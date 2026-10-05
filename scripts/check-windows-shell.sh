#!/usr/bin/env bash
# Run with the same Godot editor version as os/Containerfile, on Linux.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-shell-check.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
# Import a disposable project so checks do not generate sidecars in the checkout.
cp -a "$repo_root/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
# These checks exercise installer UI without the separately built CEF engine.
if [ ! -s "$work/shell/bin/libmowser.so" ]; then
    rm -f -- "$work/shell/bin/mowser.gdextension"
fi
export MARWANOS_WINDOWS_HOME="$work/state"
export MARWANOS_SHELL_WINDOWED=1
"$godot_bin" --headless --path "$work/shell" --import > "$work/import.log" 2>&1
"$godot_bin" --headless --path "$work/shell" \
    --script "$repo_root/tests/windows_shell.gd" --audio-driver Dummy > "$work/check.log" 2>&1 \
    || { cat "$work/check.log"; exit 1; }
cat "$work/check.log"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/check.log"; then
    cat "$work/import.log"
    exit 1
fi
grep -q 'Windows shell checks: 0 failure(s)' "$work/check.log"
"$godot_bin" --headless --path "$work/shell" \
    --script "$repo_root/tests/windows_setup_wizard.gd" --audio-driver Dummy > "$work/wizard.log" 2>&1 \
    || { cat "$work/wizard.log"; exit 1; }
cat "$work/wizard.log"
! grep -qE 'SCRIPT ERROR|Parse Error|FAIL:' "$work/wizard.log"
grep -q 'Windows setup wizard checks: 0 failure(s)' "$work/wizard.log"
"$godot_bin" --headless --path "$work/shell" \
    --script "$repo_root/tests/windows_setup_layout.gd" --audio-driver Dummy > "$work/layout.log" 2>&1 \
    || { cat "$work/layout.log"; exit 1; }
cat "$work/layout.log"
! grep -qE 'SCRIPT ERROR|Parse Error|FAIL:' "$work/layout.log"
grep -q 'Windows setup layout checks: 0 failure(s)' "$work/layout.log"
