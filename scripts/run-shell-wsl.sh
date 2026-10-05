#!/usr/bin/env bash
#
# Run the MarwanOS shell on the WSLg desktop, for looking at the UI without a
# boot, a stick, or a VM.
#
#   wsl -d FedoraLinux-43 -u root -e bash scripts/run-shell-wsl.sh
#
# ERROR_SCREEN=1 draws the supervision loop's error frame instead of the home
# rail -- the same binary and the same variable marwanos-session uses when the
# crash guard gives up, so what you see is what the TV would show.
#
# STATUS_DIR=/some/dir mounts a directory of status-file fixtures and points
# MARWANOS_SHELL_STATUS_DIR at it, so the top bar's network word and the Steam
# card's install narration can be exercised without an appliance. Drop any of
# network.state (`online`/`offline`), network.info (`wifi HomeNet`),
# apps.tsv (six tab-separated fields: id, name, comment, icon, exec, state),
# install.<app-id>.state (`<state>TAB<display name>`) or
# installed.<app-id> (any content) into the directory -- the shell re-reads
# them every 2 s, so editing the files while the window is up shows the
# transitions live. Without
# STATUS_DIR nothing is mounted and the shell makes no claims, same as before.
#
# WHAT THIS IS AND IS NOT. It exports the real Godot project with the real
# toolchain and runs the real binary, so what you see is what the appliance
# ships. It is NOT the appliance: there is no session, no compositor, no
# supervision loop, and no gamepad unless one is passed through. It answers
# questions about layout, focus, theming and navigation. It cannot answer
# anything about fullscreen-at-native-mode, the display handover, or D4 -- those
# need hardware (ADR 0003, ADR 0005).
#
# WHY IT RUNS IN A CONTAINER RATHER THAN STRAIGHT IN WSL. The export dlopens
# libX11, libXcursor, libvulkan and friends, and the WSL distro is not required
# to have any of them; the final image is built to have exactly the set the shell
# needs, and the Containerfile asserts that at build time. Running inside it
# means "it started" is evidence about the image, not about this laptop.
#
# THE LOOP. Only the shell-export stage is rebuilt, so a UI edit does not touch
# the dnf, dracut or NVIDIA layers at all -- the Godot download and unpack stay
# cached and a re-run costs the export plus a container start.
#
# THREE THINGS ARE WORKED AROUND, all of them ostree artefacts of the runtime
# image rather than problems with the shell:
#
#   * /mnt is a symlink into /var, so the WSLg Wayland socket -- which lives
#     under /mnt/wslg and is only reachable through a symlink -- cannot be bind
#     mounted; crun cannot create the mountpoint. X11 it is. The shell runs on
#     XWayland on the appliance too (ADR 0006), so this is the same path.
#   * /root is a symlink into /var, which does not exist in the container, so
#     Godot cannot create its user data directory and dies before drawing.
#     HOME is forced onto a tmpfs.
#   * The kiosk policy is fullscreen, borderless and cursorless, which on a
#     desktop is a screen you cannot get out of. MARWANOS_SHELL_WINDOWED is what
#     kiosk.gd reads to skip it. Nothing on the appliance sets that variable.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_IMAGE="${RUNTIME_IMAGE:-ghcr.io/marwansummakieh/marwanos:latest}"
EXPORT_IMAGE="${EXPORT_IMAGE:-marwanos-shell-export:latest}"
BIN_OUT="${BIN_OUT:-/var/tmp/marwanos-shell}"
DISPLAY="${DISPLAY:-:0}"

die() { echo >&2; echo "run-shell-wsl: $*" >&2; exit 1; }

[[ -S /tmp/.X11-unix/X0 ]] \
    || die "no X server socket at /tmp/.X11-unix/X0 -- is this WSL with WSLg?"

# The runtime image is the shell's library environment, so a missing one is a
# missing dependency set rather than a missing convenience.
podman image exists "$RUNTIME_IMAGE" \
    || die "no runtime image $RUNTIME_IMAGE -- build it first: scripts/build-push.sh --no-push"

