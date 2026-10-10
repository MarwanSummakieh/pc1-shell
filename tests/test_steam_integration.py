"""Native, legacy and external Steam libraries use one launch contract."""
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[1] / "os/files/usr/lib/marwanos/steamctl"
SPEC = importlib.util.spec_from_loader("steamctl", importlib.machinery.SourceFileLoader("steamctl", str(PATH)))
steam = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(steam)


class SteamIntegrationTests(unittest.TestCase):
    def test_all_launch_actions_keep_shared_home_without_loading_local_profiles(self):
        for action in (["signin"], ["background"], ["launch", "42"]):
            for client in (["steam"], ["flatpak", "run", "com.valvesoftware.Steam"]):
                with self.subTest(action=action, client=client), patch.dict(os.environ, {
                    "MARWANOS_PROFILE_ID": "user-" + "a" * 32,
                    "MARWANOS_PROFILES_HELPER": "/nonexistent/profiles.py",
                }), patch.object(steam.sys, "argv", [str(PATH), *action]), patch.object(
                    steam, "command", side_effect=lambda args: [*client, *args]
                ), patch.object(steam.os, "execvp") as execute:
                    home = os.environ.get("HOME")
                    steam.main()
                    argv = [*client, "-silent" if action[0] == "background" else "-gamepadui"]
                    if action[0] == "launch":
                        argv.append("steam://rungameid/42")
                    execute.assert_called_once_with(client[0], argv)
                    self.assertEqual(os.environ.get("HOME"), home)

    def test_native_legacy_and_spaced_custom_libraries_are_discovered(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            config = home / ".local/share/Steam/steamapps/libraryfolders.vdf"
            config.parent.mkdir(parents=True)
            custom = home / "Extra Games"
            config.write_text('"libraryfolders" { "1" { "path" "' + str(custom) + '" } }')
            paths = list(steam.libraries(home))
            self.assertIn(config.parent, paths)
            self.assertIn(custom / "steamapps", paths)
            self.assertIn(home / ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps", paths)

    def test_native_binary_is_preferred_and_legacy_remains_supported(self):
        with patch.object(steam.shutil, "which", return_value="/usr/bin/steam"):
            self.assertEqual(steam.command(["-gamepadui"]), ["steam", "-cef-force-accessibility", "-gamepadui"])
        with patch.object(steam.shutil, "which", side_effect=lambda name: "/usr/bin/flatpak" if name == "flatpak" else None):
            self.assertEqual(steam.command(["-gamepadui"]), ["flatpak", "run", "com.valvesoftware.Steam", "-cef-force-accessibility", "-gamepadui"])

    def test_symlinked_native_root_does_not_duplicate_library(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            native = home / ".local/share/Steam"
            native.mkdir(parents=True)
            (home / ".steam").mkdir()
            (home / ".steam/steam").symlink_to(native)
            paths = list(steam.libraries(home))
            self.assertEqual(paths.count(native / "steamapps"), 1)


if __name__ == "__main__":
    unittest.main()
