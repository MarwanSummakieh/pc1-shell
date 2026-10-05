#!/usr/bin/env bash
# Install the browser icon update beside the current right-stick bundle.
set -euo pipefail

test "$(id -u)" = 0
staging=/var/tmp/pc1-browser-icon-20260905
previous=/var/marwanos/dev-shell/pc1-browser-scroll-20260905
target=/var/marwanos/dev-shell/pc1-browser-icon-20260905
override=/var/marwanos/dev-shell/marwanos-shell
backup="$override.before-browser-icon-20260905"

test -f /var/marwanos/devmode
test -d "$previous/mowser"
test ! -e "$target"
test ! -e "$backup"
grep -q "^exec $previous/marwanos-shell.bin" "$override"

cd "$staging"
sha256sum -c SHA256SUMS
old_pid=$(pgrep -u player -f "^$previous/marwanos-shell.bin$")
test "$(printf '%s\n' "$old_pid" | wc -l)" = 1

cp -a --reflink=auto "$previous" "$target"
install -m 0755 marwanos-shell.bin "$target/marwanos-shell.bin"
test "$(stat -c '%U:%G %a' "$target/mowser/chrome-sandbox")" = "root:root 4755"

export MARWANOS_MOWSER_ROOT="$target/mowser"
export LD_LIBRARY_PATH="$MARWANOS_MOWSER_ROOT"
ldd "$target/libmowser.so" > "$staging/dependencies.log"
! grep -q 'not found' "$staging/dependencies.log"
runuser -u player -- env \
    MARWANOS_MOWSER_ROOT="$MARWANOS_MOWSER_ROOT" \
    LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
    XDG_RUNTIME_DIR=/run/user/1000 \
    "$target/marwanos-shell.bin" --headless --audio-driver Dummy --quit-after 4 \
    > "$staging/preflight.log" 2>&1
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|GDExtension dynamic library not found' "$staging/preflight.log"
grep -q 'home rail ready' "$staging/preflight.log"

cp -a "$override" "$backup"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    "export MARWANOS_MOWSER_ROOT=$target/mowser" \
    'export LD_LIBRARY_PATH="$MARWANOS_MOWSER_ROOT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
    "exec $target/marwanos-shell.bin \"\$@\"" \
    > "$override.new"
chmod 0755 "$override.new"
mv "$override.new" "$override"
kill -TERM "$old_pid"

# An open CEF browser can keep Godot alive while its renderer processes close.
# Give it a short graceful window, then make the requested shell restart
# definitive so the session supervisor can execute the new wrapper.
for attempt in $(seq 1 10); do
	if not kill -0 "$old_pid" 2>/dev/null; then
		break
	fi
	sleep 0.5
done
if kill -0 "$old_pid" 2>/dev/null; then
	kill -KILL "$old_pid"
fi

for attempt in $(seq 1 30); do
    new_pid=$(pgrep -u player -f "^$target/marwanos-shell.bin$" || true)
    if test -n "$new_pid"; then
        printf 'Browser icon update activated; shell restarted as PID %s.\n' "$new_pid"
        exit 0
    fi
    sleep 0.5
done

printf 'The wrapper was installed, but the session did not start the updated shell.\n' >&2
exit 1
