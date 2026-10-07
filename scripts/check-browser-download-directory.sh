#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-browser-directory.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export MARWANOS_SHELL_WINDOWED=1 MARWANOS_SHELL_STATUS_DIR="$work/status"
export MARWANOS_HISTORY_HOME="$work/history" MARWANOS_WINDOWS_HOME="$work/windows"
export HOME="$work/home"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
"${GODOT_BIN:-godot}" --headless --path "$work/shell" --import > "$work/import.log" 2>&1 || { cat "$work/import.log"; exit 1; }
display_args=(--headless)
if [[ "${PC1_BROWSER_DIRECTORY_GRAPHICAL:-0}" == 1 ]]; then
    display_args=(--rendering-method gl_compatibility)
fi
for scenario in missing custom; do
    if [[ "$scenario" == custom ]]; then
        printf 'XDG_DOWNLOAD_DIR="%s/Custom downloads"\n' "$HOME" > "$XDG_CONFIG_HOME/user-dirs.dirs"
    fi
    export PC1_BROWSER_DIRECTORY_SCENARIO="$scenario"
    "${GODOT_BIN:-godot}" "${display_args[@]}" --path "$work/shell" --script "$repo/tests/browser_download_directory.gd" --audio-driver Dummy > "$work/$scenario.log" 2>&1 || { cat "$work/$scenario.log"; exit 1; }
    cat "$work/$scenario.log"
    if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/$scenario.log"; then
        cat "$work/import.log"
        exit 1
    fi
    grep -q 'Browser download directory checks: 0 failure(s)' "$work/$scenario.log"
done
