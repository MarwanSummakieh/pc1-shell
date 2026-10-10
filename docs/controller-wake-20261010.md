# Bluetooth controller wake — 10 October 2026

PC1 now has a controller-operated, display-only Rest mode. The owner physically
confirmed that Rest switches the display off and PS on the wireless controller
brings it back. The PC stays running throughout. At the owner's request, the
power menu now contains Turn off, Restart and Rest mode; Sleep and the description
beside Rest mode were removed. A separate line says how to wake with PS.

The current UGREEN BT6.0 adapter does not expose a supported deep-sleep wake path
to Linux. Rest avoids that hardware limitation by keeping Bluetooth running.

Initial read-only inspection of the physical bench at `192.168.50.206` found:

- Kernel `7.1.5-101.fc43.x86_64`, with `s2idle [deep]` selected.
- USB adapter `33fa:0012`, product `UGREEN BT6.0 Adapter`, at `3-2`.
- Its sole USB configuration reports `bmAttributes=0xc0` (self powered), without
  the Remote Wakeup flag. The adapter has no `power/wakeup` sysfs attribute.
- The connected DualSense reports paired, trusted and `WakeAllowed: yes` in
  BlueZ. Both controllers' bonds remain present.
- The adapter's PCI USB controller and upstream PCI bridge already report
  `power/wakeup=enabled`. Its USB root hub reports `disabled`; enabling the hub
  alone would not supply the missing adapter wake capability.
- No configuration was changed during this inspection and no suspend/resume test was initiated. The
  current boot reports zero successful and zero failed suspends.

Raw evidence is saved locally in `out/controller-wake-20261010.json`. The local
Windows development laptop is a separate machine; its Modern Standby results do
not describe PC1.

Linux distinguishes hardware wake capability from wake permission and runtime
autosuspend. Changing `power/control` to `on` does not keep an adapter operating
through system suspend. See the [USB power management documentation](https://docs.kernel.org/driver-api/usb/power-management.html)
and [device power management documentation](https://docs.kernel.org/driver-api/pm/devices.html).

True controller wake from system suspend still requires an adapter/driver that
exposes remote wake, wake enabled along its USB/PCI path, and a physical DualSense
button-wake test on PC1. Display-only rest consumes running-PC power.

## Rest implementation and bench acceptance

`shell/src/rest_screen.gd` uses the existing Xorg session's DPMS controls to turn
off the display. It keeps the controller broker and shell heartbeat running,
reduces the shell to 10 FPS, consumes menu input while resting, and restores the
previous display settings and FPS on wake. PS/Home from either controller or a
controller reconnect wakes the screen. Keyboard or mouse-button input provides
another way to recover. Saved display settings are also restored if the shell
exits normally or restarts after a crash.

The current-source rest checks and the deployed-source rest, navigation and
controller checks pass. The actual bench software check observed `Monitor is
Off`, a fresh shell heartbeat, unchanged shell/broker PIDs and zero suspend
cycles. An evdev PS pulse through the physical Bluetooth controller's input node
restored the previous DPMS settings. The owner then independently confirmed
both screen-off and wireless PS wake with the physical controller.

This is installed in the existing persistent bench layer at
`/var/marwanos/console-design-20261009/marwanos-shell`. The tested source derives
from the exact deployed PS/Home build, with only the power/rest changes applied;
unrelated unfinished work in the shared checkout was excluded. It is not a new
published OS image. The source changes are present for subsequent image builds.

Final binary SHA-256:
`e63bd1055bc102d417a3b8980d93be974713c754eb67193425a3f48a2c539e15`.

Local evidence: `out/rest-mode-20261010/bench-verification.json`,
`rest-deployment-20261010.json` and `power-menu-final.png`. Build source and Linux
test logs are under `/var/tmp/pc1-rest-mode-20261010/` on PC1. The pre-rest binary
remains at `marwanos-shell.before-rest-20261010` in the bench layer; an additional
`marwanos-shell.before-rest-menu-20261010` preserves the initial four-row rest
preview. Replacing the bench binary with a chosen backup and restarting the shell
reverts that local update without changing Bluetooth bonds or player slots.
