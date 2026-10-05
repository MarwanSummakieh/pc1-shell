#!/usr/bin/env bash
# Upgrade the approved bench override, retaining the previous working bundle.
set -euo pipefail
test "$(id -u)" = 0
staging=/var/tmp/pc1-keyboard-20260905
previous=/var/marwanos/dev-shell/pc1-tools-20260905
target=/var/marwanos/dev-shell/pc1-keyboard-20260905
override=/var/marwanos/dev-shell/marwanos-shell
test -f /var/marwanos/devmode
test ! -e "$target"
test ! -e "$override.before-keyboard-20260905"
grep -q "^exec $previous/marwanos-shell.bin" "$override"
cd "$staging"
sha256sum -c keyboard.sha256
old_pid=$(pgrep -u player -f "^$previous/marwanos-shell.bin$")
test "$(printf '%s\n' "$old_pid" | wc -l)" = 1
install -d -m 0755 "$target"
# Separate inodes: replacing the helper never modifies the running engine.
# Preserve the already approved root-owned sandbox permissions.
cp -a --reflink=auto "$previous/mowser" "$target/mowser"
install -m 0755 pc1-tools-shell.x86_64 "$target/marwanos-shell.bin"
install -m 0755 libmowser.so "$target/libmowser.so"
install -m 0755 mowser-helper "$target/mowser/mowser-helper"
export LD_LIBRARY_PATH="$target/mowser"
export MARWANOS_MOWSER_ROOT="$target/mowser"
ldd "$target/libmowser.so" > "$staging/dependencies.log"
! grep -q 'not found' "$staging/dependencies.log"
runuser -u player -- env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" MARWANOS_MOWSER_ROOT="$MARWANOS_MOWSER_ROOT" \
    XDG_RUNTIME_DIR=/run/user/1000 "$target/marwanos-shell.bin" --headless --audio-driver Dummy --quit-after 4 \
    > "$staging/preflight.log" 2>&1
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|GDExtension dynamic library not found' "$staging/preflight.log"
grep -q 'home rail ready' "$staging/preflight.log"
cp -a "$override" "$override.before-keyboard-20260905"
cat > "$override.new" <<'WRAPPER'
#!/usr/bin/env bash
export MARWANOS_MOWSER_ROOT=/var/marwanos/dev-shell/pc1-keyboard-20260905/mowser
export LD_LIBRARY_PATH="$MARWANOS_MOWSER_ROOT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /var/marwanos/dev-shell/pc1-keyboard-20260905/marwanos-shell.bin "$@"
WRAPPER
chmod 0755 "$override.new"
mv "$override.new" "$override"
kill -TERM "$old_pid"
echo 'Keyboard update activated; previous wrapper and bundle retained.'
