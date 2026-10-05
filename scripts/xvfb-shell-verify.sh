#!/usr/bin/env bash
#
# Drive the MarwanOS shell invisibly under Xvfb and print its logs, so a UI
# flow can be asserted without touching the desktop the user is sitting at.
#
#   wsl -d FedoraLinux-43 -u root -e bash scripts/xvfb-shell-verify.sh Up Return Return
#
# Arguments are xdotool key names sent to the shell window in order (arrows for
# focus, Return for A / ui_accept, Escape for B / ui_cancel, Menu for the pad's
# OPTIONS button / ui_shell_options). A purely numeric
# argument is not a key but an extra sleep of that many seconds, for screens
# that need time to settle:
#
#   ... xvfb-shell-verify.sh Up Return 2 Return
#
# Everything the caller asserts on goes to STDOUT: exactly the container's
# logs, nothing else. Progress narration goes to stderr, so
#
#   out="$(wsl ... bash scripts/xvfb-shell-verify.sh Up Return)"
#   grep -q 'launch requested: steam.620' <<< "$out"
#
# is the whole harness. The shell's ShellLog lines are the assertion surface:
# `home rail ready with N cards`, `settings opened`, `launch requested: <id>`,
# `install requested for <id>`. Counting a line before and after a key press
# proves a screen survived an action.
#
# The Steam screen adds a second surface worth asserting on, and it is a
# stronger one: STEAM_DIR is mounted read-write, so a press can be checked by
# reading back the request the shell actually wrote --
#
#   grep -qx 'install\t620' "$STEAM_DIR/steam.request"
#
# which proves what was asked for rather than merely that something was logged.
#
# Environment:
#   STATUS_DIR   directory of status-file fixtures, mounted read-only and
#                pointed at by MARWANOS_SHELL_STATUS_DIR -- same seam and same
#                file formats as run-shell-wsl.sh. Without it the shell makes
#                no claims about network or apps. Everything the shell reads out
#                of /run/marwanos lives here: netcheck's answer, apps.tsv, and
#                gameart.tsv (the Steam artwork table -- one env lever for one
#                directory, which is why the artwork seam deliberately did not
#                get an override of its own).
#   STORE_DIR    the artwork and metadata cache, mounted read-only and pointed
#                at by MARWANOS_SHELL_STORE_DIR -- the /var/marwanos/store tree:
#                icons/<app-id>.png and meta/steam.<appid>.json. Without it a
#                store page draws its fallback glyph and the details panel has
#                no description from Steam to show.
#
#                THE STOREFRONT HALF OF THIS FIXTURE IS GONE, and so is the
#                front/ subtree it used to describe -- featured, search,
#                wishlist and the rest went out with the storefront in the
#                2026-08-12 rebuild (ADR 0010). What replaced it is STEAM_DIR
#                below.
#   STEAM_DIR    the in-shell Steam client's whole seam, mounted read-only and
#                pointed at by MARWANOS_SHELL_STEAM_DIR. ONE directory holding
#                everything by basename, which is not tidiness: the seam spans
#                /run/marwanos (steam.state, steam.downloads.json) AND
#                /var/marwanos/steam (account.json, library.json, signin.json,
#                qr.png, art/<appid>.jpg), so neither of the existing levers
#                could have covered it and two would have meant keeping two
#                fixtures in step by hand. Requests land here as steam.request.
#
#                WHAT EACH FILE MAKES THE SCREEN DO, since a fixture missing
#                one renders as a different state rather than as an error:
#                account.json decides signed-out vs the shelf, library.json is
#                the shelf itself ({appid,name} items), signin.json + qr.png
#                are the QR panel, and steam.downloads.json is what puts a
#                percentage on a tile.
#
#                NOTE THE SHELF ALSO NEEDS STATUS_DIR: the screen gates every
#                state behind the flatpak client being installed, so an
#                apps.tsv without com.valvesoftware.Steam marked installed
#                correctly draws the first-boot page no matter what is here.
#   FILES_DIR    directory of file-manager fixtures, mounted at /files and
#                pointed at by MARWANOS_SHELL_FILES_HOME, so the files
#                screen's Home place browses it. Read-write, unlike
#                STATUS_DIR: status files are root-written truth the shell
#                must not touch, and this is a sandbox home whose whole point
#                is that copy, rename and delete can be exercised against it.
#                Without it the Home place is the container's HOME -- an
#                empty tmpfs, which only ever proves the empty state.
#   SERVICES_DIR the background-service seam: <id>.state files ("running",
#                "stopped", "crashed") and optionally <id>.wanted, as the
#                session's supervisor would have written them. What it drives is
#                the processes pill's badge dot in the bar's left corner and the
#                rows of the menu behind it. It used to drive a third thing --
#                the quick settings panel's own copy of the same words -- which
#                was deleted in the menu rewrite of 2026-08-12.
#
#                COPIED IN, NOT MOUNTED, and it is the only fixture that is --
#                every other one is a read-only bind because the shell only
#                reads it. This seam is READ AND WRITTEN: pressing A on a row
#                puts a `<id>.wanted` file next to the state, which is the whole
#                mechanism under test, so a read-only mount would fail the press
#                rather than prove it. The destination is XDG_RUNTIME_DIR's
#                marwanos/services, a tmpfs podman makes at start, so the files
#                go in with podman cp once the container is up.
#
#                To assert a press landed, read the wish back out afterwards:
#                  podman exec marwanos-verify-99 cat /godothome/marwanos/services/steam.wanted
#   MEDIA_DIR    fake drives, bind-mounted straight over /run/media (which is
#                a tmpfs in the container, so the real path is writable and
#                needs no override in the shell). Same two-level shape as the
#                real thing -- <user>/<drive>, e.g. player/USB_DRIVE --
#                because that is what the Places view enumerates. Nothing can
#                be plugged into a container, so without this the drive rows
#                have never rendered at all.
#                Read-write, so a directory created or deleted DURING a run
#                exercises the live mount poll: mkdir one between two numeric
#                sleep arguments and assert on "files: drive appeared at".
#   DEVMODE      set to 1 to run the shell as if /var/marwanos/devmode were
#                present, which is what puts the Terminal row on the settings
#                screen (MARWANOS_SHELL_DEVMODE -- see catalogue.gd). Without
#                it the settings screen is the shipped machine's, one row
#                shorter, which is the state most assertions should be made
#                against. Pressing A on the row inside this harness launches
#                the wrapper from the RUNTIME image and it refuses (no flag in
#                a container), so what this exercises is the row, the launch
#                seam and the return -- not a working terminal.
#   KEY_DELAY    seconds slept after every key (default 1).
#   SETTLE       seconds slept once the window exists, before driving (default 3).
#   SHOTS_DIR    if set, an ImageMagick `import` of the Xvfb root is written
#                there as final.png after the last key, for pixel assertions.
#   DISP         Xvfb display (default :99); RUNTIME_IMAGE, EXPORT_IMAGE and
#                BIN_OUT override the same knobs as run-shell-wsl.sh.
#
# Build and extraction mirror run-shell-wsl.sh: only the shell-export stage
# rebuilds, the binary is copied out, and it runs against the runtime image so
# "it started" is evidence about what the appliance ships.
#
# THREE TRAPS this script exists to remember, each of which has cost a session
# a round of debugging:
#
#   * WSLg owns /tmp/.X11-unix and Xvfb cannot create a unix socket there.
#     Xvfb listens on TCP only (-nolisten unix -listen tcp -ac) and the
#     container gets --network=host with DISPLAY=127.0.0.1:<display>.
#   * podman's journald log driver chokes on the shell's `<N>` priority
#     prefixes ("Failed parse journal entry"), so `podman logs` shows nothing
#     and the shell looks hung. --log-driver=k8s-file keeps the logs readable.
#   * Driving the visible WSLg desktop with SendKeys/AppActivate is unreliable
#     (Windows blocks focus-stealing; keys land in the foreground app) and
#     hostile to whoever is using the machine. This private display is the
#     only sanctioned way to press buttons in the shell.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_IMAGE="${RUNTIME_IMAGE:-ghcr.io/marwansummakieh/marwanos:latest}"
EXPORT_IMAGE="${EXPORT_IMAGE:-marwanos-shell-export:verify}"
BIN_OUT="${BIN_OUT:-/var/tmp/marwanos-shell-verify}"
DISP="${DISP:-:99}"
KEY_DELAY="${KEY_DELAY:-1}"
SETTLE="${SETTLE:-3}"
CTR="marwanos-verify-${DISP#:}"
BUILD_LOG="/tmp/marwanos-verify-build.log"

