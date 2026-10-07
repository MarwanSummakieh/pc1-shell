#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-achievement-toast.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
godot_env=(env HOME="$work/home")
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache" XDG_STATE_HOME="$work/state"
export XDG_RUNTIME_DIR="$work/runtime"
mkdir -p "$work/home" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export MARWANOS_SHELL_WINDOWED=1 MARWANOS_SHELL_STATUS_DIR="$work/status"
export MARWANOS_METADATA_HOME="$work/metadata" MARWANOS_HISTORY_HOME="$work/history"
export MARWANOS_WINDOWS_HOME="$work/windows" MARWANOS_ACHIEVEMENTS_HOME="$work/achievements"
"${godot_env[@]}" "${GODOT_BIN:-godot}" --headless --path "$work/shell" --import > "$work/import.log" 2>&1 || { cat "$work/import.log"; exit 1; }
display=(--headless)
if [[ "${MARWANOS_TOAST_NATIVE_TEST:-0}" == 1 ]]; then
    : "${DISPLAY:?native regression requires an isolated Xvfb display}"
    display=(--display-driver x11 --rendering-method gl_compatibility)
fi
timeout 60 "${godot_env[@]}" "${GODOT_BIN:-godot}" "${display[@]}" --path "$work/shell" --script "$repo/tests/achievement_toast_shell.gd" --audio-driver Dummy > "$work/check.log" 2>&1 || { cat "$work/check.log"; exit 1; }
cat "$work/check.log"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/check.log"; then
    cat "$work/import.log"
    exit 1
fi
grep -q 'Achievement toast shell checks: 0 failure(s)' "$work/check.log"
if [[ "${MARWANOS_TOAST_NATIVE_TEST:-0}" == 1 ]]; then
    grep -q 'native=true' "$work/check.log"
fi
