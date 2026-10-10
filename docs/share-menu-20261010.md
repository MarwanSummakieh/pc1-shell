# Share passes through to games — 10 October 2026

Installed on Bench (`192.168.50.206`) at 14:48 Copenhagen time. Share/Create/View
is no longer a system Home action and reaches the corresponding game's virtual
controller. Only Guide (PS/Xbox) opens the system menu. The broker's immediate
evdev handler, application gate, heartbeat policy and multiplayer snapshots use
the same rule. Held controls remain suppressed when returning from a menu.

The build uses the currently deployed source archive and preserves the controller
discovery latency repair, browser panel, user profiles and battery UI. Bloodborne
was closed with the user's authorization before restarting only the shell and
controller broker. This is a persistent local bench update, not a new OS image.

Validation: all 43 Linux controller policy tests pass; the real evdev/uinput
kernel fixture verifies Share press/release reaches each application slot without
disabling input. Controller shell checks and a focused running-application check
pass: Share leaves the overlay closed and application input active; Guide opens
the overlay; Back restores application input. The release export and isolated
startup pass. Live shell PID `671529` and broker PID `671615` restarted cleanly,
with a fresh shell heartbeat and unchanged native browser engine.

The older `windows_shell.gd` suite cannot pass its initial Install dock lookup
against this deployed UI; the focused `controller_home.gd` fixture verifies the
actual application/menu behavior directly. Physical in-game button acceptance
remains for the user.

| Artifact | SHA-256 |
| --- | --- |
| Shell | `0eb8c618f488fedd22a38f84c56b38dc1ab3e1d664d2f273bdecd80bf23e6e11` |
| Router | `ed566f1d45b4e48135c375e80b414985a7d17694db07c6aab847264df514a1b5` |
| Native engine | `de9d689c9b55bf26af5906f03fc2a8968b6b7e94b50d0a0938066fde5025ce58` |

Build scripts, source archive and logs: `/var/tmp/pc1-share-menu-20261010/`.
Local evidence: `out/share-menu-20261010/`. The active refinement manifest points
to `share-menu-source.tar.gz` and records `share-menu-deployment-20261010.json`.

Rollback files:

- `/var/marwanos/console-design-20261009/marwanos-shell.before-share-menu-20261010`
- `/var/marwanos/input-latency-20261010/router.py.before-share-menu-20261010`

Restore the shell atomically with the existing file's SELinux label. Restore the
router contents in place to preserve its active bind-mount inode, then restart
the supervised shell and broker. The installer automatically restores both
files if activation health checks fail.
