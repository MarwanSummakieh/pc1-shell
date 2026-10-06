extends Control

## The home screen -- everything the appliance shows when nothing is launched.
##
## WHAT IS LEFT OF IT, and the absence is the current state of the project
## rather than a bug. This file was 2,037 lines; the rail of cards, the
## full-bleed hero artwork behind them and the details sheet they opened were
## about 1,100 of those, and ADR 0012 removed all three along with the library
## they presented. What remains is the chrome that was never Steam-shaped: the
## top bar, the clock and status corner, the process pill, the in-game overlay,
## the launch handlers and the input routing between them.
##
## THE RAIL IS BACK, FED DIFFERENTLY. The old one read a catalogue that knew
## about Steam and nothing else. This one reads the same seam it always did --
## appscan writes /run/marwanos/apps.tsv, installed.gd polls it -- but with more
## scanners behind it: Steam's own manifests, umu for standalone Windows games,
## the store CLIs, a ROM scan. NOTHING IN THIS FILE KNOWS WHICH SOURCE AN ENTRY
## CAME FROM, which is the entire point of putting the seam there. Only card.gd
## looks, and only to print a caption.
##
## Metadata supplies the selected game's title, facts, description and backdrop.
## The bounded artwork cache keeps selection changes from retaining every image.
##
## TWO INVARIANTS, and they outlived the rail's absence so they are written
## here rather than left implicit:
##
##   - Something is always focused. A gamepad UI with no focus owner does not
##     move, and reads as a crashed machine. See _ensure_focus.
##   - The bar cannot be hidden into a dead end. On a machine with nothing
##     installed it is the only focusable surface, so _hide_bar refuses while
##     the rail is empty and _ready reveals it at boot.
##
## THREE ROWS, TWO OF THEM FOCUSABLE. Top is the bar (hidden until Up asks for
## it), middle is the rail -- or, on an empty machine, a sentence standing where
## it would be -- and bottom is the hint row. Up and Down between them are
## explicit and consumed; see _handle_bar_reveal and _handle_bar_return.
##
## The whole layout is built in code rather than in a .tscn. Two reasons, both
## specific to this repo: a scene file is authored by a GUI tool that rewrites it
## on its own schedule (which is how CRLF and unreviewable diffs get into a repo
## that has spent real days on both), and the list it renders has to be built at
## runtime anyway.

const TvTheme = preload("res://src/tv_theme.gd")
const Card = preload("res://src/card.gd")
const IconButton = preload("res://src/icon_button.gd")
const AppOverlay = preload("res://src/app_overlay.gd")
const ListMenu = preload("res://src/list_menu.gd")
const ErrorScreen = preload("res://src/error_screen.gd")
const GameDetails = preload("res://src/game_details.gd")
const GameSummary = preload("res://src/game_summary.gd")
const Icons = preload("res://src/icons.gd")
const ProcessPill = preload("res://src/process_pill.gd")
const ProcessMenu = preload("res://src/process_menu.gd")
const StatusCorner = preload("res://src/status_corner.gd")

## How long after Down carried focus off the bar a card refuses to open its
## details panel. Comfortably past
## FocusRepeat.INITIAL_DELAY (0.40 s), because the press this is defending
## against is exactly the one that has been held that long; short enough that
## a deliberate second press, aimed at a card the person can now see, still
## opens the panel.
const BAR_RETURN_GRACE_MSEC := 550

var _hero: ColorRect = null
var _hero_art: TextureRect = null
var _hero_art_path := ""
var _hero_art_cache: Dictionary = {}
var _game_summary: GameSummary = null
var _summary_row: Control = null

## The rows a fullscreen sheet covers, hidden together rather than painted over
## -- see _set_lower_deck_visible. `_title_block` is the empty-library sentence
## and `_rail_row` is the rail; exactly one of the two is visible at a time.
var _title_block: Control = null
var _rail_row: Control = null
var _hint_row: Control = null
## The top bar's whole row, HIDDEN BY DEFAULT at the owner's request (#12): the
## rail is the home screen, and the bar appears when Up is pressed from it --
## see _handle_bar_reveal for the mechanism and _hide_bar for the way back.
var _bar_row: Control = null
## True while the bar is up only because a failure alert needed somewhere to be
## seen -- see _on_apps_state_changed. Cleared the moment the person moves into
## the bar themselves, because then it is up for them.
var _bar_revealed_for_alert := false
## When the last Down carried focus off the bar and onto a card, in msec. See
## _handle_bar_return and BAR_RETURN_GRACE_MSEC: the press that brings someone
## back down to the rail must not also open the card's details panel.
var _left_bar_msec := -1
var _status: Label = null
var _app_alert: Label = null
var _app_alert_timer: Timer = null
var _open_hint: Control = null
var _options_hint: Control = null
var _overlay: AppOverlay = null
## The details screen is opened from Down on a library card.
## It hides the rail and returns focus to the selected installation on Back.
var _details: Control = null
## The bar's focusable cluster, in the order they sit. Kept as one array as
## well as four members because every wiring loop below wants "all of them" --
## and a fifth icon arriving should not be a fifth line in four places.
var _bar_buttons: Array = []
## The bar's left-hand pill and the menu behind it: what is running in the
## background. It replaced the M.OS wordmark and the notification bell that
## used to share that corner -- see process_pill.gd.
var _process_pill: ProcessPill = null
var _process_menu: ProcessMenu = null
var _gear_button: IconButton = null
var _power_button: IconButton = null
## The wifi glyph and the clock, made one focusable control: A on it opens the
## Info page. See status_corner.gd for why the indicators became the button
## rather than gaining a sibling, and what used to drop from here instead.
var _status_corner: StatusCorner = null

## The strip and the window it slides inside. The strip is wider than the
## screen; the window clips it at the screen edge. See _build_rail.
var _rail_viewport: Control = null
var _rail: HBoxContainer = null

## The rail's cards, in the order the seam supplied them. Empty is a normal
## state and five guards below depend on it being handled: the bar refuses to
## hide, Up does not consume, B does not strand the pad.
var _cards: Array = []

## The card the cursor is on, so the rail can shrink it when the cursor leaves.
var _selected_card: Control = null

var _rail_tween: Tween = null

## Where focus was when a fullscreen surface took the screen, so closing it
## puts the ring back on the icon it was opened from. See _hand_screen_over.
var _last_focused: Control = null
var _windows_feedback := ""


