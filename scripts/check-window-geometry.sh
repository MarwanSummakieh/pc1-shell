#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-geometry-check.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export MARWANOS_SHELL_WINDOWED=1
"${GODOT_BIN:-godot}" --headless --path "$work/shell" --import > "$work/import.log" 2>&1
xvfb-run -a -e "$work/xvfb.log" -s '-screen 0 1920x1080x24 -nolisten tcp' \
    "${GODOT_BIN:-godot}" --path "$work/shell" --script "$repo/tests/window_geometry.gd" \
    --rendering-method gl_compatibility --audio-driver Dummy > "$work/check.log" 2>&1 \
    || { cat "$work/xvfb.log" "$work/check.log"; exit 1; }
cat "$work/check.log"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/check.log"; then
    cat "$work/import.log"
    exit 1
fi
grep -q 'Window geometry checks: 0 failure(s)' "$work/check.log"
