#!/usr/bin/env python3
"""Host native Steam in an X11 pane, independently of Godot window lifetime.

The host is a positioned, override-redirect sibling of Godot. Steam is its
native child; no screenshots, texture copies, or second compositor are used.
The owning X connection puts Steam in its save set before reparenting it.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def read_json(path):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value))
    temporary.chmod(0o600)
    temporary.replace(path)


def valid_rect(value):
    return (isinstance(value, list) and len(value) == 4
            and all(isinstance(n, int) and not isinstance(n, bool) for n in value)
            and 320 <= value[2] <= 16384 and 240 <= value[3] <= 16384
            and all(abs(n) <= 32768 for n in value[:2]))


def steam_game_id(value):
    return value if isinstance(value, int) and 0 < value < 2**32 and value != 769 else 0


class Host:
    def __init__(self, folder, shell_pid):
        from Xlib import X, Xatom, display, error
        self.X, self.Xatom, self.error = X, Xatom, error
        self.connection = display.Display()
        self.root = self.connection.screen().root
        self.folder, self.shell_pid = folder, shell_pid
        self.request = folder / "request.json"
        self.state_file = folder / "state.json"
        self.host = self.root.create_window(
            0, 0, 640, 480, 0, self.connection.screen().root_depth,
            X.InputOutput, X.CopyFromParent, background_pixel=0x151a20,
            override_redirect=True,
            event_mask=X.SubstructureNotifyMask | X.SubstructureRedirectMask)
        self.host.set_wm_class("pc1-steam-host", "PC1SteamHost")
        self.host.set_wm_name("PC1 Steam pane")
        self.host.change_property(self.atom("_NET_WM_PID"), Xatom.CARDINAL, 32, [os.getpid()])
        self.steam = None
        self.original = None
        self.game = None
        self.action = ""
        self.phase, self.detail = "idle", ""
        self.deadline = 0.0
        self.starter = None
        self.rect = [0, 0, 640, 480]
        self.visible = False
        self.focused = False
        self.running = True
        self.game_id = 0
        self.last_state = None

    def atom(self, name):
        return self.connection.intern_atom(name)

    def prop(self, window, name):
        try:
            value = window.get_full_property(self.atom(name), self.X.AnyPropertyType)
            return list(value.value) if value is not None and value.format == 32 else []
        except (self.error.XError, self.error.DisplayError):
            return []

    def owned(self, window):
        pids = self.prop(window, "_NET_WM_PID")
        try:
            return bool(pids) and Path("/proc", str(pids[0])).stat().st_uid == os.getuid()
        except OSError:
            return False

    def is_steam(self, window):
        if not self.owned(window):
            return False
        try:
            wmclass = window.get_wm_class() or ()
            pids = self.prop(window, "_NET_WM_PID")
            comm = Path("/proc", str(pids[0]), "comm").read_text().strip()
            return (comm in {"steam", "steamwebhelper"}
                    and any("steam" in item.lower() for item in wmclass)
                    and not steam_game_id(next(iter(self.prop(window, "STEAM_GAME")), 0)))
        except (OSError, self.error.XError):
            return False

    def clients(self):
        return [self.connection.create_resource_object("window", xid)
                for xid in self.prop(self.root, "_NET_CLIENT_LIST")]

    def discover(self):
        candidates = []
        windows = {window.id: window for window in self.clients()}
        # A detached, hidden Steam UI is withdrawn from the WM client list.
        windows.update({window.id: window for window in self.root.query_tree().children})
        for window in windows.values():
            if not self.is_steam(window):
                continue
            try:
                geometry = window.get_geometry()
                if geometry.width < 500 or geometry.height < 300 or window.get_wm_transient_for():
                    continue
                score = geometry.width * geometry.height
                title = window.get_wm_name() or ""
                if isinstance(title, bytes):
                    title = title.decode("utf-8", errors="replace")
                if "big picture" in title.lower() or self.prop(window, "STEAM_BIGPICTURE"):
                    score += 100_000_000
                candidates.append((score, window))
            except self.error.XError:
                continue
        return max(candidates, key=lambda item: item[0])[1] if candidates else None

    def attach(self, window):
        from Xlib import Xutil
        geometry = window.get_geometry()
        self.original = {"override": window.get_attributes().override_redirect,
                         "state": self.prop(window, "_NET_WM_STATE"),
                         "width": geometry.width, "height": geometry.height}
        recovery = read_json(self.folder / "original.json")
        if recovery.get("client") == window.id and self.original["override"]:
            saved = recovery.get("attributes", {})
            if (valid_rect([0, 0, saved.get("width"), saved.get("height")])
                    and isinstance(saved.get("state"), list)
                    and all(isinstance(atom, int) for atom in saved["state"])):
                self.original = saved
        write_json(self.folder / "original.json", {"client": window.id, "attributes": self.original})
        window.unmap()
        window.change_save_set(self.X.SetModeInsert)
        window.set_wm_state(state=Xutil.WithdrawnState, icon=0)
        window.change_attributes(override_redirect=True)
        window.change_property(self.atom("_NET_WM_STATE"), self.Xatom.ATOM, 32, [])
        window.reparent(self.host, 0, 0)
        window.configure(x=0, y=0, width=self.rect[2], height=self.rect[3], border_width=0)
        self.connection.sync()
        self.steam = window
        self.phase, self.detail = "ready", ""
        print(f"Steam attached: client={window.id} host={self.host.id}", flush=True)

    def detach(self):
        if self.steam is None:
            return
        try:
            self.host.unmap()
            self.steam.unmap()
            self.steam.reparent(self.root, 0, 0)
            self.steam.change_attributes(override_redirect=bool(self.original["override"]))
            self.steam.change_property(self.atom("_NET_WM_STATE"), self.Xatom.ATOM, 32,
                                       self.original["state"])
            self.steam.configure(width=self.original["width"], height=self.original["height"])
            self.steam.change_save_set(self.X.SetModeDelete)
            # Leave hidden when the shell exits; opening Steam restores its UI.
            self.connection.sync()
        except self.error.XError:
            pass
        self.steam = None
        (self.folder / "original.json").unlink(missing_ok=True)

    def start(self):
        if self.steam is not None and not self.alive(self.steam):
            self.steam = None
        if self.steam is not None:
            return
        candidate = self.discover()
        if candidate is not None:
            self.attach(candidate)
            return
        if self.starter is None or self.starter.poll() is not None:
            self.starter = subprocess.Popen(["/usr/lib/marwanos/steamctl", "signin"])
        self.phase, self.detail = "loading", ""
        self.deadline = time.monotonic() + 120

    def game_window(self):
        for window in self.clients():
            appid = steam_game_id(next(iter(self.prop(window, "STEAM_GAME")), 0))
            if appid and self.owned(window):
                return window, appid
        return None, 0

    def alive(self, window):
        if window is None:
            return False
        try:
            window.get_attributes()
            return True
        except self.error.XError:
            return False

    def set_focus(self, window):
        try:
            window.set_input_focus(self.X.RevertToParent, self.X.CurrentTime)
            self.connection.flush()
        except self.error.XError:
            pass

    def contains_focus(self, window):
        """CEF focuses nested input windows rather than the top-level client."""
        if self.steam is None:
            return False
        try:
            for _ in range(32):
                if getattr(window, "id", 0) == self.steam.id:
                    return True
                if not getattr(window, "id", 0) or window.id == self.root.id:
                    break
                window = window.query_tree().parent
        except self.error.XError:
            pass
        return False

    def tick(self, request):
        if valid_rect(request.get("rect")):
            self.rect = request["rect"]
        command_id = str(request.get("action_id", ""))
        command = request.get("action", "") if command_id != self.action else ""
        self.action = command_id
        if command == "start":
            self.start()
        if command == "quit":
            self.running = False
            return
        if command == "detach":
            self.detach()
            self.phase = "idle"
        if command == "stop":
            self.host.unmap()
            self.detach()
            subprocess.Popen(["/usr/lib/marwanos/steamctl", "stop"])
            self.phase = "idle"
        if self.steam is not None and not self.alive(self.steam):
            self.steam = None
            self.phase, self.detail = "error", "Steam closed. Open it again."
        if self.steam is None and self.phase == "loading":
            candidate = self.discover()
            if candidate is not None:
                self.attach(candidate)
            elif time.monotonic() > self.deadline:
                self.phase, self.detail = "error", "Steam did not open. Try again."
        self.game, self.game_id = self.game_window()
        if command == "close_game" and self.game is not None:
            from Xlib.protocol import event
            self.game.send_event(event.ClientMessage(
                window=self.game, client_type=self.atom("WM_PROTOCOLS"),
                data=(32, [self.atom("WM_DELETE_WINDOW"), self.X.CurrentTime, 0, 0, 0])))
            self.connection.flush()
        self.visible = bool(request.get("visible")) and self.steam is not None and self.game is None
        self.focused = bool(request.get("focus")) and self.visible
        if self.visible:
            x, y, width, height = self.rect
            self.host.configure(x=x, y=y, width=width, height=height, stack_mode=self.X.Above)
            self.steam.configure(x=0, y=0, width=width, height=height, border_width=0)
            self.steam.map()
            self.host.map()
            if command == "focus":
                self.set_focus(self.steam)
        else:
            self.host.unmap()
        if command == "shell":
            owner = self.connection.create_resource_object("window", int(request.get("owner", 0)))
            self.set_focus(owner)
        if command == "menu" and self.visible:
            focused = self.connection.get_input_focus().focus
            if self.contains_focus(focused):
                # Steam's native Big Picture menu shortcut. Guide stays with PC1.
                subprocess.run(["xdotool", "key", "--clearmodifiers", "ctrl+1"],
                               timeout=2, check=False)
        # Configure requests from Steam cannot resize the pane over navigation.
        while self.connection.pending_events():
            event = self.connection.next_event()
            if event.type == self.X.ConfigureRequest:
                if self.steam is not None and event.window.id == self.steam.id:
                    event.window.configure(x=0, y=0, width=self.rect[2], height=self.rect[3], border_width=0)
            elif event.type == self.X.MapRequest:
                event.window.map()
        self.connection.flush()
        focused = self.connection.get_input_focus().focus
        self.publish({"phase": self.phase, "detail": self.detail,
                      "host": self.host.id, "client": self.steam.id if self.steam else 0,
                      "parent": self.host.id if self.steam else 0,
                      "visible": self.visible, "focused": self.focused,
                      "input_focus": getattr(focused, "id", 0),
                      "client_has_focus": self.contains_focus(focused),
                      "rect": self.rect, "game_window": self.game.id if self.game else 0,
                      "game_id": self.game_id, "action_id": self.action})

    def publish(self, state):
        # Include a heartbeat even while the state is unchanged.
        state["heartbeat"] = time.time()
        write_json(self.state_file, state)

    def run(self):
        def stop(_sig, _frame):
            self.running = False
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        try:
            while self.running:
                try:
                    os.kill(self.shell_pid, 0)
                    if self.request.exists() and time.time() - self.request.stat().st_mtime < 2:
                        self.tick(read_json(self.request))
                    else:
                        self.host.unmap()
                        self.connection.flush()
                    time.sleep(.1)
                except ProcessLookupError:
                    break
                except self.error.XError as exc:
                    self.phase, self.detail = "error", "Steam window changed. Open it again."
                    print(f"Steam host: {exc}", flush=True)
        finally:
            self.detach()
            self.host.destroy()
            self.connection.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--shell-pid", type=int, required=True)
    args = parser.parse_args()
    if os.environ.get("MARWANOS_COMPOSITOR") != "x11":
        parser.error("native Steam hosting requires the Xorg session")
    args.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    Host(args.directory, args.shell_pid).run()


if __name__ == "__main__":
    main()
