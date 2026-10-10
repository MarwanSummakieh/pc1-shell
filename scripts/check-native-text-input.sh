#!/usr/bin/env bash
# Real accessibility focus, native floating window and XTEST typing on an
# isolated display/session bus. Never connects to the appliance's live desktop.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-native-text-input.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export XDG_RUNTIME_DIR="$work/runtime"
mkdir -m 700 "$XDG_RUNTIME_DIR"
export MARWANOS_SHELL_WINDOWED=1 LIBGL_ALWAYS_SOFTWARE=1
export GSETTINGS_BACKEND=memory GTK_USE_PORTAL=0 GDK_BACKEND=x11 NO_AT_BRIDGE=0
export PC1_NATIVE_INPUT_LOG="$work/native-godot.log"
godot_bin="${GODOT_BIN:-godot}"
timeout 90 "$godot_bin" --headless --path "$work/shell" --editor --import --quit > "$work/import.log" 2>&1
timeout 90 dbus-run-session -- xvfb-run -a -s '-screen 0 1920x1080x24' \
    python3 "$repo/tests/text_input_native.py" --godot "$godot_bin" --project "$work/shell" > "$work/native.log" 2>&1 || {
    cat "$work/native.log" "$work/native-godot.log"
    exit 1
}
cat "$work/native.log"
! grep -qE 'ERROR:|Parse Error|FAIL:' "$work/import.log" "$work/native-godot.log"
grep -q 'Native text input checks: 0 failure(s)' "$work/native.log"
