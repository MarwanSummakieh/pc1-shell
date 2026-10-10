# Home volume slider — 10 October 2026

Deployed to Bench (`192.168.50.206`) at 16:44 Copenhagen time as a persistent
local shell update. Audio in the Home dock and running-app Home menu opens a
compact output volume slider above its control. Settings retains the full mixer.

Built from the verified current deployment source, applying only the slider
patch and its tests. The native browser engine and other installed fixes remain
intact. Linux audio, responsive design and controller Home checks pass, as do
release export and isolated startup as the player user.

Live verification clicked the Audio dock icon and confirmed the popup above it
with the library visible. Right changed the real HDMI output from 80% to 85%;
Left restored 80%. The output remained unmuted. The slider was left open for
review. Physical controller acceptance remains for the user.

Installed shell SHA-256:
`a70b6b9ab90674378155891238e1db854fc835a5e0542b081d6dde22eb791fba`.
Verified shell PID: `1166277`.

Build source, tests, source archive and deployment records:
`/var/tmp/pc1-volume-slider-20261010/`. Local records and the live screenshot:
`out/volume-slider-bench-20261010/`. The active refinement manifest references
`volume-slider-source.tar.gz` and `volume-slider-deployment-20261010.json`.

Rollback binary:
`/var/marwanos/console-design-20261009/marwanos-shell.before-volume-slider-20261010`.
Restore it atomically with the active binary's SELinux label and restart the
supervised shell. The installer retains the previous manifest and automatically
restores the previous binary if startup health checks fail.
