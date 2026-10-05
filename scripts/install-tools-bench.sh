#!/usr/bin/env bash
# Install a verified tools bundle through the existing reversible shell override.
set -euo pipefail
test "$(id -u)" = 0
staging=/var/tmp/pc1-tools-20260905
target=/var/marwanos/dev-shell/pc1-tools-20260905
override=/var/marwanos/dev-shell/marwanos-shell
test ! -e "$override" || { echo 'An override already exists; preserve it before installing.'; exit 1; }
cd "$staging"
sha256sum -c pc1-tools.sha256
install -d -m 0755 "$target/mowser"
tar --no-same-owner -xzf pc1-browser-engine.tar.gz -C "$target/mowser"
chown -R root:root "$target"
install -m 0755 pc1-tools-shell.x86_64 "$target/marwanos-shell.bin"
install -m 0755 libmowser.so "$target/libmowser.so"
chmod 0755 "$target/mowser/mowser-helper"
chmod 4755 "$target/mowser/chrome-sandbox"
export LD_LIBRARY_PATH="$target/mowser"
export MARWANOS_MOWSER_ROOT="$target/mowser"
ldd "$target/libmowser.so" > "$staging/dependencies.log"
if grep -q 'not found' "$staging/dependencies.log"; then
    cat "$staging/dependencies.log"
    exit 1
fi
runuser -u player -- env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" MARWANOS_MOWSER_ROOT="$MARWANOS_MOWSER_ROOT" \
    XDG_RUNTIME_DIR=/run/user/1000 "$target/marwanos-shell.bin" --headless --audio-driver Dummy --quit-after 4 \
    > "$staging/preflight.log" 2>&1
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|GDExtension dynamic library not found' "$staging/preflight.log"; then
    cat "$staging/preflight.log"
    exit 1
fi
grep -q 'home rail ready' "$staging/preflight.log"
cat > "$override.new" <<'WRAPPER'
#!/usr/bin/env bash
export MARWANOS_MOWSER_ROOT=/var/marwanos/dev-shell/pc1-tools-20260905/mowser
export LD_LIBRARY_PATH="$MARWANOS_MOWSER_ROOT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /var/marwanos/dev-shell/pc1-tools-20260905/marwanos-shell.bin "$@"
WRAPPER
chmod 0755 "$override.new"
mv "$override.new" "$override"
if [ ! -e /var/marwanos/devmode ]; then
    touch "$target/enabled-devmode"
    touch /var/marwanos/devmode
fi
echo 'Installed. Restarting only the shell; gamescope stays running.'
pkill -TERM -u player -x marwanos-shell
echo "Rollback: mv $override $override.disabled; then restart the shell."
