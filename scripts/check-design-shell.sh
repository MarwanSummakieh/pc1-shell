#!/usr/bin/env bash
# Responsive console layout and focus checks in an isolated shell copy.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-design-shell.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export XDG_RUNTIME_DIR="$work/runtime"
export MARWANOS_SHELL_WINDOWED=1 MARWANOS_SHELL_STATUS_DIR="$work/status"
export MARWANOS_METADATA_HOME="$work/metadata" MARWANOS_HISTORY_HOME="$work/history"
export MARWANOS_WINDOWS_HOME="$work/windows"
unset MARWANOS_COMPOSITOR
"${GODOT_BIN:-godot}" --headless --path "$work/shell" --editor --import --quit > "$work/import.log" 2>&1 || { cat "$work/import.log"; exit 1; }
timeout 60 "${GODOT_BIN:-godot}" --headless --path "$work/shell" --script "$repo/tests/design_shell.gd" --audio-driver Dummy > "$work/check.log" 2>&1 || { cat "$work/check.log"; exit 1; }
cat "$work/check.log"
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/import.log" "$work/check.log"; then
    cat "$work/import.log"
    exit 1
fi
grep -q 'Design shell checks: 0 failure(s)' "$work/check.log"
mkdir -p "$work/files"
export MARWANOS_SHELL_FILES_HOME="$work/files"
timeout 60 "${GODOT_BIN:-godot}" --headless --path "$work/shell" --script "$repo/tests/files_design_shell.gd" --audio-driver Dummy > "$work/files.log" 2>&1 || { cat "$work/files.log"; exit 1; }
cat "$work/files.log"
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/files.log"
grep -q 'Files design checks: 0 failure(s)' "$work/files.log"
timeout 60 "${GODOT_BIN:-godot}" --headless --path "$work/shell" --script "$repo/tests/files_trash_shell.gd" --audio-driver Dummy > "$work/trash.log" 2>&1 || { cat "$work/trash.log"; exit 1; }
cat "$work/trash.log"
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/trash.log"
grep -q 'Files trash checks: 0 failure(s)' "$work/trash.log"
timeout 60 "${GODOT_BIN:-godot}" --headless --path "$work/shell" --script "$repo/tests/console_refinement_shell.gd" --audio-driver Dummy > "$work/refinement.log" 2>&1 || { cat "$work/refinement.log"; exit 1; }
cat "$work/refinement.log"
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|FAIL:' "$work/refinement.log"
grep -q 'Console refinement checks: 0 failure(s)' "$work/refinement.log"
