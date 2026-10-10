#!/usr/bin/env python3
"""Real GTK fields, AT-SPI events and a no-focus Godot keyboard on isolated X11.

Run with: dbus-run-session -- xvfb-run -a python3 tests/text_input_native.py
          --godot /path/to/godot --project /isolated/shell
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", required=True)
    args = parser.parse_args()
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="pc1-native-input-") as temporary:
        directory = Path(temporary)
        window = Gtk.Window(title="Native keyboard fixture")
        window.set_default_size(500, 250)
        window.move(80, 80)
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
        column.set_border_width(20)
        entry = Gtk.Entry()
        password = Gtk.Entry()
        password.set_visibility(False)
        readonly = Gtk.Entry()
        readonly.set_editable(False)
        readonly.set_text("Read only")
        for field in [entry, password, readonly]:
            column.pack_start(field, False, False, 0)
        window.add(column)
        window.show_all()
        window_id = window.get_window().get_xid()
        environment = dict(os.environ, PC1_NATIVE_INPUT_CHECK=str(directory),
                           XDG_RUNTIME_DIR=str(directory / "runtime"),
                           XDG_DATA_HOME=str(directory / "data"), XDG_CONFIG_HOME=str(directory / "config"),
                           XDG_CACHE_HOME=str(directory / "cache"), MARWANOS_SHELL_WINDOWED="1",
                           MARWANOS_COMPOSITOR="x11", MARWANOS_TEXT_INPUT_HELPER=str(repo / "os/files/usr/lib/marwanos/text_input.py"),
                           MARWANOS_SHELL_STATUS_DIR=str(directory / "status"),
                           MARWANOS_SHELL_FILES_HOME=str(directory), MARWANOS_WINDOWS_HOME=str(directory / "windows"))
        Path(environment["XDG_RUNTIME_DIR"]).mkdir(mode=0o700)
        state = {}

        def pump():
            while Gtk.events_pending():
                Gtk.main_iteration_do(False)

        def wait(predicate, label):
            nonlocal state
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                pump()
                try:
                    state = json.loads((directory / "state.json").read_text())
                except (OSError, ValueError):
                    pass
                if predicate():
                    print("PASS: " + label, flush=True)
                    return
                time.sleep(.03)
            raise AssertionError(label + ": " + repr(state))

        def xdo(*arguments):
            subprocess.run(["xdotool", *map(str, arguments)], check=True, timeout=3)
            pump()

        def click_field(field):
            pump()
            _, origin_x, origin_y = window.get_window().get_origin()
            allocation = field.get_allocation()
            xdo("windowraise", window_id, "windowfocus", window_id, "mousemove", origin_x + allocation.x + 30,
                origin_y + allocation.y + allocation.height // 2, "click", 1)

        def click_key(label):
            x, y = state[label]
            xdo("mousemove", round(x), round(y), "click", 1)

        log = (directory / "godot.log").open("w")
        process = subprocess.Popen([args.godot, "--path", args.project, "--script", str(repo / "tests/text_input_native.gd"),
                                    "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility"],
                                   env=environment, stdout=log, stderr=subprocess.STDOUT)
        try:
            wait(lambda: state.get("ready"), "native shell fixture starts")
            # Wait for the helper to subscribe before delivering actual pointer input.
            time.sleep(1)
            click_field(entry)
            wait(lambda: state.get("open") and not state.get("masked"), "clicking a native text field opens the floating keyboard")
            assert state["unfocusable"] and state["paused"] and state["blocked"]
            click_key("q")
            click_key("a")
            wait(lambda: entry.get_text() == "qa", "native keyboard clicks type into the original app without taking focus")
            (directory / "command.json").write_text(json.dumps({"id": 1, "action": "delete"}))
            wait(lambda: entry.get_text() == "q", "controller deletion reaches the native editor")
            next_character = {"q": "w", "a": "s"}[state["focused_key"]]
            (directory / "command.json").write_text(json.dumps({"id": 2, "action": "type_next"}))
            wait(lambda: entry.get_text() == "q" + next_character, "controller navigation and selection type through the floating window")
            first_token = state["token"]
            click_field(password)
            wait(lambda: state.get("open") and state.get("masked") and state.get("token") != first_token,
                 "switching native fields retargets the keyboard and detects passwords")
            click_key("a")
            wait(lambda: password.get_text() == "a" and state.get("draft_empty"), "password typing leaves no draft in the shell")
            click_key("Done")
            wait(lambda: not state.get("open") and not state.get("blocked") and not state.get("paused"),
                 "Done closes the native keyboard and restores application controller input")
            click_field(password)
            wait(lambda: state.get("open"), "clicking the same field reopens a dismissed keyboard")
            click_field(readonly)
            wait(lambda: not state.get("open"), "read-only native fields never open a keyboard")
            (directory / "command.json").write_text(json.dumps({"id": 3, "action": "quit"}))
            process.wait(timeout=5)
            log.flush()
            output = (directory / "godot.log").read_text()
            assert process.returncode == 0, output[-6000:]
            assert not any(message in output for message in ["ERROR:", "Parse Error"]), output[-6000:]
            print("Native text input checks: 0 failure(s)")
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            log.close()
            output = (directory / "godot.log").read_text()
            destination = os.environ.get("PC1_NATIVE_INPUT_LOG")
            if destination:
                Path(destination).write_text(output)
            window.destroy()


if __name__ == "__main__":
    # Start the standard service explicitly inside this private bus. Fedora's
    # SELinux policy can reject dbus-daemon spawning desktop services in an SSH
    # test session, while the installed desktop uses systemd user activation.
    launcher_path = next(path for path in [Path("/usr/libexec/at-spi-bus-launcher"),
                                          Path("/usr/lib/at-spi2-core/at-spi-bus-launcher")] if path.exists())
    launcher = subprocess.Popen([str(launcher_path), "--launch-immediately"])
    registry = None
    try:
        time.sleep(.3)
        registry_path = launcher_path.with_name("at-spi2-registryd")
        registry = subprocess.Popen([str(registry_path)])
        main()
    finally:
        for child in [registry, launcher]:
            if child is not None and child.poll() is None:
                child.terminate()
                child.wait(timeout=5)
