#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-keyboard-preview.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cp -a "$repo/shell" "$work/shell"
rm -rf -- "$work/shell/.godot"
rm -f -- "$work/shell/bin/mowser.gdextension"
mkdir -p "$work/home/Downloads" "$work/home/Pictures"
printf 'Preview document\n' > "$work/home/Downloads/readme.txt"
export MARWANOS_SHELL_FILES_HOME="$work/home"
export MARWANOS_SHELL_WINDOWED=1
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export LIBGL_ALWAYS_SOFTWARE=1
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
timeout 60 "$godot_bin" --headless --path "$work/shell" --import > "$work/import.log" 2>&1
timeout 60 xvfb-run -a -s '-screen 0 1600x900x24' "$godot_bin" --path "$work/shell" \
    --script "$repo/tests/keyboard_preview.gd" --audio-driver Dummy --rendering-method gl_compatibility