# stdout is reserved for the container logs; everything human goes here.
say() { echo "==> $*" >&2; }
die() { echo "xvfb-shell-verify: $*" >&2; exit 1; }

command -v podman  >/dev/null || die "no podman"
command -v Xvfb    >/dev/null || die "no Xvfb"
command -v xdotool >/dev/null || die "no xdotool"
podman image exists "$RUNTIME_IMAGE" \
    || die "no runtime image $RUNTIME_IMAGE -- build it first: scripts/build-push.sh --no-push"

if [[ -n "${STATUS_DIR:-}" && ! -d "$STATUS_DIR" ]]; then
    die "STATUS_DIR=$STATUS_DIR is not a directory"
fi
if [[ -n "${FILES_DIR:-}" && ! -d "$FILES_DIR" ]]; then
    die "FILES_DIR=$FILES_DIR is not a directory"
fi
if [[ -n "${STORE_DIR:-}" && ! -d "$STORE_DIR" ]]; then
    die "STORE_DIR=$STORE_DIR is not a directory"
fi
if [[ -n "${STEAM_DIR:-}" && ! -d "$STEAM_DIR" ]]; then
    die "STEAM_DIR=$STEAM_DIR is not a directory"
fi

say "Exporting the shell (only the shell-export stage rebuilds)"
podman build \
    --file "${REPO_ROOT}/os/Containerfile" \
    --target shell-export \
    --tag "$EXPORT_IMAGE" \
    "$REPO_ROOT" >"$BUILD_LOG" 2>&1 \
    || { tail -30 "$BUILD_LOG" >&2; die "export build failed (full log: $BUILD_LOG)"; }

