"""Focus changes must never send native keyboard edits into another field."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "os/files/usr/lib/marwanos/text_input.py"
SPEC = importlib.util.spec_from_file_location("text_input", SOURCE)
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class Backend:
    def __init__(self):
        self.focus = "field"
        self.window = 42
        self.held = False
        self.edits = []
        self.releases = []

    def pointer_releases(self):
        releases, self.releases = self.releases, []
        return releases

    def contains(self, source, x, y):
        return source == self.focus and 0 <= x < 80 and 0 <= y < 80

    def metadata(self, source):
        if source != self.focus or source is None:
            return None
        return {"editable": True, "pid": 10, "type": "password", "mode": "text"}

    def focus_window(self):
        return self.window

    def mouse_held(self):
        return self.held

    def inject(self, arguments):
        self.edits.append(arguments)
        return True


class FocusBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.backend = Backend()
        self.bridge = module.FocusBridge(self.directory, 99, self.backend)
        self.bridge.focused("field")
        self.bridge.tick()

    def request(self, **values):
        return dict(token=self.bridge.context["token"], **values)

    def test_metadata_never_contains_field_values(self):
        self.assertEqual(set(self.bridge.context), {"editable", "pid", "type", "mode", "token", "window", "serial", "heartbeat"})
        self.assertEqual(self.bridge.context["type"], "password")

    def test_focus_waits_for_pointer_release(self):
        self.backend.focus = "second"
        self.backend.held = True
        serial = self.bridge.context["serial"]
        self.bridge.focused("second")
        self.bridge.tick()
        self.assertEqual(self.bridge.context["serial"], serial)
        self.backend.held = False
        self.bridge.tick()
        self.assertGreater(self.bridge.context["serial"], serial)

    def test_injects_literal_text_and_caret_edits_without_a_shell(self):
        text = '$(touch sentinel) `literal` "\\ test'
        self.assertTrue(self.bridge.execute(self.request(kind="text", text=text)))
        self.assertEqual(self.backend.edits[-1], ["type", "--clearmodifiers", "--delay", "0", "--", text])
        self.assertTrue(self.bridge.execute(self.request(kind="key", key="BackSpace")))
        self.assertFalse(self.bridge.execute(self.request(kind="key", key="Return")))

    def test_stale_field_token_or_window_never_receives_text(self):
        stale = self.request(kind="text", text="private")
        self.backend.focus = "second"
        self.bridge.focused("second")
        self.bridge.tick()
        self.assertFalse(self.bridge.execute(stale))
        self.backend.window = 43
        self.assertFalse(self.bridge.execute(self.request(kind="text", text="private")))
        self.assertEqual(self.backend.edits, [])

    def test_blur_and_readonly_fields_close_keyboard(self):
        self.backend.focus = None
        self.bridge.blurred("field")
        self.assertFalse(self.bridge.context["editable"])
        self.assertFalse(self.bridge.execute({"kind": "text", "text": "private"}))

    def test_duplicate_notifications_do_not_restart_keyboard(self):
        serial = self.bridge.context["serial"]
        token = self.bridge.context["token"]
        self.bridge.focused("field")
        self.bridge.tick()
        self.assertEqual(self.bridge.context["serial"], serial)
        self.assertEqual(self.bridge.context["token"], token)

    def test_clicking_same_field_reopens_but_keyboard_click_does_not(self):
        serial = self.bridge.context["serial"]
        module.write_json(self.directory / "overlay.json", {"rect": [100, 100, 568, 390], "heartbeat": module.time.time()})
        self.bridge.clicked(120, 120)
        self.bridge.tick()
        self.assertEqual(self.bridge.context["serial"], serial)
        self.bridge.clicked(20, 20)
        self.bridge.tick()
        self.assertGreater(self.bridge.context["serial"], serial)

    def test_short_pointer_release_reopens_only_inside_the_editor(self):
        serial = self.bridge.context["serial"]
        self.backend.releases = [(90, 90)]
        self.bridge.tick()
        self.assertEqual(self.bridge.context["serial"], serial)
        self.backend.releases = [(20, 20)]
        self.bridge.tick()
        self.assertGreater(self.bridge.context["serial"], serial)

    def test_consumed_edit_files_are_removed_before_injection(self):
        path = self.directory / "edit-000000000001.json"
        path.write_text(json.dumps(self.request(id=1, kind="text", text="secret")))
        self.bridge.tick()
        self.assertFalse(path.exists())
        self.assertNotIn("secret", (self.directory / "result.json").read_text())

    def test_shell_fields_are_left_to_the_shell_keyboard(self):
        bridge = module.FocusBridge(self.directory, 10, self.backend)
        bridge.focused("field")
        self.assertFalse(bridge.context["editable"])


if __name__ == "__main__":
    unittest.main()
