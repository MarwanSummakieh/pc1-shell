#!/usr/bin/env python3
"""Focused-editor metadata and guarded native typing. Never read field values."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import struct
import time
import uuid


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value))
    temporary.chmod(0o600)
    temporary.replace(path)


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


class FocusBridge:
    def __init__(self, directory, shell_pid, backend):
        self.directory = directory
        self.shell_pid = shell_pid
        self.backend = backend
        self.field = None
        self.context = {"editable": False, "serial": 0}
        self.pending = False
        self.last_heartbeat = 0.0

    def focused(self, source):
        metadata = self.backend.metadata(source)
        if not metadata or metadata.get("pid") == self.shell_pid:
            self.field = None
            self.pending = False
            self.publish({"editable": False})
            return
        if source == self.field and self.context.get("editable"):
            return
        self.field = source
        self.context = dict(self.context, **metadata, token=uuid.uuid4().hex)
        self.pending = True

    def blurred(self, source):
        if source == self.field:
            self.focused(None)

    def clicked(self, x, y):
        overlay = read_json(self.directory / "overlay.json")
        rect = overlay.get("rect", [])
        if len(rect) == 4 and time.time() - overlay.get("heartbeat", 0) < 2:
            if rect[0] <= x < rect[0] + rect[2] and rect[1] <= y < rect[1] + rect[3]:
                return
        # A second click in the same focused editor reopens a dismissed keyboard.
        if self.field is not None and self.backend.metadata(self.field) and self.backend.contains(self.field, x, y):
            self.pending = True

    def publish(self, metadata):
        self.context = dict(metadata, serial=self.context["serial"] + 1, heartbeat=time.time())
        write_json(self.directory / "focus.json", self.context)

    def execute(self, request):
        if not self.context.get("editable") or request.get("token") != self.context.get("token"):
            return False
        if self.field is None or not self.backend.metadata(self.field):
            return False
        # A no-focus keyboard window leaves the application's real X focus alone.
        # Never restore focus or inject into a different window on a stale request.
        if self.backend.focus_window() != self.context.get("window"):
            return False
        if request.get("kind") == "text":
            text = request.get("text")
            if not isinstance(text, str) or not text or len(text) > 4096 or "\0" in text:
                return False
            arguments = ["type", "--clearmodifiers", "--delay", "0", "--", text]
        elif request.get("kind") == "key" and request.get("key") in {"BackSpace", "Left", "Right"}:
            arguments = ["key", "--clearmodifiers", request["key"]]
        else:
            return False
        return self.backend.inject(arguments)

    def tick(self):
        for x, y in self.backend.pointer_releases():
            self.clicked(x, y)
        if self.pending and not self.backend.mouse_held():
            self.pending = False
            metadata = self.backend.metadata(self.field)
            if metadata:
                self.publish(dict(metadata, token=self.context["token"], window=self.backend.focus_window()))
        # Process requests in creation order. Delete before invoking anything;
        # text exists only briefly in this private runtime directory.
        for path in sorted(self.directory.glob("edit-*.json"))[:64]:
            request = read_json(path)
            path.unlink(missing_ok=True)
            try:
                accepted = self.execute(request)
            except Exception:
                accepted = False
            write_json(self.directory / "result.json", {"id": request.get("id"), "accepted": accepted})
        now = time.time()
        if now - self.last_heartbeat >= 1:
            self.last_heartbeat = now
            if self.field is not None and not self.backend.metadata(self.field):
                self.focused(None)
            self.context["heartbeat"] = now
            write_json(self.directory / "focus.json", self.context)
        return True


class AccessibilityBackend:
    def __init__(self):
        import gi
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi
        from Xlib import display
        from Xlib.ext import xinput
        self.atspi = Atspi
        self.display = display.Display()
        self.xinput_opcode = self.display.query_extension(xinput.extname).major_opcode
        # XI 2.1 keeps raw releases visible during another client's implicit
        # pointer grab (ordinary toolkit button clicks).
        xinput.XIQueryVersion(display=self.display.display, opcode=self.xinput_opcode, major_version=2, minor_version=1)
        self.display.screen().root.xinput_select_events([(xinput.AllMasterDevices, xinput.RawButtonReleaseMask)])
        self.display.flush()

    def pointer_releases(self):
        # AT-SPI mouse events are not emitted by every registry. XInput raw
        # releases also catch short real/XTEST clicks between timer ticks.
        from Xlib.ext import xinput
        releases = []
        while self.display.pending_events():
            event = self.display.next_event()
            if event.type != 35 or event.extension != self.xinput_opcode or event.evtype != xinput.RawButtonRelease:
                continue
            # python-xlib leaves XI_RawEvent data unparsed: device(2), time(4),
            # button(4). Only button one is observed; no key events are selected.
            if len(event.data) >= 10 and struct.unpack_from("=I", event.data, 6)[0] == 1:
                pointer = self.display.screen().root.query_pointer()
                releases.append((pointer.root_x, pointer.root_y))
        return releases

    def contains(self, source, x, y):
        try:
            rect = source.get_component_iface().get_extents(self.atspi.CoordType.SCREEN)
            return rect.x <= x < rect.x + rect.width and rect.y <= y < rect.y + rect.height
        except Exception:
            return False

    def metadata(self, source):
        if source is None:
            return None
        try:
            states = source.get_state_set()
            state = self.atspi.StateType
            if not all(states.contains(value) for value in [state.FOCUSED, state.EDITABLE, state.ENABLED, state.SENSITIVE]):
                return None
            if states.contains(state.DEFUNCT):
                return None
            attributes = source.get_attributes() or {}
            kind = "password" if source.get_role() == self.atspi.Role.PASSWORD_TEXT else "text"
            mode = attributes.get("text-input-type", attributes.get("input-type", kind))
            return {"editable": True, "pid": source.get_process_id(), "type": kind,
                    "mode": mode if mode in {"email", "url", "numeric", "decimal", "tel", "number"} else kind}
        except Exception:
            return None

    def focus_window(self):
        window = self.display.get_input_focus().focus
        return int(getattr(window, "id", 0))

    def mouse_held(self):
        from Xlib import X
        return bool(self.display.screen().root.query_pointer().mask & X.Button1Mask)

    def inject(self, arguments):
        try:
            return subprocess.run(["xdotool", *arguments], stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  timeout=2, check=False).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--shell-pid", type=int, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    args.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.directory.chmod(0o700)
    for path in args.directory.glob("edit-*.json"):
        path.unlink(missing_ok=True)
    # Opt into the accessibility bus before applications are launched. Toolkit
    # bridges and Chromium can then expose focused editable controls.
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    status = bus.get_object("org.a11y.Bus", "/org/a11y/bus")
    dbus.Interface(status, "org.freedesktop.DBus.Properties").Set("org.a11y.Status", "IsEnabled", True)
    backend = AccessibilityBackend()
    from gi.repository import GLib
    bridge = FocusBridge(args.directory, args.shell_pid, backend)
    bridge.publish({"editable": False})

    def event_received(event, *_):
        try:
            if event.type.startswith("mouse:button:1r") or event.type.startswith("mouse:b1r"):
                bridge.clicked(event.detail1, event.detail2)
            elif event.type.startswith("focus:") or event.detail1:
                bridge.focused(event.source)
            else:
                bridge.blurred(event.source)
        except Exception:
            # A disappearing app is ordinary focus loss, never a reason to type.
            bridge.focused(None)

    listener = backend.atspi.EventListener.new(event_received, None)
    listener.register("object:state-changed:focused")
    listener.register("focus:")
    listener.register("mouse:b1r")

    def tick():
        try:
            os.kill(args.shell_pid, 0)
        except ProcessLookupError:
            loop.quit()
            return False
        return bridge.tick()

    GLib.timeout_add(25, tick)
    loop = GLib.MainLoop()
    try:
        loop.run()
    finally:
        backend.display.close()
        for path in args.directory.glob("edit-*.json"):
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