say "Extracting the binary"
cid="$(podman create "$EXPORT_IMAGE" /bin/true)"
podman cp "${cid}:/out/usr/lib/marwanos/shell/marwanos-shell" "$BIN_OUT"
podman rm -f "$cid" >/dev/null
chmod 0755 "$BIN_OUT"

say "Xvfb on $DISP (TCP only -- WSLg owns /tmp/.X11-unix)"
pkill -f "Xvfb $DISP" 2>/dev/null || true
sleep 1
Xvfb "$DISP" -screen 0 1920x1080x24 -nolisten unix -listen tcp -ac \
    >/tmp/marwanos-verify-xvfb.log 2>&1 &
XVFB_PID=$!
trap 'podman rm -f "$CTR" >/dev/null 2>&1 || true; kill "$XVFB_PID" 2>/dev/null || true' EXIT
sleep 2

STATUS_ARGS=()
if [[ -n "${STATUS_DIR:-}" ]]; then
    STATUS_ARGS=(-e MARWANOS_SHELL_STATUS_DIR=/status -v "${STATUS_DIR}:/status:ro")
fi

STORE_ARGS=()
if [[ -n "${STORE_DIR:-}" ]]; then
    # Read-only for STATUS_DIR's reason: this tree is root-written truth on the
    # appliance (marwanos-steam owns it) and the shell only ever reads it, so
    # a fixture the shell could write to would be a fixture that proves less.
    STORE_ARGS=(-e MARWANOS_SHELL_STORE_DIR=/store -v "${STORE_DIR}:/store:ro")
fi

STEAM_ARGS=()
if [[ -n "${STEAM_DIR:-}" ]]; then
    # READ-WRITE, and it is the one fixture mount that has to be. Every other
    # seam here is answers the shell only reads; this one also carries the
    # REQUESTS the shell writes, so mounting it :ro would make every press on
    # the Steam screen fail silently -- which is indistinguishable from the
    # feature being broken, and is exactly what the harness exists to tell
    # apart. Reading steam.request back out is also how a test asserts that a
    # press asked for the right thing.
    STEAM_ARGS=(-e MARWANOS_SHELL_STEAM_DIR=/steam -v "${STEAM_DIR}:/steam:rw")
fi

FILES_ARGS=()
if [[ -n "${FILES_DIR:-}" ]]; then
    FILES_ARGS=(-e MARWANOS_SHELL_FILES_HOME=/files -v "${FILES_DIR}:/files:rw")
