# MarwanOS design guidelines

Use this system for MarwanOS and products added to it. The visual foundation is a PS5-inspired console interface with dark charcoal surfaces and Scandinavian simplicity. Prioritise the user's task, clear controller focus, readable content and quick response.

## Shared visual language

Use a system sans-serif, sentence case and concise labels. A heading normally stands alone. Instructions belong beside the control they explain. Show useful content rather than filling space with subtitles, badges or decorative cards.

Semantic colour tokens:

- `background`: `#11161C` — main canvas.
- `surface`: `#1B232C` — attached navigation, windows and grouped content.
- `surfaceFocus`: `#293541` — hover and focus fill.
- `surfacePressed`: `#354352` — acknowledgement while pressed.
- `textPrimary`: `#E4EDF3`.
- `textSecondary`: `#B7C7D2`.
- `primary`: `#BCD9EC` — the main action.
- `textOnPrimary`: `#20313E`.
- `focusRing`: `#D5EAF5`.
- `destructive`: `#F0AEAE` — an explicit destructive action label.

Use names instead of hard-coded colours in product components. Product artwork and brand marks retain their identity; surrounding navigation and controls use these shared tokens. Colour must accompany a label, outline, marker or icon when it conveys state.

On the game library, the highlighted game's artwork fills the viewport at its original aspect ratio with cover cropping. Prefer landscape library hero art, then header art, then the cover; Steam's dim store-page backdrop is not the library illustration. Keep the artwork in full colour; use local dark scrims behind the summary and user header for readability. Selection updates the background after a brief settling delay, with decoding off the UI thread and bounded caching. Entries without artwork use the shared charcoal canvas. Navigation and buttons retain the shared dark surfaces.

Down from a game enters its Play and Options actions on the same Home surface. Preserve the selected artwork, rail and summary; Back returns to the selected game. Steam belongs in Stores. Download tools, transfers and unfinished setup belong in Downloads; registered games appear on Home. Finished Downloads exposes Install, Choose program to play, or Play according to the latest setup result. Settings → Update metadata refreshes all library game artwork/details with progress and retry feedback.

Home game cards use 1.5× their original width and height, retaining the 2:3 portrait shape. Leave 3u between the selected card and the overview. Preserve the Play/Options baseline where it fits; move the actions below the measured wrapped overview with at least 2u of clear space when needed.

Home's footer keeps Open, Options and the PlayStation-mark System menu hint. Omit the Game actions tutorial hint. During game startup, use cached full-screen background artwork and the game logo; keep loading and recovery feedback at the safe lower edge. Fall back to the icon and title when artwork is missing, and hand over as soon as the existing window watchdog confirms the game is drawing.

## Responsive layout

Layout fills the available viewport. Do not centre the application inside a fixed-width frame. Calculate dimensions from the current content region, and recalculate after resizing or display changes.

For console layouts, define **u = min(viewport height, viewport width × 9/16) / 100** in the framework's logical layout coordinates. Native render scaling may map those coordinates to physical pixels; do not stretch a finished screenshot to substitute for layout. Web products should use viewport/container units and the same proportions, with a readable minimum type and target size.

- Keep text and focusable content inside approximately 5% safe margins. Backgrounds, sidebars and bottom bars extend to the screen edge.
- Vertical rounded rectangular library tiles are approximately 10.3u wide × 15.5u high, with a 1.5u gap. Selection grows modestly to 12.7u × 19u. Ultrawide displays reveal more tiles while preserving the 2:3 portrait shape. Cover artwork fills and clips to the rounded silhouette.
- Action sidebars fill the height and use up to 30% of available width, capped at 52u. On narrow displays, use the available width. Their contents scroll when necessary.
- Bottom navigation occupies approximately 12u, with an 80-pixel circle around each unchanged 36-pixel icon. Commands scroll with focus if they cannot fit; the badged activity indicator stays at the far right. Keep every destination reachable.
- Primary controls are approximately 6u tall. Width follows the label plus padding, rather than a fixed fraction of the entire screen.
- Use a small spacing scale: 0.4u, 0.8u, 1.2u, 1.6u, 2.4u, 3.2u and 4.8u.
- Ordinary buttons and menus use corners of approximately 0.75u. Home Play uses semicircular ends; its Options control is three dots in an outlined circle. System-menu icons use circular selection outlines, and Browser uses a globe.
- Body text is approximately 2.6u, secondary text 2.2u and page titles 4.1–5.2u. Enforce readable minimums and support larger text. Wrap or reflow before shrinking essential text.