func _ready() -> void:
	# The error mode branches before anything else in this file runs, and that
	# ordering is the whole point rather than a style choice. marwanos-session
	# starts this binary in error mode precisely because the normal path crashed
	# five times in sixty seconds -- so the frame it draws must not touch the
	# catalogue, the cards, the launcher or the rail, any one of which could be
	# what crashed. See error_screen.gd for what this does and does not protect
	# against.
	if ErrorScreen.requested():
		ShellLog.error("starting in ERROR SCREEN mode: the supervision loop gave up on the shell")
		add_child(ErrorScreen.build())
		return

	_build()
	_app_alert_timer = Timer.new()
	_app_alert_timer.one_shot = true
	_app_alert_timer.timeout.connect(_on_app_alert_expired)
	add_child(_app_alert_timer)
	_populate()
	_wire_focus_neighbours()
	_refresh_empty_state()

	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)
	Launcher.minimized.connect(_on_launch_finished)
	Launcher.blocked.connect(_on_launch_blocked)
	Settings.settings_opened.connect(_on_surface_opened)
	Settings.settings_closed.connect(_on_surface_closed)
	Power.power_opened.connect(_on_surface_opened)
	Power.power_closed.connect(_on_surface_closed)
	# Info is a peer surface now rather than a page inside settings, so the rail
	# hides and returns for it through the same pair every other surface uses.
	# That is also what puts focus back on the status corner it was opened from:
	# _hand_screen_over remembers the focus owner, _take_screen_back restores it.
	Info.info_opened.connect(_on_surface_opened)
	Info.info_closed.connect(_on_surface_closed)
	WindowsInstall.opened.connect(_on_surface_opened)
	WindowsInstall.closed.connect(_on_surface_closed)
	DownloadInstall.opened.connect(_on_surface_opened)
	DownloadInstall.closed.connect(_on_surface_closed)
	WindowsInstall.changed.connect(_on_windows_changed)
	WindowsInstall.guided_finished.connect(_on_guided_setup_return)
	WindowsInstall.guided_backgrounded.connect(_on_guided_setup_return)
	Files.files_opened.connect(_on_surface_opened)
	Files.files_closed.connect(_on_surface_closed)
	Browser.opened.connect(_on_surface_opened)
	Browser.closed.connect(_on_surface_closed)
	PlayerOne.player_one_present.connect(_on_player_one_present)
	PlayerOne.player_one_absent.connect(_on_player_one_absent)
	SystemStatus.network_changed.connect(_on_network_changed)
	Notifications.received.connect(_on_system_notification)
	# A game finishing its download and an application being removed arrive
	# through the same door, because to this screen they are the same event:
	# the library is different now. GameArt.changed used to be a third path
	# into the same rebuild and is gone with the artwork cache it fed.
	Installed.apps_changed.connect(_on_apps_changed)
	_refresh_status()
	# SystemStatus polled once in its own _ready, which ran before this one, so
	# this is the current answer rather than a default -- the first frame the
	# TV shows already carries the wifi glyph if the machine has said Offline.
	_on_network_changed(SystemStatus.network)

	# A machine that boots with no pad starts with the bar up and "Reconnect
	# the controller" on it: player_one_absent only fires on a CHANGE, and
	# boot-without-pad is a state, not a change. Same alert reveal as the
	# unplug, so a pad arriving retires it through the same door.
	if not PlayerOne.has_controller() and _bar_row != null:
		_reveal_bar(false)
		_bar_revealed_for_alert = true

	_start_clock()

	# THE BAR STARTS UP ON AN EMPTY MACHINE, and it is the same reasoning as the
	# no-controller case above rather than a new rule: the bar is hidden because
	# the rail is the thing worth looking at, and a machine with nothing
	# installed has no rail. A hidden bar plus a placeholder with no focusable
	# children is a screen the pad cannot move at all -- the dead-gamepad-UI
	# failure _ensure_focus exists to prevent, arrived at from the other side.
	#
	# Gated on the rail being empty, NOT on the bar being hidden: without the
	# guard this reveals the bar on every boot, including the ordinary one where
	# there is a library to look at and the bar is hidden on purpose.
	if _cards.is_empty() and _bar_row != null and not _bar_row.visible:
		_reveal_bar(false)

	# Nothing navigates until something is focused: the viewport's directional
	# navigation starts from the current focus owner, and with none there is no
	# origin to move from. This is the single most common way a gamepad UI ships
	# looking dead.
	_ensure_focus()
	ControllerRouter.mark_shell_ready()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The hero wash: the selected entry's accent, full bleed, heavily dimmed. It
	# is the BASE of the background and the whole of it for an entry with no
	# picture -- which is a normal card, not a broken one: the Files surface has
	# no export to take an icon from, and neither does an app whose flatpak
	# shipped none. It deliberately bleeds past the TV-safe inset -- background
	# may overscan, text may not.
	_hero = ColorRect.new()
	_hero.color = TvTheme.BACKGROUND
	_hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)

	_hero_art = TextureRect.new()
	_hero_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero_art.modulate = Color(1, 1, 1, 0.28)
	_hero_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero_art)

	# Darkens the lower part of the surface so the title and rail keep their
	# contrast whatever the accent is. Anchored to the bottom and given a
	# fraction of the height rather than a pixel count, so it scales with the
	# output the same way every other measurement here does.
	var scrim := TextureRect.new()
	scrim.texture = TvTheme.hero_gradient()
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scrim.anchor_top = 1.0 - TvTheme.HERO_GRADIENT_FRACTION
	scrim.offset_top = 0.0
	scrim.offset_bottom = 0.0
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# THE VERTICAL TV-SAFE INSET ONLY. The horizontal one is applied per row by
	# _inset(), and the rail is deliberately the one row that does not get it.
	#
	# It used to be applied here, to everything at once, and that produced the
	# defect this structure exists to fix: the rail's clip_contents clipped to
	# this container's rect, so cards were guillotined at an invisible line 96 px
	# in from each screen edge with empty background beyond it. A card has to
	# leave the screen at the SCREEN's edge or the eye reads the cut as damage.
	#
	# The rail is background-class furniture, like the hero and the scrim above
	# it: it may bleed. What must stay inside the safe area is the SELECTED card
	# -- which is where the focus ring is and the only card anyone is reading --
	# and that is handled by resting the selection at SAFE_MARGIN_X in
	# _scroll_to_selected rather than by clipping the strip it sits on.
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	add_child(safe)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)

	# HIDDEN BY DEFAULT, at the owner's request: the home screen is the rail and
	# the art, and the bar -- store, files, settings, power, notifications --
	# appears when Up is pressed from the rail. Kept as a field because four
	# other places move it: the reveal, the hide, the empty-rail fallback (a
	# machine with no cards has nothing BUT the bar to focus) and the app alert
	# (a failure must be seen without being asked for). Hiding a VBox child
	# collapses its slot, so the spacer below simply grows and the rail never
	# moves -- the reveal costs no layout jump at the bottom of the screen.
	_bar_row = _inset(_build_topbar())
	_bar_row.visible = false
	column.add_child(_bar_row)
	# Said in the journal because it is a designed absence: a bar missing from
	# the first frame is this line, not a build that lost the top of the UI.
	ShellLog.info("top bar starts hidden; Up from the rail reveals it")

	# Pushes everything below it to the bottom of the surface. The rail sitting
	# low is not a style choice: the hero art it is drawn over is the thing being
	# selected, and covering the middle of it with cards would hide what the
	# selection is for.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_game_summary = GameSummary.new()
	_summary_row = _inset(_game_summary)
	column.add_child(_summary_row)

	# THE PLACEHOLDER AND THE RAIL ARE BOTH BUILT, and only one of them is ever
	# visible -- see _refresh_empty_state. A machine with nothing installed gets
	# a sentence; a machine with a library gets the library. Building both up
	# front rather than swapping nodes on every change means an install arriving
	# is a visibility flip, not a rebuild of the row above the one being read.
	_title_block = _inset(_build_home_placeholder())
	column.add_child(_title_block)
	_rail_row = _build_rail()
	column.add_child(_rail_row)
	_hint_row = _inset(_build_hints())
	column.add_child(_hint_row)


