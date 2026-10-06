#!/usr/bin/env bash
# Use the image's exact editor and checksum for controller regression checks.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pc1-shell-suite.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
if [[ -z "${GODOT_BIN:-}" ]]; then
    argument() { tr -d '\r' < "$repo/os/Containerfile" | sed -n "s/^ARG $1=\"\([^\"]*\)\"$/\1/p"; }
    version="$(argument GODOT_VERSION)"
    release="$(argument GODOT_RELEASE)"
    checksum="$(argument GODOT_EDITOR_SHA512)"
    [[ -n "$version" && -n "$release" && ${#checksum} -eq 128 ]]
    archive="Godot_v${version}-${release}_linux.x86_64.zip"
    curl --fail --location --retry 3 \
        "https://github.com/godotengine/godot-builds/releases/download/${version}-${release}/${archive}" \
        -o "$work/editor.zip"
    printf '%s  %s\n' "$checksum" "$work/editor.zip" | sha512sum -c -
    unzip -q "$work/editor.zip" -d "$work/editor"
    export GODOT_BIN="$work/editor/Godot_v${version}-${release}_linux.x86_64"
fi
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
timeout 180 bash "$repo/scripts/check-tools-shell.sh"
timeout 180 bash "$repo/scripts/check-windows-shell.sh"
timeout 90 bash "$repo/scripts/check-controller-shell.sh"
timeout 90 bash "$repo/scripts/check-audio-shell.sh"
timeout 90 bash "$repo/scripts/check-metadata-shell.sh"
timeout 90 bash "$repo/scripts/check-metadata-page-shell.sh"
timeout 90 bash "$repo/scripts/check-play-history-shell.sh"
timeout 90 bash "$repo/scripts/check-achievements-shell.sh"
timeout 90 bash "$repo/scripts/check-bluetooth-shell.sh"
timeout 90 bash "$repo/scripts/check-download-install-shell.sh"
timeout 90 bash "$repo/scripts/check-browser-download-directory.sh"
