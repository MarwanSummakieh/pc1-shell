# Files and Browser

Open the top bar with Up from the library, then choose Files or Browser.
These are shell surfaces: they keep the same controller mapping, on-screen
keyboard and home-screen focus restoration as Settings.

## Files

Browse Home, its common folders, Filesystem, Trash bin and mounted USB drives.
The footer shows the controller actions: Cross opens folders and files, Circle
goes back, Square selects items, and Triangle searches the current location.
Options offers file actions and view settings: details, icons, compact view,
sorting, hidden files and two panes. L1/R1 switch panes in split view. Folder
paths, previous/next folder and refresh are also available through Options.

Trash bin stays in the left Places column with an item count. Open it to review
deleted files and folders. Cross restores an item to its original folder;
Square selects several to restore through Options. Options → Empty trash bin
asks for confirmation before permanently deleting its contents. File pickers
omit Trash bin.

Actions include copy, cut, paste, rename, new folder, properties, trash and
restoring items from the home trash.
Name collisions create a numbered copy instead of replacing an existing file.
Copies skip symbolic links. A cross-filesystem move that skipped links retains
the original folder and reports that it was retained. Trash failures are shown
without falling back to permanent deletion. Copy and cross-filesystem move use
incremental, cancellable staging; a failed or cancelled copy keeps the source.
Initial folder listing remains synchronous, so unusually large directories can
briefly delay navigation.

PNG, JPEG, WebP, BMP and SVG open in the image viewer. Documents supported by
the embedded browser open inside Files and return to the same folder when
closed. EXE and MSI files open the managed Windows installation screen with the
chosen file focused. Run Windows setup opens its wizard through umu; after setup,
choose the installed program to add to the library. EXE files also offer Add as
portable app. Other unsupported formats report that no handler is available.

## Browser

The browser uses Chromium Embedded Framework with off-screen rendering in a
Godot control. The shell owns its window, tab rail, address bar, cursor, menus
and keyboard. The inset window follows the console's blue surfaces and focus
ring. Its native start page offers search, six shortcuts (or saved bookmarks),
and the latest three visits. X opens Website or search. An address without a scheme
uses HTTPS, and ordinary words become a DuckDuckGo search.

| Controller action | Result |
|---|---|
| D-pad / left stick | Move the page cursor |
| A | Click |
| Y | Type into the selected page field |
| X | Enter an address or search |
| L3 | Switch between the page pointer and browser controls |
| L1 / R1 or right stick | Scroll; the right stick supports continuous vertical and horizontal movement |
| B | Leave browser controls; on the page, go back or close when history is empty |
| Guide / Share | Return to the library while keeping tabs and downloads alive |
| Options | Address, tabs, bookmarks, history, downloads, Enter, Backspace, back/forward, reload, stop, return |

Selecting an editable page field opens a compact, movable keyboard. Move it
with the right stick; the page keeps its width and scrolls the focused field
clear of the floating panel. Its position is remembered. Characters, deletion and cursor movement reach that field immediately;
Circle closes the keyboard and keeps those edits. Triangle reopens it.

The keyboard reads field metadata locally: passwords remain masked in Chromium,
email/URL fields get address shortcuts, numeric fields get a number pad, and
search/next hints label the confirmation action. No field values or passwords
are copied into the shell. Ordinary Done only closes the panel; Search sends
Enter and Next sends Tab when explicitly confirmed. Other forms can be submitted
with their own button or Press Enter from Options.

While the keyboard is open: Cross types, Square deletes, Triangle adds a space,
L2 toggles shift, L1/R1 move the text cursor, and R2 or Options confirms. Circle
cancels drafts (addresses, filenames, Wi-Fi) or closes live page editing. The
keyboard uses the same compact layout for those other shell inputs; their draft
is saved only on confirmation. In Steam and other accessible native applications,
selecting an editable field opens the same keyboard in a separate floating window.
The window keeps application focus intact, and each edit is checked against the
focused field and window before typing. Password values stay in their original
fields. Done or Circle closes live editing and restores controller ownership.
Click the field again to reopen it; drag the header or use the right stick to move it.
Steam starts with its CEF accessibility bridge enabled. Applications that do not
expose editable controls through AT-SPI retain the Home → Type draft fallback.
The current URL stays visible above the page, including after redirects.
Network failures appear in the shell's status line with a reload instruction.

The Tabs button and Options → Tabs open up to eight live Chromium pages. New tabs
start on the native search surface. L3 focuses the address bar; the D-pad then
moves between native buttons. Circle returns to the page without navigating;
on a new tab, Circle closes the browser. Options → Close browser returns to the
library. The browser fills the screen with a single 60 px address toolbar;
there is no title bar, tab strip, side rail or bottom dock. Editing the
address starts with the current URL. Switching tabs keeps
their document state. User-initiated links to new windows become tabs; automatic
popup windows are blocked. Returning to the library keeps these tabs alive for
the current shell session. Bookmarks and the latest 100 internet visits are
saved locally; their menus offer removal and clearing. Local document paths are
excluded from history.

