# PC1 shell

The MarwanOS Godot project is the current PC1 interface. It renders a library,
settings and an application overlay at a 1920×1080 design height, expanding to
the display aspect ratio. Every supported interaction must work with a controller.

## Structure

- `project.godot`: engine configuration and autoload services. Match the image's
  Godot version (currently 4.7.1) when opening the editor.
- `scenes/shell_root.tscn`: the root scene; UI composition lives in GDScript.
- `src/shell_root.gd`, `card.gd`, `tv_theme.gd`: library, navigation and TV layout.
- `src/shell_input.gd`, `player_one.gd`, `focus_repeat.gd`: input bindings,
  controller ownership within the shell, hotplug and held-direction repeat.
- `src/installed.gd`: library state. `launcher.gd` owns application launch/exit;
  `app_overlay.gd` supplies in-application shell controls.
- `src/*_screen.gd`: internal surfaces. The matching autoloads manage state,
  request files or screen lifetime.
- `assets/phosphor/`: bundled icon font, license and provenance.

Files and Browser are built-in surfaces reached from the top bar. Files uses
Godot's filesystem APIs; Browser uses the Mowser GDExtension and pinned CEF
payload. Both keep navigation and text entry inside the shell. See
[built-in tools](../docs/built-in-tools.md) for controls and limitations.
The Windows installation surface is described in [the installation contract](../docs/windows-installation.md).
Audio is available in Settings and the running-app Home menu, with device,
microphone and application volume controls. See [audio manager](../docs/audio-manager.md).

Console users select a profile at startup and share one installed library. Add
users or switch from the PS/Home dock or Settings → Users. Managed Windows game saves,
play history, achievement caches and browser bookmarks/history follow the
selected user. Steam keeps one shared account, login and save state across local
users; switching leaves Steam running. See [user profiles](../docs/user-profiles.md) for Steam Cloud,
custom save-path limits and verification.

## Runtime contracts

System helpers publish status under `/run/marwanos`; most shell readers have
`MARWANOS_SHELL_*` fixture overrides. Inspect the relevant reader for the exact
format. Requests use a temporary file followed by rename so consumers never
observe a partially written command. Persistent application data belongs in the
player's home, independently of bootc deployments.

Use `Launcher.launch(entry)` for external applications. Internal surfaces save
focus before opening and restore it after closing. Hidden surfaces must not
handle controller actions behind the active surface. A/B are logical accept/back
bindings; the UI draws PlayStation-style glyphs. Guide mapping and input
ownership across Steam and games still require real-device validation.

## Build and verification

The Containerfile imports and exports with the pinned editor/templates, embeds
the PCK into one executable and checks a headless startup reaches the library.
The icon font is an imported resource, so an import pass is required.

```bash
godot --headless --path shell --import
godot --headless --path shell --export-release Linux out/marwanos-shell.x86_64
./scripts/xvfb-shell-verify.sh
```

The Xvfb harness uses a local runtime image and supports status fixtures. It
does not prove physical controller ownership, GPU behavior, silent boot or
television readability. Verify those on the appliance. Never commit `.godot/`
or exported binaries.

The session supports a developer shell override under
`/var/marwanos/dev-shell/marwanos-shell` when `/var/marwanos/devmode` exists.
See [dev-setup.md](../docs/dev-setup.md) for deployment and recovery commands.

## Play history

The library sorts by most recently played, retaining scanner order for unplayed
entries and equal timestamps. Home summaries show total playtime; Down focuses
Play and Options while preserving the selected artwork and overview.
`PlayHistory.stats(installation_id)` also exposes the persisted
session records. IDs identify installations, so reinstalling under a different
ID begins a separate history even when the Steam metadata ID is the same.

History lives at `~/.local/share/marwanos/play-history/state.json` in the player's
home, with an independently atomic backup. The observer checks compositor focus
once per second. It starts only after a real launch is confirmed on screen and
the entry is a game: confirmed Steam Store game metadata, an explicit `kind:
game`, or a ROM entry. Failed/windowless launches, placeholders, desktop tools
and installer executables do not count. Games without metadata or an explicit
game classification remain uncounted until classification is available.
Ordinary launch windows must belong to the watched process or descendants;
Steam handoffs additionally require the exact game ID in the foreground window's
`STEAM_GAME` property, so the Steam client or another game cannot accrue time.

Minimizing, shell overlays or focus loss pause accounting without splitting the
session; resuming the same running process continues it. Foreground idle time,
cutscenes and menus count, since lack of button presses cannot establish that
someone stopped playing. Background idle time does not. Intervals over five
seconds in either monotonic or wall clock, including suspend or a stalled
observer, are discarded. Ordinary exit closes the session. Checkpoints occur
every fifteen counted seconds and at transitions; shell crash or reboot closes
unfinished sessions at the last checkpoint on recovery, never extrapolating
downtime. This can conservatively lose up to fifteen seconds on abrupt failure.
`MARWANOS_HISTORY_HOME` selects an isolated directory for regression tests.

## Interface design

Use [the shared design guidelines](../docs/design-system.md) for this shell and
products added to it. Home uses a user header, compact artwork rail, primary
actions and an attached system dock. Context menus reuse `edge_panel.gd` and
`list_menu.gd`; action controls reuse `console_button.gd`. The current viewport
determines card, dock and sidebar dimensions. `MARWANOS_DISPLAY_NAME` supplies
the active profile name until profile management is connected, falling back to
the session user. Stores includes the opt-in native Steam pane on Xorg. Enable
`MARWANOS_STEAM_EMBED=1` with the packaged Python/Xlib host, or provide a bench
`MARWANOS_STEAM_EMBED_HELPER` path. Guide returns to the selector, Share opens
Steam's menu, and games remain fullscreen. The pane's failure state offers an
explicit fullscreen action; unsupported systems retain the library's Steam
entry. See [bench evidence and limits](../docs/steam-embedding-20261009.md).