Inspect 16:9 at 720p, 1080p and 4K, 21:9 ultrawide, and narrow windows. Verify long names, translated labels, enlarged text and overflow. Screen size and viewing distance are separate concerns; sofa readability still needs physical validation.

Reference dimensions at a 1920 × 1080 logical viewport (u = 10.8):

| Element | Proportion | Approximate reference size |
| --- | --- | --- |
| Idle / selected artwork | 10.3u × 15.5u / 12.7u × 19u | 112 × 167 / 137 × 205 |
| Card gap | 1.5u | 16 |
| Main action height | 6u, with readable target floor | 65 |
| Menu row height / gap | 6u / 0.8u | 65 / 9 |
| Sidebar width | min(30% width, 52u) | 562 |
| Bottom navigation height | 12u, with content floor | 130 |
| Body / secondary / title type | 2.6u / 2.2u / 4.1–5.2u | 28 / 24 / 44–56 |
| Corner / focus outline | 0.75u / 0.28u | 8 / 3 |

These numbers are reference measurements, not a fixed-width frame. When width is less than about 1.15 × height, action sidebars use the full width and store windows stack below their selector. Preserve content and target minimums before reducing spacing; allow scrolling when they cannot fit.

## Identity and navigation

The active user's display name belongs at the top. Read it from the active profile, with a session-user fallback until the profile flow exists. An avatar is optional. Store accounts remain distinct from the operating-system identity.

Use one main navigation structure with predictable destinations. MarwanOS includes Home, Stores, Browser, Files, Downloads, Audio, Settings and Power; Install remains available while it is a required independent flow. New products may use fewer destinations. Do not copy every destination into every product.

System commands belong in an attached sidebar or bottom bar. Contextual actions open an edge-attached sidebar. Avoid floating panels containing oversized buttons. Show the active page with a subtle fill or edge marker, and controller focus with an outline; these represent different states.

Audio in the Home dock and running-app Home menu opens a compact volume slider
directly above its control, keeping the current surface visible. Drag or use
left / right to adjust output volume; Cross toggles mute. Circle, PS/Home or an
outside click closes it and restores Audio focus. Device and application audio
controls remain in Settings → Audio.

On Home and Stores, the bottom bar starts hidden while browsing. PS/Home toggles it and moves focus to the active destination. Pressing PS/Home again restores focus to the originating game, control or embedded store pane. Hidden navigation must be excluded from directional focus paths. Reserve bottom-bar space only while it is visible, so store content uses the available height. Keep a small PS/Home hint discoverable. An empty library or disconnected controller may initially reveal setup navigation; PS/Home remains available to recover it.

Text entry uses a compact floating keyboard near the bottom center. Keep the
application visible at its existing size, use four character rows and a symbols
toggle, and let the user move the panel by its header or the right stick. Open it
when an editable field is selected and restore controller ownership when it closes.
Live fields retain their own text and password masking; do not duplicate their
values in the shell. Native applications use a separate window that leaves their
keyboard focus intact. Unsupported custom controls retain the manual Type action.

Remember the selected object and scroll position when a surface opens. Closing it restores focus to its origin, or a valid nearby control if the origin was removed. Hidden surfaces must not process input behind the active surface.

## Buttons and states

**Primary:** pale blue fill, dark text. Use for Play, Save or the current task. Give one action the strongest emphasis in a local group.

**Secondary:** quiet surface or outline with light text. Use for Details, Cancel and supporting actions. Keep a comparable hit area.

**Navigation:** compact icon and label on a shared surface. Use recognisable icons from the existing Phosphor family. Icon-only controls need accessible names.

Every interactive component needs idle, hover, focus, pressed, disabled and loading states where applicable. Loading preserves size and prevents duplicate requests. Unavailable actions explain why when it affects the user's decision. Errors state what failed and offer a specific recovery action near the cause.

Destructive actions use explicit verbs and appear after ordinary actions. Confirm deletion of managed data with the object name and consequence; default focus goes to Cancel. Do not present unsupported deletion actions.

## Cards, artwork and windows

Use cards for independently actionable objects, not as decorative wrappers around every section. Lists and settings normally share one surface with spacing or subtle separators.

Game cover artwork fills each 2:3 vertical rounded rectangular tile edge to edge, clipped to the card's rounded corners. Use portrait cover art first, with header art as a fallback. Draw focus above artwork so the image cannot hide it. Keep download and installation progress in Downloads with readable text and progress indicators.

