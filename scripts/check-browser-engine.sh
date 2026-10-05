#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="${PC1_TOOLS_BUILD_DIR:-/var/tmp/pc1-tools-build}"
editor="${GODOT_BIN:-/var/tmp/mowser-build/godot}"
runtime="${RUNTIME_IMAGE:-localhost/pc1-windows-test:latest}"
display="${PC1_TEST_DISPLAY:-:96}"
container="pc1-browser-check-${display#:}"
script="${PC1_BROWSER_TEST_SCRIPT:-browser_engine.gd}"
# Exercise the current shell sources with the locally built extension. Import
# registers the GDExtension even when a build cleared the .godot directory.
test -s "$work/project/bin/libmowser.so"
cp -a "$repo/shell/src/." "$work/project/src/"
cp "$repo/shell/project.godot" "$work/project/project.godot"
podman run --rm --network=none \
    -v "$work:/work" -v "$editor:/editor:ro" \
    -v "$work/payload:/usr/lib/marwanos/mowser:ro" \
    --entrypoint /usr/bin/timeout "$runtime" 120 /editor \
    --headless --path /work/project --import > "$work/browser-import.log" 2>&1 \
    || { cat "$work/browser-import.log"; exit 1; }
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Error loading extension|GDExtension dynamic library not found' "$work/browser-import.log"; then
    cat "$work/browser-import.log"
    exit 1
fi
server_pid=""
if [[ "$script" == browser_downloads.gd || "$script" == browser_workflows.gd ]]; then
    mkdir -p "$work"
    rm -f "$work/download-port"
    python3 "$repo/tests/download_server.py" "$work/download-port" &
    server_pid=$!
    for attempt in {1..40}; do [[ -s "$work/download-port" ]] && break; sleep 0.1; done
    export PC1_DOWNLOAD_PORT="$(cat "$work/download-port")"
fi
mkdir -p "$work/fixtures/Downloads" "$work/fixtures/Pictures" "$work/fixtures/Games" "$work/runtime-home/player"
cp "$repo/tests/browser-fixture.html" "$work/fixtures/Downloads/Browser test.html"
Xvfb "$display" -screen 0 1920x1080x24 -nolisten unix -listen tcp -ac \
    > "$work/xvfb.log" 2>&1 &
xvfb_pid=$!
trap 'podman rm -f "$container" >/dev/null 2>&1 || true; kill "$xvfb_pid" ${server_pid:+$server_pid} 2>/dev/null || true' EXIT
sleep 1
kill -0 "$xvfb_pid"
runner=(/editor)
debug_mounts=()
if [[ "${PC1_BROWSER_DEBUG:-0}" == 1 ]]; then
    debug_mounts=(-v "${PC1_CEF_DEBUG_LIBRARY:-/var/tmp/mowser-build/cef/Release/libcef.so}:/usr/lib/marwanos/mowser/libcef.so:ro")
    runner=(/usr/bin/gdb --batch -ex 'set pagination off' -ex 'set debuginfod enabled off' -ex run -ex 'info sharedlibrary' -ex 'x/10i $pc-16' -ex 'info registers' -ex 'bt 24' --args /editor)
fi
podman run --rm --name "$container" --network=host --user 0 \
    -e "DISPLAY=127.0.0.1$display" -e LIBGL_ALWAYS_SOFTWARE=1 \
    -e MARWANOS_SHELL_WINDOWED=1 -e MARWANOS_MOWSER_NO_SANDBOX=1 \
    -e MARWANOS_SHELL_FILES_HOME=/work/fixtures \
    -e PC1_DOWNLOAD_PORT -e PC1_DOWNLOAD_DIR=/work/test-downloads \
    -e PC1_BROWSER_FIXTURE=/tests/browser-fixture.html \
    -e PC1_BROWSER_SCREENSHOT=/work/browser-verified.png \
    -v "$work:/work" -v "$work/runtime-home:/var/home" -v "$repo/tests:/tests:ro" -v "$editor:/editor:ro" \
    -v "$work/payload:/usr/lib/marwanos/mowser:ro" \
    "${debug_mounts[@]}" \
    --entrypoint /usr/bin/timeout "$runtime" 90 "${runner[@]}" \
    --path /work/project --script "/tests/$script" \
    --rendering-method gl_compatibility --audio-driver Dummy > "$work/browser-check.log" 2>&1 \
    || { result=$?; tail -80 "$work/browser-check.log"; echo "Browser test process exited with status $result" >&2; exit "$result"; }
cat "$work/browser-check.log"
grep -qE 'Browser (engine|download|workflow) checks: 0 failure\(s\)'  "$work/browser-check.log"
! grep -qE 'SCRIPT ERROR|Parse Error|FAIL:' "$work/browser-check.log"
[[ "$script" == browser_engine.gd ]] || exit 0
cp "$work/browser-verified.png" "$repo/out/pc1-browser-verified.png"
cp "$work/files-verified.png" "$repo/out/pc1-files-verified.png"
