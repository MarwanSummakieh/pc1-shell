# Steam Stores pane — PC1 bench, 2026-10-09

The actual Steam Big Picture client runs inside the Stores pane on PC1, with
MarwanOS navigation visible. This is an enabled bench experiment, opt-in in the
source, rather than a default-enabled release acceptance claim.

![Actual Steam Store on PC1](steam-embedding-20261009/store.png)

## Controls and implementation

Open Stores and select Steam. Cross/A enters the client; its D-pad, sticks,
shoulders and Back stay native to Steam. Share/View opens Steam's native menu.
Guide/PS returns to the store selector; Down reaches MarwanOS navigation. Back
from the selector returns Home. Leaving and reopening Stores keeps the session.

`steam_embed.py` owns a rectangular native X11 host aligned to the Godot pane.
Steam is reparented as its child and continues rendering itself. There is no
capture loop, texture copy, nested compositor or Steam website substitution.
The host is independent of Godot's native window lifetime. X save-set protection
and saved original attributes preserve the client if the host exits.

The shell exchanges private atomic request/state files with the host, follows
physical pane geometry, and gives application controller input only to a visible,
focused Steam descendant. Ordinary shell navigation/repeat pauses during that
ownership. Guide, stale state and hidden panes neutralize application input.

Observed game windows require the current player's process ownership and a
non-client `STEAM_GAME` ID. Launcher adopts games started inside Steam and also
recognizes library launches when a Steam pane session exists. Game windows stay
fullscreen. Guide/minimize/resume use the existing application lifecycle; Close
sends the observed game `WM_DELETE_WINDOW`, preserving Steam. Only an exact
foreground game ID accrues play time.

## Verified remotely on the actual bench

| Check | Result |
| --- | --- |
| Composition | Live Steam Store, library, game details and native menus fit inside the pane; OS dock remains visible. Final physical rectangle: x=453, y=360, 2801×806 on a 3440×1440 output. |
| Controller path | Cross/A, Back, D-pad, Share/menu, Guide/Stores and dock navigation exercised through software evdev pulses injected into the physical DualSense device and the real broker. This is not a claim of human button presses or physical feel. |
| Steam library launch | Silksong app 1030300 launched from the embedded client, became fullscreen, accepted menu input, and exposed the MarwanOS Guide overlay. Close returned to Stores and the same game page. |
| MarwanOS library launch | Silksong launched from Home, minimized through Guide, resumed the same game window, then closed without ending Steam. |
| Session continuity | Steam client XID 50331698 survived game exits, repeated Home/Stores entry, shell replacement and abrupt native-host failure. |
| Recovery | Host failure displays an error with working OS navigation and restores selector focus. Controller Select starts a new host and reattaches the surviving Steam client. |
| Native fixture | Xvfb checks pass for native parenting, fixed dimensions, nested input focus, hidden-client rediscovery, orderly detachment, unrelated shell destruction and abrupt connection loss. |
| Shell regressions | Steam ownership/lifecycle checks, existing controller routing checks and play-history checks each report zero failures. They run in an isolated read-only host namespace with disposable writable state. |
| Build | Pinned Godot import/export succeeds without script or parse errors; `git diff --check` passes. |

The reusable native/shell check is `bash scripts/check-steam-embedding.sh`
(`GODOT_BIN` can select the pinned editor). It requires Python Xlib and Xvfb.

![Silksong fullscreen after launch from embedded Steam](steam-embedding-20261009/game.png)

![Same Steam session after closing the game](steam-embedding-20261009/return.png)

![Visible recovery state after host failure](steam-embedding-20261009/recovery.png)

## Bench deployment and rollback

- Base image: `0.0.202610071750`, commit `a38dce1`, built October 7 at 17:50:53 UTC.
- Xorg/Openbox/xcompmgr; RTX 3070, NVIDIA 610.43.03, 3440×1440 / 174.96 Hz.
- Godot `4.7.1.stable.official.a13da4feb`; Steam package `1.0.0.87-3.fc43`;
  Python Xlib `0.33-15.fc43`.
- Override: `/var/marwanos/steam-embedding-20261009/`, activated by enabled
  `marwanos-steam-embedding.service`. It layers over the existing Windows-library
  shell override. The unit checks the base image version and underlying shell
  checksum before mounting, and refuses to unmount an unrelated later override.
- Final executable SHA-256:
  `a5585a2c73d701e99426135ed5c099900020aa70f5362391a54da6397cb4b327`.
- Original underlying shell SHA-256:
  `ed7078f464d64ad2e115189f840a8aa2b745a27e20781f7e2f35e724285fc716`.

A concurrent console-design deployment subsequently layered above this service.
Its wrapper retains this Steam helper and its current executable is
`/var/marwanos/console-design-20261009/marwanos-shell`, SHA-256
`04114aa35815f2fe6a69b4bd096d888d14a4830b6a7745bc8752ef9f490c0d82`.
Native parenting, the 2801×806 pane and 174.96 Hz output were rechecked after
that deployment. Its unit orders itself after the Steam embedding unit.

With games closed, removing both October 9 shell overrides on PC1 is:

```sh
systemctl disable --now marwanos-console-design.service
systemctl disable --now marwanos-steam-embedding.service
pkill -TERM -u player -x marwanos-shell
```

Overrides must be removed in reverse order; the mount helpers refuse to remove
an unrelated top override. The existing supervisor restores the previous shell.
The Steam embedding unit is enabled for
future boots; a reboot was not performed during this task. Other existing bench
services and player account data were preserved.

## Remaining acceptance

Physical motion, frame pacing, controller latency/feel, rumble and disconnect
while embedded remain unverified. Fresh login/Steam Guard, search text entry,
checkout, downloads, separate native popup windows, Steam process replacement,
offline startup, other games (including Proton namespace PID handling) and
gamescope are not certified by these checks. Steam's menu shortcut can require
the first direction press to restore gamepad focus before moving selection.
Game Close currently relies on the game honoring `WM_DELETE_WINDOW`.

The default source requires `MARWANOS_STEAM_EMBED=1` on Xorg, or an explicit
`MARWANOS_STEAM_EMBED_HELPER` path as used by the bench wrapper. Unsupported
systems keep the existing fullscreen Steam library entry and a Stores
unavailable state. The error screen also offers an explicit fullscreen action.
See [ADR 0008](adr/0008-embedding-a-client-surface.md) for the acceptance contract.