The compact browser uses 44 px controls. Open its puzzle button or Options →
Extensions → Chrome Web Store, choose an extension, select Add to Chrome, then
approve the standard Add extension permission prompt. Extensions come from the
[Chrome Web Store](https://chromewebstore.google.com/category/extensions).
Manage extensions opens Chromium's own extension manager for settings,
enabling, disabling and removal.

The store and manager use a fullscreen native Chromium window with one compact
shell toolbar and Return to browser. They share the embedded pages' persistent
profile at `~/.local/share/marwanos/mowser`; installed content scripts activate
without restarting MarwanOS. Chromium handles package verification, permissions,
the extension registry and updates. Store URLs entered in the address bar open
this same installer. Leaving the browser closes the extension window and
restores the retained page. Extension-created welcome tabs are closed so they
cannot take over the screen or remain unmanaged during shutdown.

CEF's embedded pages do not provide Chrome's toolbar or tab/window UI. Extension
features that depend on those surfaces may differ from desktop Chrome; content
scripts run in the embedded pages. The former ZIP package helper remains an
internal fixture path and is no longer the browser's installation flow.

Downloads save in the player's Downloads folder without automatically opening
or executing files. Duplicate filenames receive a numbered suffix. Options →
Downloads opens the shared [system Downloads surface](native-downloads.md),
with progress, cancellation and folder access in Files for viewing documents
or installing Windows apps. Browser downloads continue while the
browser surface is closed; closing their tab or quitting the shell cancels
unfinished transfers. Download status is retained for the current shell session.

File upload buttons open the controller Files picker. Cross chooses a readable
file; multiple uploads support selection and Choose selected in Options. Circle
or Share cancels. Chromium receives the selected files through its DOM API and
submits ordinary forms. This bypasses the pinned CEF 151 Linux off-screen
native chooser's null-window crash before its embedder callback. The bridge
does not copy text-field values or passwords to the shell. Folder upload inputs
and the browser File System Access API are not supported.

HTML select popups render inside the page; Circle dismisses them before
page navigation. JavaScript alerts, confirmations,
prompts and leave-page confirmations use controller menus or the same keyboard.
Camera, microphone, location and notification requests are denied. HTTP failures
and renderer failures provide a shell status message with a reload action.
DRM video is not supported. Chromium renderer sandboxing remains enabled for
the appliance's unprivileged player account.

## Building and checking

`os/Containerfile` builds Mowser against Godot 4.7.1 and the checksum-pinned CEF
distribution, exports its shared library beside the shell, and installs the
engine payload under `/usr/lib/marwanos/mowser`. The sandbox helper is installed
root-owned with mode 4755. Godot bindings are pinned to a commit and generated
from the pinned editor's API.

`scripts/check-tools-shell.sh` runs controller, filesystem and extension package regression checks
in a disposable fixture directory. `tests/browser_engine.gd` checks actual CEF
page rendering, input, clicking and navigation with `tests/browser-fixture.html`
on an X display. `scripts/build-tools-local.sh` can reuse a verified local
CEF/SDK cache for bench builds; the Containerfile remains the clean build path.
`PC1_BROWSER_TEST_SCRIPT=browser_downloads.gd` exercises saved download bytes;
`PC1_BROWSER_TEST_SCRIPT=browser_workflows.gd` checks real controller file
selection and Chromium uploads, dialogs, select widgets, tabs, bookmarks,
history and background downloads. Set `PC1_TOOLS_BUILD_DIR` to an isolated build
and `PC1_TEST_DISPLAY` to a free X display when running concurrent checks.
`PC1_BROWSER_TEST_SCRIPT=browser_internet.gd` verifies a real HTTPS page with
normal certificate validation; it requires internet connectivity.
`tests/browser_native_extensions.gd` checks the real native extension manager,
toolbar click, return focus, store routing and window closure. Run it on an
isolated X11 display with the pinned payload and a window manager; Openbox using
the appliance configuration matches the fullscreen stacking behavior. See
[fullscreen browser validation](browser-compact-20261009.md) for the real store
installation and restart checks.

## Bench validation — 2026-09-05

Activated on PC1 through `/var/marwanos/dev-shell/marwanos-shell`, using the
bundle in `/var/marwanos/dev-shell/pc1-tools-20260905`. The installed bootc image
remains unchanged. The developer-mode flag enables the override on subsequent
shell starts and reboots.

Verified on the NVIDIA/gamescope session: Files opens the player's home;
Browser renders DuckDuckGo with HTTP 200; its address keyboard opens; closing
the browser returns to the top bar and it can be reopened. The renderer runs
as UID 1000 with `NoNewPrivs: 1` and seccomp filter mode 2. No failed system
units were reported after activation. Physical controller acceptance remains
the user's bench check; automated controller events passed in the local suite.

The shipped binary's SHA-256 is recorded with its extension and engine archive
in the staged `/var/tmp/pc1-tools-20260905/pc1-tools.sha256` manifest. To return
to the baked shell, move the override wrapper aside and restart the active
shell process. `pc1-tools-20260905/enabled-devmode` records that this installation
created the developer-mode flag, so that flag can also be removed on rollback.


### Compact keyboard update — 2026-09-05

The active override now points to `/var/marwanos/dev-shell/pc1-keyboard-20260905`.
The previous tools bundle and `marwanos-shell.before-keyboard-20260905` wrapper
are retained for rollback. The staged `keyboard.sha256` covers the new shell,
extension and renderer helper. `scripts/install-keyboard-bench.sh` verifies
checksums and performs a player-account startup check before switching wrappers.

Validated CEF live editing before Done, deletion and cursor movement in existing
text, password isolation, email shortcuts, numeric inputmode, Next and Search,
click-release handling, and page/keyboard separation. The rendered test fixture
was visually checked at 1920×1080. Shell/controller and installer regressions
passed. On the bench, the updated shell detected DualSense, loaded the search
page with HTTP 200, automatically opened the field keyboard, and opened/closed
the address keyboard without script errors or failed units. Bench screen capture
was blocked by automatic approval review; no bench screenshot was collected.