## The stand-in home screen: two lines, no focusable children.
##
## No focus owner here is deliberate and is why _ensure_focus now aims at the
## bar. A screen whose only focusable things are on a hidden bar would be a dead
## screen if the bar stayed hidden, so _ready reveals it when there is nothing
## else to look at -- the same door the no-controller alert uses.
func _build_home_placeholder() -> Control:
	var block := VBoxContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_constant_override("separation", 4)

	var headline := Label.new()
	headline.text = "Library"
	headline.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	headline.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(headline)

	var line := Label.new()
	line.text = "Nothing installed yet. Press Up for the bar."
	line.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	line.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(line)

	return block


## The rail: one row, full bleed, clipped to the screen edge.
##
## FULL BLEED AND NOT INSET, which is the one row that breaks the safe-area
## rule and the reason is a defect this structure was built to fix. Clipping
## the strip to the safe area guillotines cards at an invisible line 96 px in
## from each screen edge, and the eye reads that cut as damage. A card has to
## leave the screen AT the screen's edge. What stays inside the safe area is
## the SELECTED card, which _scroll_to_selected parks at SAFE_MARGIN_X.
func _build_rail() -> Control:
	_rail_viewport = Control.new()
	_rail_viewport.clip_contents = true
	_rail_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Room for the tallest state (a focused card) plus the caption block that
	# hangs below it, so a selection growing does not shove the hint row down.
	_rail_viewport.custom_minimum_size = Vector2(0, TvTheme.CARD_FOCUSED_SIZE + 96)

	_rail = HBoxContainer.new()
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_theme_constant_override("separation", TvTheme.CARD_GAP)
	_rail.position = Vector2(TvTheme.SAFE_MARGIN_X, 0)
	_rail_viewport.add_child(_rail)

	return _rail_viewport


## Build one card per entry, in the order the seam supplied them.
##
## Installed supplies recently played order. Unplayed entries retain scanner
## order, and _on_apps_changed restores the selected installation by stable ID.
func _populate() -> void:
	for card in _cards:
		_rail.remove_child(card)
		card.queue_free()
	_cards.clear()

	for entry in Installed.apps:
		var card := Card.new()
		card.setup(entry)
		card.selected.connect(_on_card_selected)
		card.details_requested.connect(_open_details.bind(entry))
		_rail.add_child(card)
		_cards.append(card)

	ShellLog.info("home rail ready with %d cards" % _cards.size())


## The cursor moved onto a card: grow it, shrink the last one, slide the strip.
func _on_card_selected(entry: Dictionary) -> void:
	var card := get_viewport().gui_get_focus_owner()
	if card == null or not _cards.has(card):
		return

	if is_instance_valid(_selected_card) and _selected_card != card:
		_selected_card.set_selected_size(false)
	_selected_card = card
	card.set_selected_size(true)
	_game_summary.show_entry(entry)
	_update_hero_art(entry)

	_scroll_to_selected()
	# The bar's way back down has to follow the cursor, or Down from the bar
	# lands on whatever was selected when the bar went up. One source of truth
	# for "where the person's place is" -- see _handle_bar_return.
	for button in _bar_buttons:
		if is_instance_valid(button):
			button.focus_neighbor_bottom = button.get_path_to(card)

	ShellLog.info("selected %s" % str(entry.get("id", "")))


func _update_hero_art(entry: Dictionary) -> void:
	var assets: Dictionary = entry.get("metadata", {}).get("assets", {})
	var path := str(assets.get("background", {}).get("path", ""))
	if path.is_empty():
		path = str(assets.get("header", {}).get("path", ""))
	if path == _hero_art_path:
		return
	_hero_art_path = path
	_hero_art.texture = null
	if path.is_empty():
		return
	if not _hero_art_cache.has(path):
		var image := Icons.load_icon_image(path)
		if image == null:
			return
		# Bound backdrop memory even when the provider supplies very large art.
		var ratio := minf(1.0, minf(1920.0 / image.get_width(), 1080.0 / image.get_height()))
		if ratio < 1.0:
			image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)))
		if _hero_art_cache.size() >= 4:
			_hero_art_cache.erase(_hero_art_cache.keys()[0])
		_hero_art_cache[path] = ImageTexture.create_from_image(image)
	_hero_art.texture = _hero_art_cache[path]


