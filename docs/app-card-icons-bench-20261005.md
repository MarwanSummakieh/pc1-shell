# App card icons on the bench — 2026-10-05

The PC1 bench at `192.168.50.206` now has the official app icon scanner and
Windows icon decoder. Its active shell already contained the rounded card
background, square card sizing and icon loading changes. The deployment retained
the current controller setup bundle, installed apps and compositor session.

## Installed override

`marwanos-app-icons.service` is enabled and bind-mounts
`/var/marwanos/app-icons-20261005/appscan` onto `/usr/lib/marwanos/appscan`, ordered
after the existing bench override and before the scanner, Windows worker and
greetd. It also restores the expected SELinux labels on the bound Windows helper
directory before the worker starts.

The existing Fedora `python3-pefile-2024.8.26-6.fc43` sources, ordinal lookup
module and MIT license were copied beside the active helper in
`/var/marwanos/controller-setup-20261005/windows`. Pillow was already installed.
This supplies the dependency through the executing helper's import directory;
the immutable OS image was not replaced.

The decoder extracted Free Download Manager's own embedded 256×256 icon to the
player's Windows icon cache. Refreshing the idle Windows worker published the
icon in its live library. A separate controller setup test was retained during
the refresh. The helper's staged `var_t` labels initially prevented service
startup; restoring the expected `lib_t` labels recovered the worker and is now
part of override startup.

## Verification

- The archive and individual source checksums matched before installation.
- The icon decoder loaded as `player`, and Pillow verified the actual FDM PNG.
- The Windows worker had a current heartbeat and a library entry with that PNG.
- The icon override, scanner and Windows worker were all active after recovery.
- The scanner SHA256 is
  `48f89180acf08bd5569f0edda1d1b03924125b577e930f9a1a7c06e4f99eec34`.
- The active shell SHA256 at verification was
  `c33d8bced5f75006d5c06af4c9a67fcbf6f32ffe8e2ec6372a59c3751b0f94b7`.

This deployment did not reboot the bench or publish a new OS image. The icon
code previously passed 19 regressions and a rendered controller navigation check.

## Rollback

The previous scanner and a snapshot of the existing bench override unit are
saved under `/var/marwanos/app-icons-20261005/rollback`.

To restore the image scanner, stop `marwanos-appscan.service`, disable and stop
`marwanos-app-icons.service`, then start `marwanos-appscan.service`. The decoder
files and generated icon cache can remain; they do not replace installed apps or
their prefixes. Retain the corrected helper labels so the Windows worker can
start. Disable this icon override together with the bench override before moving
to an OS image that includes these changes.