echo "==> Exporting the shell (only the shell-export stage rebuilds)"
podman build \
    --file "${REPO_ROOT}/os/Containerfile" \
    --target shell-export \
    --tag "$EXPORT_IMAGE" \
    "$REPO_ROOT"

echo "==> Extracting the binary"
cid="$(podman create "$EXPORT_IMAGE" /bin/true)"
trap 'podman rm -f "$cid" >/dev/null 2>&1 || true' EXIT
podman cp "${cid}:/out/usr/lib/marwanos/shell/marwanos-shell" "$BIN_OUT"
podman rm -f "$cid" >/dev/null
trap - EXIT
chmod 0755 "$BIN_OUT"
echo "    $BIN_OUT  $(( $(stat -c%s "$BIN_OUT") / 1024 / 1024 )) MiB"

echo "==> Running. Close the window to quit."
echo

# THE RENDERER, and this is the difference between a window you can use and one
# that looks broken. There is no /dev/dri in WSL, so Vulkan resolves to llvmpipe
# -- software rasterisation on the CPU. The shell ships Forward+, which is
# Godot's clustered renderer built for 3D scenes, and asking llvmpipe to run it
# over a 1920x1080 canvas costs single-digit frames per second: the window opens,
# draws, and then responds to input so slowly it reads as frozen.
#
# gl_compatibility is the OpenGL 3 path and llvmpipe handles it perfectly well
# for a 2D card rail. It changes NOTHING about what the appliance ships --
# project.godot still says Forward Plus and the export contains both -- it only
# picks which one this desk run uses.
#
# Override with RENDER_ARGS='' to see what Forward+ actually does here, which is
# worth doing once so the difference is measured rather than believed.
#
# --max-fps 60 is paired with it because llvmpipe cannot vsync -- Godot warns
# "changing V-Sync mode is not supported by the graphics driver" -- so nothing
# paces the frame loop and software rendering will take every core it can get.
# This is the one machine that is also the build host; an uncapped desk run
# competes with the thing you are trying to work on.
RENDER_ARGS=(--rendering-method gl_compatibility)
[[ -n "${RENDER_ARGS_OVERRIDE+x}" ]] && read -r -a RENDER_ARGS <<< "${RENDER_ARGS_OVERRIDE}"

# -t only when there is a terminal to attach to. Passing it without one makes
# podman fail with "the input device is not a TTY", which would make this script
# work when a human runs it and break when anything else does -- a CI job, a
# wrapper, or an agent checking that it still starts.
TTY_FLAGS=()
[[ -t 0 && -t 1 ]] && TTY_FLAGS=(-it)

# The fixture lever. :ro because the shell only ever reads these files --
# writes come from the person editing the fixtures on the host, which the
# bind mount passes straight through.
STATUS_ARGS=()
if [[ -n "${STATUS_DIR:-}" ]]; then
    [[ -d "$STATUS_DIR" ]] || die "STATUS_DIR=$STATUS_DIR is not a directory"
    STATUS_ARGS=(-e MARWANOS_SHELL_STATUS_DIR=/status -v "${STATUS_DIR}:/status:ro")
fi

# --network=none because the shell has no business reaching anything, and a
# desk run is the cheapest place to keep that true -- the status seam reads
# files precisely so this flag never has to soften.
exec podman run --rm "${TTY_FLAGS[@]}" \
    --network=none \
    -e DISPLAY="$DISPLAY" \
    -e HOME=/godothome \
    -e XDG_RUNTIME_DIR=/godothome \
    -e MARWANOS_SHELL_WINDOWED=1 \
    -e MARWANOS_SHELL_ERROR_SCREEN="${ERROR_SCREEN:-}" \
    "${STATUS_ARGS[@]}" \
    --tmpfs /godothome:rw,mode=1777 \
    -v /tmp/.X11-unix/X0:/tmp/.X11-unix/X0 \
    -v "${BIN_OUT}:/usr/lib/marwanos/shell/marwanos-shell:ro" \
    --entrypoint /usr/lib/marwanos/shell/marwanos-shell \
    "$RUNTIME_IMAGE" \
    "${RENDER_ARGS[@]}" --audio-driver Dummy --max-fps 60