## Park the selected card's left edge on the safe margin by sliding the STRIP,
## not by moving a highlight.
##
## This is the property that stops the eye re-finding the cursor after every
## press: the selection stays put and the library moves underneath it.
func _scroll_to_selected() -> void:
	if _rail == null or not is_instance_valid(_selected_card):
		return
	# Deferred one frame: the card was resized this frame and the HBox has not
	# laid out yet, so its position is still the old one.
	await get_tree().process_frame
	if _rail == null or not is_instance_valid(_selected_card):
		return

	var target := TvTheme.SAFE_MARGIN_X - _selected_card.position.x
	if _rail_tween != null and _rail_tween.is_valid():
		_rail_tween.kill()
	_rail_tween = create_tween()
	_rail_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rail_tween.tween_property(_rail, "position:x", target, TvTheme.RAIL_TWEEN_SECONDS)


## Exactly one of the rail and the empty-library sentence is visible.
func _refresh_empty_state() -> void:
	var has_library := not _cards.is_empty()
	if _summary_row != null:
		_summary_row.visible = has_library
	if not has_library and _hero_art != null:
		_hero_art.texture = null
		_hero_art_path = ""
	if _rail_row != null:
		_rail_row.visible = has_library
	if _title_block != null:
		_title_block.visible = not has_library


## The seam said the library changed: rebuild, and put the cursor back where it
## was if that entry is still there.
##
## REMEMBERED BY ID, not by node. Every card is freed and rebuilt here, so the
## control that had focus a moment ago is a dangling reference by the time this
## needs to restore anything.
func _on_apps_changed(_apps: Array) -> void:
	var focused_id := ""
	var owner := get_viewport().gui_get_focus_owner()
	var rail_focused := owner != null and _cards.has(owner)
	if rail_focused:
		focused_id = str(owner.entry.get("id", ""))
	elif is_instance_valid(_last_focused) and _cards.has(_last_focused):
		focused_id = str(_last_focused.entry.get("id", ""))

	_populate()
	_wire_focus_neighbours()
	_refresh_empty_state()

	var restored: Control = null
	for card in _cards:
		if str(card.entry.get("id", "")) == focused_id:
			restored = card
			break
	if restored != null:
		_last_focused = restored
		if visible and rail_focused:
			restored.grab_focus()
	else:
		_ensure_focus()


## deliberately does not -- see the comment in _build().
func _inset(control: Control) -> Control:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	margin.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	margin.add_child(control)
	return margin


func _build_topbar() -> Control:
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Explicit, because the bar's right-hand end is a run of independent items --
	# the app alert, the controller line, three icons and the clock -- and at the
	# container default the alert ran straight into "Reconnect the controller"
	# with no gap, reading as one impossible sentence. Caught on the Xvfb run.
	bar.add_theme_constant_override("separation", TvTheme.HINT_GAP)

	# THE PROCESSES PILL, and it is the only thing in the bar's left corner now.
	# Two things used to share it: the drawn "M.OS" wordmark, and a notification
	# bell beside it. Both are gone at the owner's request (2026-08-12) and
	# neither is missed by anything -- the wordmark was furniture that said the
	# same thing on every screen forever, and the bell named a surface this shell
	# has never had. What the bell actually opened was the list of background
	# processes, so the control that replaced it is named and shaped for that.
	# See process_pill.gd. It is added to _bar_buttons below with the rest of the
	# focusables so the neighbour table picks it up without a special case.
	_process_pill = ProcessPill.new()
	_process_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_process_pill.activated.connect(_open_process_menu)
	bar.add_child(_process_pill)
	bar.add_child(_bar_gap())

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	# Controller state lives in the bar rather than in a modal overlay. A pad that
	# has been unplugged should not also take the home screen away -- the person
	# is reaching for a cable, and the UI they come back to should be the one they
	# left, with the selection where it was.
	# THE APP ALERT, and it is a separate label from the controller line rather
	# than a second thing that line can say. An install failing and a pad
	# falling off the air are independent -- both can be true at once -- and a
	# single label would have to pick one and silently drop the other.
	#
	# Empty and invisible almost always. It exists because an uninstall is
	# started from the rail and finishes somewhere the person is not looking:
	# without this the only report of a failure was the journal, on a machine
	# with no terminal to read it from.
	_app_alert = Label.new()
	_app_alert.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	_app_alert.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	_app_alert.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_app_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app_alert.visible = false
	bar.add_child(_app_alert)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_status)

	bar.add_child(_bar_gap())

	# Built-in tools share the shell screen and controller focus.
	_gear_button = _bar_button("gear", "Settings", Settings.open)
	_bar_button("download", "Install", WindowsInstall.open)
	_bar_button("folder", "Files", Files.open)
	_bar_button("browser", "Browser", Browser.open)
	# The power menu, asked for by name: off, restart, sleep, next to the
	# others.
	_power_button = _bar_button("power", "Power", Power.open)

	# THE STATUS CORNER IS THE LAST FOCUSABLE, rightmost because it is the
	# corner: the wifi glyph and the clock, which used to be loose indicators
	# here, are now the face of one button (#13). A on it opens the Info page --
	# it used to drop a quick settings panel, which was a copy of four other
	# surfaces and is deleted; see status_corner.gd. Appended by hand rather than
	# through _bar_button because it is not an IconButton -- but into the same
	# array, so the neighbour table still cannot drift from what is on the bar.
	_status_corner = StatusCorner.new()
	_status_corner.activated.connect(Info.open)
	_bar_buttons.append(_status_corner)

	for index in _bar_buttons.size():
		bar.add_child(_bar_buttons[index])
		# No gap after the last one: the corner ends the bar, and a trailing
		# gap would hold it off the safe area's right edge for nothing.
		if index + 1 < _bar_buttons.size():
			bar.add_child(_bar_gap())

	# THE PILL JOINS THE FOCUS CHAIN AFTER the loop above, not before it: it was
	# already parented to the bar at the far left, and letting the loop see it
	# would re-add it on the right. Index 0 because it IS leftmost, so left off
	# the store lands on it and the neighbour table needs no special case.
	#
	# ONLY WHILE IT HAS SOMETHING TO SHOW. A hidden control in the chain is a
	# focus trap on exactly one machine -- a fresh one, before the first-boot
	# installer has finished putting Steam on it -- and that is the machine least
	# able to recover from a pad that stops responding.
	# _on_pill_membership_changed puts it back the moment there is a process to
	# list.
	if _process_pill != null and _process_pill.visible:
		_bar_buttons.insert(0, _process_pill)
	Installed.apps_changed.connect(_on_pill_membership_changed)

	# The wifi glyph and the clock used to end the bar here as loose indicator
	# Labels. They still end it -- inside the status corner appended above,
	# where they double as the Info page's button. The rules about what the wifi
	# fan may claim went with them; see status_corner.set_network.
	return bar


