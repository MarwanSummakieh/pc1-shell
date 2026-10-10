#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-downloads-shell.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export XDG_RUNTIME_DIR="$work/runtime" MARWANOS_SHELL_WINDOWED=1 MARWANOS_SHELL_STATUS_DIR="$work/status"
export MARWANOS_WINDOWS_HOME="$work/windows" MARWANOS_METADATA_HOME="$work/metadata" MARWANOS_HISTORY_HOME="$work/history"
"${GODOT_BIN:-godot}" --headless --path "$work/shell" --editor --import --quit > "$work/import.log" 2>&1
timeout 60 "${GODOT_BIN:-godot}" --headless --path "$work/shell" --script "$repo/tests/downloads_shell.gd" --audio-driver Dummy > "$work/check.log" 2>&1 || { cat "$work/check.log"; exit 1; }
cat "$work/check.log"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/check.log"; then
    cat "$work/import.log"
    exit 1
fi
grep -q 'Downloads shell checks: 0 failure(s)' "$work/check.log"