Keep the selected object's title and useful facts in the hero area. Protect text from bright or busy artwork with a static slate scrim. Do not use live blur or decorative glow.

Application windows fit the available content region and keep shell navigation accessible. For Stores, the required interaction is **Stores → Steam → a bounded Steam window**. Additional stores use the same pattern when supported. Do not add inactive future-store placeholders or substitute fullscreen Steam for windowed integration. Windowed Steam remains a separate development dependency; report its actual availability honestly.

## Files

Files opens from the system navigation to Home, with the listing focused. Opening a folder or file is its primary action. Circle walks up to the current place; Circle from Places closes Files, and a picker returns to the app that opened it.

Places attaches to the left edge, with a marker and subtle fill for the current location. Controller focus uses the shared outline independently of that marker. The footer maps Cross to Open, Circle to Back, Square to Select and Triangle to Search. Options contains file actions and view settings; closing it returns to the file. Trash bin is a persistent Place with an item count, a normal listing and restore actions. Empty trash bin appears in Options and requires confirmation before permanent deletion. Pickers omit Trash bin.

The listing fills the remaining region. Details uses aligned Name, Size and Modified columns, hiding Modified and then Size as width runs out. Rows reflow in place when the display changes. Icons and Compact keep their existing file behavior. Split view keeps both locations and selections; below 1100 logical pixels it displays the active pane at full width, with L1/R1 switching panes. Places becomes a full-width drawer, and Back returns to the listing.

Show item count and sorting beside each pane, selection count beside the title, and operation feedback in the attached footer. Empty folders and empty searches have local messages; failures keep the listing and show the recovery reason in the footer. Transfers yield between chunks and retain their cancellation feedback. Properties opens in the shared edge panel with scrollable facts. Run `scripts/check-design-shell.sh` to check Files navigation, sizing, selection, split panes and focus restoration alongside the OS surfaces.

## Tutorials and feedback

Teach one action at the point it is needed. Use a short inline instruction, a restrained highlight and a controller-accessible dismissal. Preserve essential help after onboarding; persistent footer glyphs can teach Select, Back and Options. Avoid tutorial modals that cover the task.

When adding dismissible onboarding, persist completion and provide replay from Settings. Restore focus after dismissal. Do not add a tutorial merely to explain an obvious label.

## Accessibility and motion

Normal text needs at least 4.5:1 contrast and qualifying large text at least 3:1. Validate contrast against actual artwork, not just colour swatches. Focus and interactive boundaries must remain distinguishable.

Support keyboard and controller navigation, visible focus, semantic controls and accessible names. Web and touch products should retain approximately 44 logical-pixel targets where practical. Long lists must follow focus into view; a focused item outside the visible area is a failure.

Focus responds immediately. Keep rail movement around 100–140 ms and panel movement around 160–200 ms. Respect reduced-motion preferences, removing movement rather than hiding state changes. Avoid ambient animation and entrance sequences that delay controls.

## Performance

- Decode large hero artwork away from the UI thread, after selection settles for approximately 150 ms.
- Discard obsolete results; rapidly crossing a library should not decode every intermediate background.
- Upload textures on the render/UI thread. Bound artwork caches and resize images to useful display sizes.
- Reuse unchanged card nodes and cached textures. Update text, progress and status in place.
- Avoid unnecessary per-frame work, live blur and repeated filesystem/process calls during focus changes.
- Measure frame time, navigation latency and memory on target hardware before claiming performance improvements.

## Implementation and review

Godot products reuse `shell/src/tv_theme.gd`, `console_button.gd`, `edge_panel.gd` and `list_menu.gd`. Keep shared behaviour in these components rather than copying styles into each screen. Other platforms map these semantic tokens and behaviours to their native components.

For each added product, document its main task, primary action, entry point, Back destination, content sizing rule and loading/error/empty states. Use the shared palette and control states, then apply the product's identity through its name, artwork and content. Add navigation destinations only when they lead to a working surface.

Run `scripts/check-design-shell.sh` for the native home, attached Options menu, Stores bounds and focus restoration. Its optional `MARWANOS_DESIGN_ART` directory accepts real game artwork for local review; generated review fixtures are not shipped with the product.

Before adding a product or surface, verify its primary task, navigation entry/exit, controller focus restoration, loading/error states, narrow and ultrawide layouts, contrast, artwork handling and reduced-motion behaviour. Use actual product content in review captures. Keep any native-runtime limitation explicit in the handoff.

This document is the shared design contract. Update it alongside shared components when an approved design decision changes.