## One icon in the bar's cluster, built and remembered. The registration into
## _bar_buttons is the point: the neighbour tables below walk that array, so an
## icon that is built is an icon that is wired, and the two cannot drift.
func _bar_button(kind: String, label_text: String, action: Callable) -> IconButton:
	var button := IconButton.new()
	button.setup(kind, label_text)
	button.activated.connect(action)
	_bar_buttons.append(button)
	return button


func _bar_gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(TvTheme.SECTION_GAP, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	# Kept as a member because it is hidden when the rail is empty -- see
	# _refresh_empty_state. B stays: it is inert at the rail but the glyph is
	# how a person learns that, and the top bar's icons still take an A.
	_open_hint = TvTheme.hint("A", "Open")
	hints.add_child(_open_hint)
	hints.add_child(TvTheme.hint("↓", "Details"))
	# OPTIONS is the only route to removing an application on a machine with no
	# terminal, so it is advertised rather than left to be discovered. Hidden
	# with the A hint when the rail is empty -- there is nothing to have options
	# about -- which is why it is a member too.
	_options_hint = TvTheme.hint("OPTIONS", "Options")
	hints.add_child(_options_hint)
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


## end up disagreeing.
func _on_pill_membership_changed(_apps: Array) -> void:
	if _process_pill == null:
		return
	var present := _bar_buttons.has(_process_pill)
	if _process_pill.visible == present:
		return
	if _process_pill.visible:
		_bar_buttons.insert(0, _process_pill)
	else:
		_bar_buttons.erase(_process_pill)
	_wire_focus_neighbours()
	ShellLog.info("processes pill %s the bar's focus chain"
		% ("joined" if _process_pill.visible else "left"))


## Two rows, one axis each, hard stops at both ends.
##
## EVERY NEIGHBOUR IS STATED, including the ones that point at the control
## itself. An unset neighbour lets Control's geometric search wander off and
## find something that was never meant to be reachable -- the hint row, or a
## card three screens away -- and the resulting press goes somewhere invisible.
## A self-reference is a hard stop the search cannot get past.
##
## Up and Down between the two rows are NOT in this table. They are consumed in
## _input by _handle_bar_reveal and _handle_bar_return, because the bar hides,
## and a neighbour path into a hidden control is a press Godot drops with a
## warning rather than a move somebody sees.
func _wire_focus_neighbours() -> void:
	var card_count := _cards.size()
	for index in card_count:
		var card: Control = _cards[index]
		var left := index - 1 if index > 0 else index
		var right := index + 1 if index + 1 < card_count else index

		card.focus_neighbor_left = card.get_path_to(_cards[left])
		card.focus_neighbor_right = card.get_path_to(_cards[right])
		card.focus_neighbor_top = card.get_path_to(card)
		card.focus_neighbor_bottom = card.get_path_to(card)

	var count := _bar_buttons.size()
	for index in count:
		var button: Control = _bar_buttons[index]
		var previous := index - 1 if index > 0 else index
		var next := index + 1 if index + 1 < count else index

		button.focus_neighbor_left = button.get_path_to(_bar_buttons[previous])
		button.focus_neighbor_right = button.get_path_to(_bar_buttons[next])
		button.focus_neighbor_top = button.get_path_to(button)
		# Down goes to the selected card once one exists; _on_card_selected
		# keeps it following the cursor after that.
		var below: Control = _cards[0] if card_count > 0 else button
		button.focus_neighbor_bottom = button.get_path_to(below)


## Put focus somewhere, or the pad moves nothing.
##
## THREE CANDIDATES IN ORDER, and the order is what makes each landing the
## least surprising one available.
##
## _last_focused first, and it is why _hand_screen_over bothers to record it:
## closing Settings should return the ring to the gear it was opened from, not
## to whatever happens to be leftmost. Validity is checked rather than assumed
## -- the remembered control may have been freed while the covering screen was
## up, which is exactly what happens to every card on a library rebuild.
##
## Then the rail, because the rail is the home screen. Then the bar, which is
## the empty-machine fallback and the reason _ready reveals it in that case: a
## focus ring on a hidden control is worse than none, since the pad moves,
## nothing on screen changes, and the machine reads as crashed.
func _ensure_focus() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	if is_instance_valid(_last_focused) and _last_focused.visible \
			and _last_focused.is_inside_tree():
		_last_focused.grab_focus()
		return
	if not _cards.is_empty():
		_cards[0].grab_focus()
		return
	for button in _bar_buttons:
		if is_instance_valid(button) and button.visible:
			button.grab_focus()
			return
	ShellLog.warn("nothing focusable on the home screen; the pad will not move")


## builds an hour on a machine that is rendering nothing else.
func _start_clock() -> void:
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(_refresh_clock)
	add_child(timer)
	_refresh_clock()


func _refresh_clock() -> void:
	if _status_corner == null:
		return
	var now := Time.get_time_dict_from_system()
	_status_corner.set_clock("%02d:%02d" % [int(now.get("hour", 0)), int(now.get("minute", 0))])


func _on_launch_started(_entry: Dictionary) -> void:
	_hand_screen_over()


func _on_launch_blocked(detail: String) -> void:
	if _app_alert != null:
		_app_alert.text = detail
		_app_alert.show()
		_app_alert_timer.start(APP_ALERT_SECONDS)
		_reveal_bar(false)
		_bar_revealed_for_alert = true


func _on_system_notification(entry: Dictionary) -> void:
	# Store every notification centrally; show a brief alert only on home.
	# Never focus or expose the shell over a running application.
	if visible and not Launcher.is_busy() and not Info.is_open():
		_on_launch_blocked("%s: %s" % [str(entry.get("app", "")), str(entry.get("summary", ""))])


func _on_windows_changed() -> void:
	var state: Dictionary = WindowsInstall.snapshot
	var detail := WindowsInstall.message
	if str(state.get("operation", "")) in ["remove", "discard"] and str(state.get("status", "")) == "failed":
		detail = str(state.get("detail", "Could not remove the app. Try again."))
	if visible and not detail.is_empty() and detail != _windows_feedback:
		_windows_feedback = detail
		_on_launch_blocked(detail)


func _on_launch_finished(_entry: Dictionary) -> void:
	if is_instance_valid(_process_pill):
		_process_pill.visible = Launcher.is_minimized() or not Services.visible_services().is_empty()
		_on_pill_membership_changed([])
	# The app went away -- via the overlay's Close, or on its own. Either way
	# the overlay is now framing nothing, so it goes first.
	_close_overlay()
	# A launch can start FROM the stores screen, in which case that screen is
	# what the person should land back on when the app quits -- not the rail
	# grabbing focus to a card that is drawn underneath an open surface. The
	# surface's own close is what restores the rail.
	if Settings.is_open() or WindowsInstall.is_open() or Files.is_open() or Browser.is_open():
		return
	_take_screen_back()


func _on_surface_opened() -> void:
	_hand_screen_over()


func _on_surface_closed() -> void:
	_take_screen_back()


func _on_guided_setup_return() -> void:
	if visible and not WindowsInstall.is_open() and not Files.is_open() and not Browser.is_open() and not Settings.is_open():
		_ensure_focus()


## Shared by the launch seam and both shell surfaces: from the rail's point of
## view "something fullscreen is up" is one state, however it was reached, and
## having one implementation is what guarantees the seams cannot drift apart
## in how they give the screen back.
func _hand_screen_over() -> void:
	# Captured before hiding: hiding a Control releases focus, so asking
	# afterwards would always answer null. Captured only while VISIBLE: a
	# launch that starts from inside the stores screen arrives here with the
	# rail already hidden, and overwriting the remembered card with a store
	# tab would strand focus on a freed control when the rail finally returns.
	if visible:
		_last_focused = get_viewport().gui_get_focus_owner()
	hide()
	# Hiding a Control stops it drawing and stops it receiving GUI input, but
	# _unhandled_input keeps arriving regardless. The covering screen is a later
	# sibling and so is called first, and it consumes the press -- but relying on
	# dispatch order for "B does not do two things at once" is the kind of
	# assumption that breaks silently when a node is reparented.
	set_process_unhandled_input(false)


func _take_screen_back() -> void:
	show()
	set_process_unhandled_input(true)
	_ensure_focus()


func _on_player_one_present(_device: int, _pad_name: String) -> void:
	_refresh_status()
	# A controller arriving is also the moment a shell that came up with nothing
	# focused becomes usable, so take the opportunity.
	_ensure_focus()
	# And the moment the "Reconnect the controller" line stops being true, so
	# the bar it summoned can stand down (unless something else still needs it
	# -- _retire_alert_reveal checks).
	_retire_alert_reveal()


## The pad going away is the second thing that summons the hidden bar
## unprompted (#12), for the app alert's exact reason: the line lives in the
## bar so that losing a pad does not take the home screen away -- but a bar
## that stays hidden over "Reconnect the controller" is a message to nobody,
## written on a machine whose one input device just left.
func _on_player_one_absent() -> void:
	_refresh_status()
	if _bar_row != null and not _bar_row.visible:
		_reveal_bar(false)
		_bar_revealed_for_alert = true


## How long a failure stays in the top bar. It has to outlast someone looking
## away -- a removal is started and then watched for on the rail -- and it must
## not become permanent furniture, because appctl's state file keeps saying
## "failed" until the next request and a line that never leaves stops being
## read. Cleared early by any state change, which is the normal way it goes.
const APP_ALERT_SECONDS := 20.0


func _on_app_alert_expired() -> void:
	if _app_alert != null:
		_app_alert.visible = false
		_app_alert.text = ""
	_retire_alert_reveal()


## The bar came up for an alert alone; the alert is gone, so the bar goes too
## -- UNLESS the person moved into it meanwhile, in which case it is up for
## them and leaves when they do. Checked on the focus owner rather than on the
## flag alone because Up during an alert takes the reveal over (see
## _reveal_bar) and this is the belt to that brace.
func _retire_alert_reveal() -> void:
	if not _bar_revealed_for_alert:
		return
	# The app alert and the controller line are independent -- both can be true
	# at once, which is why they are two labels (see _build_topbar) -- so one
	# resolving must not hide the other. Either alone keeps the bar up.
	if _app_alert != null and _app_alert.visible:
		return
	if not PlayerOne.has_controller():
		return
	_bar_revealed_for_alert = false
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or not _bar_buttons.has(owner):
		_hide_bar()


func _refresh_status() -> void:
	if _status == null:
		return
	if PlayerOne.has_controller():
		_status.text = "Player 1  %s" % PlayerOne.pad_name
		_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	else:
		_status.text = "Reconnect the controller"
		_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)


