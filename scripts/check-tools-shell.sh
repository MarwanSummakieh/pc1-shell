#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-tools-check.XXXXXX")"
cross="$(mktemp -d /dev/shm/pc1-tools-cross.XXXXXX)"
trap 'rm -rf -- "$work" "$cross"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
# tools_shell.gd includes dedicated file_keyboard_checks.gd operation and picker tests.
# Headless UI/file tests also cover the engine-unavailable recovery state.
# Real browser rendering is exercised separately with its payload installed.
rm -f -- "$work/shell/bin/mowser.gdextension"
mkdir -p "$work/files/source" "$work/files/destination"
mkdir -p "$work/files/with-link"
printf 'Original data\n' > "$work/files/with-link/original.txt"
ln -s original.txt "$work/files/with-link/link.txt"
export MARWANOS_SHELL_FILES_HOME="$work/files"
export MARWANOS_SHELL_WINDOWED=1
export PC1_TOOLS_TEST_HOME="$work/files"
export PC1_TOOLS_CROSS_HOME="$cross"
export XDG_DATA_HOME="$work/data"
export XDG_CONFIG_HOME="$work/config"
export XDG_CACHE_HOME="$work/cache"
timeout 120 "$godot_bin" --headless --path "$work/shell" --import > "$work/import.log" 2>&1
timeout 90 "$godot_bin" --headless --path "$work/shell" --script "$repo/tests/tools_shell.gd" \
    --audio-driver Dummy > "$work/check.log" 2>&1 || { cat "$work/check.log"; exit 1; }
cat "$work/check.log"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/check.log"; then
    cat "$work/import.log"
    exit 1
fi
grep -q 'Tools shell checks: 0 failure(s)' "$work/check.log"

timeout 90 "$godot_bin" --headless --path "$work/shell" --script "$repo/tests/keyboard_input_timing.gd" \
    --audio-driver Dummy > "$work/keyboard-timing.log" 2>&1 || { cat "$work/keyboard-timing.log"; exit 1; }
cat "$work/keyboard-timing.log"
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/keyboard-timing.log"
grep -q 'Keyboard input timing checks: 0 failure(s)' "$work/keyboard-timing.log"
timeout 90 "$godot_bin" --headless --path "$work/shell" --script "$repo/tests/browser_shell.gd" \
    --audio-driver Dummy > "$work/browser.log" 2>&1 || { cat "$work/browser.log"; exit 1; }
cat "$work/browser.log"
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/browser.log"
grep -q 'Browser shell checks: 0 failure(s)' "$work/browser.log"

python3 -m unittest discover -s "$repo/tests" -p test_browser_extensions.py
python3 -m unittest discover -s "$repo/tests" -p test_text_input.py
export MARWANOS_BROWSER_EXTENSIONS_HELPER="$repo/os/files/usr/lib/marwanos/browser_extensions.py"
timeout 90 "$godot_bin" --headless --path "$work/shell" --script "$repo/tests/browser_extensions_shell.gd" \
    --audio-driver Dummy > "$work/extensions.log" 2>&1 || { cat "$work/extensions.log"; exit 1; }
cat "$work/extensions.log"
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/extensions.log"
grep -q 'Browser extension shell checks: 0 failure(s)' "$work/extensions.log"
