# Browser extension controller access — 10 October 2026

Applied to Bench (`192.168.50.206`) at 13:52 Copenhagen time. This corrects
controller access in the [extension side panel](browser-extension-panel-20261010.md).

The native pointer bridge remained active while **Open extension** displayed
the shell's extension chooser. It consumed controller presses before the list
could handle them. The bridge now pauses for the chooser and keyboard, and waits
for held controls to release before resuming.

Fullscreen kiosk policy also kept the native cursor hidden after the browser
hid its own drawn cursor. Desktop-mode checks had missed this difference. The
panel now requests a visible native pointer, preserves it through focus changes,
places it inside the content when opened, and bounds controller movement to the
panel and toolbar. Closing the panel restores the console's hidden cursor.

Use **Open extension → NordVPN**, then the left stick to move and Cross to click.
**Type** opens the controller keyboard; L1/R1 scroll the native page.

## Validation

- Existing browser and extension shell suites: 74 assertions pass.
- Native panel lifecycle and setup/typing suites: 20 assertions pass with the
  Chromium sandbox enabled on a private Xvfb/Openbox display as `player`.
- New fullscreen controller regression: 11 assertions pass. The broker's routed
  controller events select the installed extension, move the native X pointer,
  and click a real extension button that opens its setup page. It also verifies
  visible cursor policy, focus restoration, pointer bounds and close cleanup.
- Before the fix, the fullscreen regression reproduced the hidden cursor while
  confirming that native pointer movement and Cross clicks themselves worked.
- The release export passes isolated startup. Bench's replacement shell PID
  `426620` loaded the expected executable and native engine, refreshed
  `shell.ready`, announced `home rail ready`, and stayed running without script
  or resource-loading errors during the deployment health check.

This verifies controller access and setup navigation. NordVPN account sign-in
and VPN connections have not been verified. The tests use an isolated copy of
the installed extension profile and do not alter the live account state.

## Deployment and rollback

The build preserves the latest user-profile and controller-battery UI changes.
Only the shell executable was replaced; the native engine is unchanged.

| Artifact | SHA-256 |
| --- | --- |
| Shell | `a2a2410f79bee39918843075471bde9a602e64d46f2a72e8b73634da6553dd9a` |
| Native engine | `de9d689c9b55bf26af5906f03fc2a8968b6b7e94b50d0a0938066fde5025ce58` |
| Source archive | `524fb21a87ad83768f8c3800cc0e17689081b5845afecb6c8a94058a8978b298` |

Stage and evidence: `/var/tmp/marwanos-browser-panel-input-20261010/`.
Source: `browser-panel-input-source.tar.gz` in that directory. The active
`refinement-deployment-20261010.json` now points to this combined source archive;
`browser-extension-input-deployment-20261010.json` records this deployment.

Rollback shell:
`/var/marwanos/console-design-20261009/marwanos-shell.before-extension-input-20261010`.
Restore it to the active `marwanos-shell` path and restart only the shell. The
installer verifies baseline hashes and restores that executable automatically
if startup fails. Local logs and scripts are under ignored
`out/browser-panel-input-20261010/`.