## autoload that can subscribe for itself.
func _on_network_changed(state: String) -> void:
	if _status_corner != null:
		_status_corner.set_network(state)


## THE HOME BUTTON IS HANDLED IN _input, NOT _unhandled_input, and that is the
## only place it could go. `_hand_screen_over` turns unhandled input off for
## the whole time an application is running -- which is exactly when the home
## button has to work. `_input` keeps arriving on a Node regardless of whether
## the Control is visible, so this is the one hook still alive while the rail
## is hidden behind a launch.
##
## Everything else is left alone: this consumes nothing unless there is a
## running application and the press is the home button, or the press is the
## Up that summons the hidden top bar (see _handle_bar_reveal).
func _input(event: InputEvent) -> void:
	if _handle_home_button(event):
		return
	if _handle_bar_reveal(event):
		return
	_handle_bar_return(event)


func _handle_home_button(event: InputEvent) -> bool:
	if not InputMap.has_action("ui_shell_home"):
		return false
	if not event.is_action_pressed("ui_shell_home"):
		return false
	if not Launcher.is_busy() or not Launcher.can_close():
		# No process to offer anything about. The placeholder branch has no pid
		# and is dismissed with B, and at the rail the button means nothing.
		return false
	if _overlay != null:
		return false
	get_viewport().set_input_as_handled()
	_open_overlay()
	return true


