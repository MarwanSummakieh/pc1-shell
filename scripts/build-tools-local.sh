#!/usr/bin/env bash
# Fast local build using a previously verified CEF/SDK cache. The Containerfile
# remains the clean build; this avoids downloading the same engine for bench work.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="${PC1_TOOLS_BUILD_DIR:-/var/tmp/pc1-tools-build}"
cache="${PC1_MOWSER_CACHE:-/var/tmp/mowser-build}"
distribution="${PC1_CEF_DISTRIBUTION:-$cache/cef}"
compiler="${PC1_COMPILER_IMAGE:?Set PC1_COMPILER_IMAGE to an image with gcc-c++ and make}"
sdk="${PC1_SDK_IMAGE:-localhost/marwanos-godot-sdk:parse}"
mkdir -p "$work/payload/locales" "$work/project" "$work/out"

payload_file() {
    local source=$1
    local target=$2
    local mode=$3
    if test -s "$source"; then
        install -m "$mode" "$source" "$target"
    else
        # Shell-only rebuilds may reuse a verified payload after the extracted
        # CEF distribution was trimmed to headers and link libraries.
        test -s "$target"
    fi
}

cp -a "$repo/shell/." "$work/project/"
rm -rf -- "$work/project/.godot"
podman run --rm --network=none -v "$cache:/cache:ro" -v "$repo/mowser:/src:ro" \
    -v "$work:/work" --entrypoint /bin/bash "$compiler" -c \
    'make -C /src CEF_ROOT=/cache/cef GODOT_CPP=/cache/godot-cpp OUT=/work/extension'
install -m 0755 "$work/extension/libmowser.so" "$work/project/bin/libmowser.so"
install -m 0755 "$work/extension/mowser-helper" "$work/payload/mowser-helper"
install -m 0755 "$cache/cef/Release/libcef.so" "$work/payload/libcef.so"
podman run --rm --network=none -v "$work:/work" --entrypoint /usr/bin/strip "$compiler" \
    --strip-unneeded /work/payload/libcef.so
payload_file "$distribution/Release/chrome-sandbox" "$work/payload/chrome-sandbox" 0755
payload_file "$distribution/Release/v8_context_snapshot.bin" "$work/payload/v8_context_snapshot.bin" 0644
for name in icudtl.dat resources.pak chrome_100_percent.pak chrome_200_percent.pak; do
    payload_file "$distribution/Resources/$name" "$work/payload/$name" 0644
done
payload_file "$distribution/Resources/locales/en-US.pak" "$work/payload/locales/en-US.pak" 0644
podman run --rm --network=none -v "$work:/work" -v "$work/payload:/usr/lib/marwanos/mowser:ro" \
    --entrypoint /bin/bash "$sdk" -c \
    '/godot/bin/godot --headless --path /work/project --import && /godot/bin/godot --headless --path /work/project --export-release Linux /work/out/marwanos-shell.x86_64'
test -s "$work/out/libmowser.so"
install -m 0755 "$work/out/marwanos-shell.x86_64" "$repo/out/pc1-tools-shell.x86_64"
install -m 0755 "$work/out/libmowser.so" "$repo/out/libmowser.so"
tar -C "$work/payload" -czf "$repo/out/pc1-browser-engine.tar.gz" .
echo "Tools build ready in $repo/out"