fi

# An environment variable rather than a touched file, because the real flag
# lives at a root-owned path the shell cannot write -- so the override has to
# be something only whoever STARTS the shell can set. See catalogue.gd.
DEVMODE_ARGS=()
if [[ -n "${DEVMODE:-}" && "${DEVMODE}" != "0" ]]; then
    DEVMODE_ARGS=(-e MARWANOS_SHELL_DEVMODE=1)
fi

MEDIA_ARGS=()
if [[ -n "${MEDIA_DIR:-}" ]]; then
    # Bind-mounted at the REAL path rather than at a fixture path behind an
    # environment override, because /run is a tmpfs in this container and the
    # real path is therefore writable -- so the drive rows are exercised
    # through exactly the constant the appliance uses. NOT /media: in an ostree
    # image that is a symlink to run/media, and crun refuses to resolve a bind
    # mount destination through one.
    MEDIA_ARGS=(-v "${MEDIA_DIR}:/run/media:rw")
fi

say "Starting the shell container"
podman rm -f "$CTR" >/dev/null 2>&1 || true
podman run -d --name "$CTR" \
    --network=host --log-driver=k8s-file \
    -e DISPLAY="127.0.0.1${DISP}" \
    -e HOME=/godothome \
    -e XDG_RUNTIME_DIR=/godothome \
    -e MARWANOS_SHELL_WINDOWED=1 \
    "${STATUS_ARGS[@]}" \
    "${STORE_ARGS[@]}" \
    "${STEAM_ARGS[@]}" \
    "${FILES_ARGS[@]}" \
    "${MEDIA_ARGS[@]}" \
    "${DEVMODE_ARGS[@]}" \
    --tmpfs /godothome:rw,mode=1777 \
    -v "${BIN_OUT}:/usr/lib/marwanos/shell/marwanos-shell:ro" \
    --entrypoint /usr/lib/marwanos/shell/marwanos-shell \
    "$RUNTIME_IMAGE" \
    --rendering-method gl_compatibility --audio-driver Dummy --max-fps 30 \
    >/dev/null || die "container did not start"

# Seeded before the window is even waited for, so the shell's first poll of the
# seam already sees it and no row has to be watched changing its mind.
if [[ -n "${SERVICES_DIR:-}" ]]; then
    say "Seeding the services seam from $SERVICES_DIR"
    podman exec "$CTR" mkdir -p /godothome/marwanos/services \
        || die "could not create the services seam inside the container"
    seeded=0
    for f in "$SERVICES_DIR"/*; do
        [[ -f "$f" ]] || continue
        podman cp "$f" "${CTR}:/godothome/marwanos/services/$(basename "$f")" \
            || die "could not copy $(basename "$f") into the services seam"
        seeded=$(( seeded + 1 ))
    done
    (( seeded > 0 )) || die "SERVICES_DIR=$SERVICES_DIR held no files"
    say "Seeded $seeded service file(s)"
fi

say "Waiting for the shell window"
export DISPLAY="127.0.0.1${DISP}"
win=""
for _ in $(seq 1 30); do
    win="$(xdotool search --name 'MarwanOS Shell' 2>/dev/null | head -1)" || true
    [[ -n "$win" ]] && break
    sleep 1
done
if [[ -z "$win" ]]; then
    podman logs "$CTR" 2>&1 | tail -20 >&2
    die "shell window never appeared on $DISP"
fi
sleep "$SETTLE"

if (( $# > 0 )); then
    say "Driving: $*"
    xdotool windowactivate "$win" 2>/dev/null || true
    for key in "$@"; do
        if [[ "$key" =~ ^[0-9]+$ ]]; then
            sleep "$key"
        else
            xdotool key --window "$win" "$key"
            sleep "$KEY_DELAY"
        fi
    done
fi

if [[ -n "${SHOTS_DIR:-}" ]]; then
    command -v import >/dev/null || die "SHOTS_DIR set but ImageMagick import is missing"
    mkdir -p "$SHOTS_DIR"
    import -display "127.0.0.1${DISP}" -window root "${SHOTS_DIR}/final.png"
    say "Screenshot: ${SHOTS_DIR}/final.png"
fi

say "Container logs follow on stdout"
podman logs "$CTR" 2>&1