## UP FROM THE RAIL SUMMONS THE BAR (#12). Caught in _input rather than
## through the focus-neighbour table, and the placement is forced, not a
## style choice: the bar is hidden, a hidden control cannot take focus, so a
## neighbour path pointing into it would be a press Godot drops -- and by the
## time _unhandled_input would see the event, the viewport's focus traversal
## has already consumed every arrow that lands on a focused control. _input
## runs before both, which makes it the one hook that can show the bar and
## move focus into it on the same press.
##
## The focus owner must be a card: Up means "to the bar" only from the rail,
## and anywhere else this consumes nothing. See _bar_input_live for the
## surfaces that switch both of the bar's moves off.
func _handle_bar_reveal(event: InputEvent) -> bool:
	if not _bar_input_live():
		return false
	if not event.is_action_pressed("ui_up"):
		return false
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or not _cards.has(owner):
		return false
	get_viewport().set_input_as_handled()
	_reveal_bar(true)
	return true


## THE HOME SCREEN IS THREE ROWS: the bar, the selected entry's title block,
## and the card rail. Only two of them are focusable -- the title block is
## prose about whatever the cursor is on -- so DOWN FROM THE BAR GOES TO THE
## CARDS, past the middle row, and that is the whole of this function.
##
## HANDLED HERE RATHER THAN LEFT TO THE NEIGHBOUR TABLE, which is a change from
## how the bar's Down worked before the bar could hide, and the reason is a
## defect the owner hit on the first build: a card's own Down opens its details
## panel (tile.gd's _gui_input), so the press that carries somebody off the bar
## arrives at the card they just landed on and opens the panel over the rail --
## "down gets the info and skips the cards". Worse on a pad than in a harness,
## because FocusRepeat turns a Down held a third of a second too long into a
## second press aimed at the card.
##
## So the move is made here and the event is CONSUMED: no viewport traversal,
## no _gui_input on the arriving card, one press one move. The destination is
## still read from the focused button's own focus_neighbor_bottom, which
## _scroll_to_selected keeps pointed at the selected card -- one source of
## truth for "where the person's place is", not two.
func _handle_bar_return(event: InputEvent) -> void:
	if not _bar_input_live():
		return
	if not event.is_action_pressed("ui_down"):
		return
	if _cards.is_empty():
		# Nothing below the bar to go back to; the bar is the whole screen.
		return
	var owner := get_viewport().gui_get_focus_owner() as Control
	if owner == null or not _bar_buttons.has(owner):
		return
	var below := owner.get_node_or_null(owner.focus_neighbor_bottom) as Control
	if below == null or not _cards.has(below):
		return
	get_viewport().set_input_as_handled()
	# Stamped BEFORE the grab, because the grab is what fires the card's
	# selected signal and everything that hangs off it.
	_left_bar_msec = Time.get_ticks_msec()
	below.grab_focus()


## The states in which the bar's own two moves mean anything: this surface is
## on screen, and nothing is layered over it. `visible` covers the fullscreen
## surfaces, the card menu and a running application, all of which hide this
## node; the details panel and the processes menu do not hide it, so they are
## named. There used to be a second drop menu here (quick settings); it is
## deleted, which is why this reads two names rather than three.
func _bar_input_live() -> bool:
	if not visible or _bar_row == null:
		return false
	return _process_menu == null


## Show the bar. With `take_focus`, also land on the first button on it, and the
## reveal stops being about any alert that triggered it: the person is in the
## bar now, and it stays until they leave.
##
## THE FIRST BUTTON, not a named one. This aimed at the store icon, then at
## Files when the store went, and both are gone -- so it asks _bar_buttons what
## is actually there rather than naming a third icon that will also be deleted.
## The list is in bar order and the processes pill inserts itself at its front,
## so "first" is the leftmost thing on screen either way.
func _reveal_bar(take_focus: bool) -> void:
	if not _bar_row.visible:
		_bar_row.visible = true
		ShellLog.info("top bar revealed")
	if take_focus:
		_bar_revealed_for_alert = false
		for button in _bar_buttons:
			if is_instance_valid(button) and button.visible:
				button.grab_focus()
				return


## Hide the bar again -- unless the rail is empty, in which case the bar is
## the only focusable surface this screen has and taking it away would leave
## the pad pointing at nothing (see _ensure_focus's empty-rail fallback).
func _hide_bar() -> void:
	if _bar_row == null or not _bar_row.visible:
		return
	if _cards.is_empty():
		return
	_bar_revealed_for_alert = false
	_bar_row.visible = false
	ShellLog.info("top bar hidden")


func _open_overlay() -> void:
	Kiosk.remember_app_window(str(Launcher.current_entry().get("input_mode", "")) == "pointer")
	Launcher.set_pad_keys_paused(true)
	Launcher.set_splash_paused(true)
	_overlay = AppOverlay.new()
	_overlay.entry = Launcher.current_entry()
	_overlay.closed.connect(_on_overlay_closed, CONNECT_ONE_SHOT)
	# Added to the root rather than to this node: the rail is hidden while an
	# app runs, and a child of a hidden Control does not draw.
	get_tree().root.add_child(_overlay)
	# The window comes BACK before the overlay flag goes on, and the order is
	# the whole of it: under the `yield` window profile this window is minimised
	# while an app is on screen (see Kiosk.yield_screen), and a menu composited
	# into an unmapped window is a home button that does nothing.
	Kiosk.yield_screen(false)
	# Ask gamescope to composite us over the application rather than instead of
	# it. See Kiosk.set_overlay -- if this does not take, the overlay still
	# works, it just covers the app.
	Kiosk.set_overlay(true)
	# While the overlay is up the pad belongs to the overlay. Without this a
	# bridged application (Dolphin) receives an arrow for every menu move and a
	# BackSpace for the B that closes the menu -- input delivered twice, acted
	# on twice, visible once.
	#
	# IT STAYS PAUSED THROUGH THE KEYBOARD TOO, and that is why this is paired
	# with the overlay's lifetime rather than with the menu panel's. The menu's
	# Type entry swaps the panel for the on-screen keyboard on the same node
	# (see app_overlay.gd) -- so nothing here fires in between, and a stick
	# crossing a 5x10 grid cannot also be arrowing around the application
	# behind it. The bridge resumes in _close_overlay, once.
	Launcher.set_pad_keys_paused(true)
	# The launch splash stands down for the same span. It is only ever still up
	# when the application has not drawn yet -- which is precisely when someone
	# presses home to ask what is going on -- and its input eating would swallow
	# the A that chooses a menu entry. See launch_splash.gd.
	Launcher.set_splash_paused(true)


