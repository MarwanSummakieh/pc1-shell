#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-steam-pane-check.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export XDG_RUNTIME_DIR="$work/runtime" MARWANOS_SHELL_WINDOWED=1
export HOME="$work/home"
mkdir -p "$XDG_RUNTIME_DIR" "$HOME"
unset MARWANOS_COMPOSITOR MARWANOS_STEAM_EMBED MARWANOS_STEAM_EMBED_HELPER
xvfb-run -a python3 "$repo/tests/steam_embed_native.py"
"${GODOT_BIN:-godot}" --headless --path "$work/shell" --import > "$work/import.log" 2>&1
"${GODOT_BIN:-godot}" --headless --path "$work/shell" --script "$repo/tests/steam_embed_shell.gd" \
    --audio-driver Dummy > "$work/check.log" 2>&1 || { cat "$work/check.log"; exit 1; }
cat "$work/check.log"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/check.log"; then
    cat "$work/import.log"
    exit 1
fi
grep -q 'Steam embedding shell checks: 0 failure(s)' "$work/check.log"
