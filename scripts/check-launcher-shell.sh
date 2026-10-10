#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-launcher-check.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
export HOME="$work/home" XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export MARWANOS_SHELL_WINDOWED=1 MARWANOS_PROFILES_HOME="$work/profiles"
export MARWANOS_WINDOWS_HOME="$work/windows" MARWANOS_METADATA_HOME="$work/metadata"
export MARWANOS_HISTORY_HOME="$work/history" MARWANOS_ACHIEVEMENTS_HOME="$work/achievements"
export MARWANOS_SHELL_STATUS_DIR="$work/status" MARWANOS_LAUNCHER_TEST_HOME="$work/fixture"
mkdir -p "$HOME"
"${GODOT_BIN:-godot}" --headless --path "$work/shell" --editor --import --quit > "$work/import.log" 2>&1
timeout 45 "${GODOT_BIN:-godot}" --headless --path "$work/shell" --script "$repo/tests/launcher_process_group.gd" \
    --audio-driver Dummy > "$work/check.log" 2>&1 || { cat "$work/check.log"; exit 1; }
cat "$work/check.log"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/check.log"; then
    cat "$work/import.log"
    exit 1
fi
grep -q 'Launcher process group checks: 0 failure(s)' "$work/check.log"