func _on_overlay_closed() -> void:
	_close_overlay.call_deferred()


## The overlay's single teardown, and it is single on purpose: the keyboard the
## Type entry puts up is a CHILD of the overlay, not a surface of its own, so
## freeing the overlay frees it too. That is what makes the awkward path safe --
## the application exiting while someone is mid-word arrives at
## _on_launch_finished, which calls this, and the keys go with the menu, the
## gamescope overlay flag and the pad-bridge pause. A sibling screen would have
## needed its own branch here and would have been the branch that got missed.
func _close_overlay() -> void:
	if _overlay == null:
		return
	var overlay := _overlay
	_overlay = null
	overlay.get_parent().remove_child(overlay)
	overlay.queue_free()
	Kiosk.set_overlay(false)
	# And back out of the way, if there is still something out there to get out
	# of the way FOR. Asked of the launch seam rather than of is_busy(): a
	# launch that never drew is busy too, and minimising for it would leave the
	# TV with nothing on it at all. See Kiosk.yield_screen.
	if Launcher.app_on_screen():
		Kiosk.focus_app()
		Kiosk.yield_screen(true)
	Launcher.set_pad_keys_paused(false)
	Launcher.set_splash_paused(false)


## ---------------------------------------------------------------------------
## The details panel
## ---------------------------------------------------------------------------

## a rebuild may have freed one of them.
func _set_lower_deck_visible(shown: bool) -> void:
	for node in [_title_block, _rail_row, _hint_row]:
		if is_instance_valid(node):
			node.visible = shown


func _open_details(entry: Dictionary) -> void:
	if not visible or _details != null or _process_menu != null or Launcher.is_busy():
		return
	_details = GameDetails.new()
	_details.entry = entry
	_details.closed.connect(func(): _close_details.call_deferred(), CONNECT_ONE_SHOT)
	_hand_screen_over()
	get_tree().root.add_child(_details)


func _close_details() -> void:
	if _details == null:
		return
	_details.get_parent().remove_child(_details)
	_details.queue_free()
	_details = null
	if not Launcher.is_busy():
		_take_screen_back()


## The processes menu, from the pill in the bar's left corner. Same guards as
## the card menu: not while another surface owns the screen, and not twice.
##
## THIS IS THE ONLY DROP MENU LEFT ON THE BAR. There were two -- this one and a
## quick settings panel behind the status corner -- and the second was a copy of
## four other surfaces (see status_corner.gd for the inventory). It is deleted,
## along with the second set of open/close handlers that lived here, the second
## STATE_WORDS table, and the Containerfile assertion that existed only to keep
## the two tables agreeing.
func _open_process_menu() -> void:
	if _process_menu != null or _details != null:
		return
	if Settings.is_open() or Power.is_open() \
			or Info.is_open() or Files.is_open() or Browser.is_open() or WindowsInstall.is_open() or Launcher.is_busy():
		return

	_process_menu = ProcessMenu.new()
	_process_menu.closed.connect(_on_process_menu_closed, CONNECT_ONE_SHOT)
	# A child of the ROOT rather than of this node, for the overlay's reason: the
	# rail hides itself while other surfaces are up, and a child of a hidden
	# Control does not draw.
	get_tree().root.add_child(_process_menu)
	# Deaf while it is up: the menu's own _unhandled_input owns B, and both
	# reacting would close the menu and act on the rail behind it on one press.
	set_process_unhandled_input(false)


func _on_process_menu_closed() -> void:
	_close_process_menu.call_deferred()


func _close_process_menu() -> void:
	if _process_menu == null:
		return
	var menu := _process_menu
	_process_menu = null
	menu.get_parent().remove_child(menu)
	menu.queue_free()
	set_process_unhandled_input(true)
	# The menu took focus; hand it back to the pill it came from, so the bar does
	# not come back ringless and looking like the pad has stopped working.
	if _process_pill != null and _process_pill.visible:
		_process_pill.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_shell_options") and is_instance_valid(_selected_card):
		get_viewport().set_input_as_handled()
		WindowsInstall.confirm_remove(_selected_card.entry)
		return
	# WHILE THE PANEL IS UP, THE RAIL IS NOT LISTENING. The panel is a later
	# child and so is offered unhandled input first, and it consumes B -- but
	# relying on dispatch order for "B does not do two things at once" is the
	# assumption _hand_screen_over already refuses to make, and OPTIONS is not
	# consumed by anything.
	if _details != null:
		return

	# OPTIONS HAS NOTHING TO OPEN. It opened the focused card's menu -- rename,
	# remove, properties -- and there are no cards. The action is deliberately
	# left unbound rather than swallowed here: an OPTIONS press that is silently
	# consumed is indistinguishable from one that opened an empty menu, and the
	# menu it opened (list_menu.gd) is kept for whatever renders the sources.

	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()

	# B IN THE BAR RETURNS TO THE RAIL AND RE-HIDES IT (#12) -- the mirror of
	# the Up that summoned it. The landing card is resolved through the focused
	# button's own down-neighbour rather than remembered separately, because
	# _scroll_to_selected already keeps that pointed at the selected card and a
	# second copy of "where is the person's place" is how the two would drift.
	# On an empty rail the guard fails and B falls through to the log below:
	# the bar is the only surface, and backing out of it would strand the pad.
	var owner := get_viewport().gui_get_focus_owner()
	if _bar_row != null and _bar_row.visible and owner != null \
			and _bar_buttons.has(owner) and not _cards.is_empty():
		var below := owner.get_node_or_null(owner.focus_neighbor_bottom) as Control
		if below != null:
			below.grab_focus()
			# The grab lands on a card, whose selected signal hides the bar --
			# see _on_card_selected -- so nothing more to do here.
			return

	# The home rail is the root of the shell, so there is nowhere to back out to
	# and nothing here quits. Exiting would be a client exit as far as
	# marwanos-session is concerned: the supervision loop would count it as a
	# crash, restart it, and five of those inside sixty seconds would trip the
	# guard and draw the error screen. B is inert here on purpose.
	ShellLog.info("back pressed at the home rail; nothing above this")
