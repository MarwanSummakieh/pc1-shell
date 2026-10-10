extends Control

## Console home: user header, artwork rail, primary actions and PS/Home system dock.
## Internal surfaces preserve controller focus; artwork is decoded off the UI thread.
## Layout follows the available viewport. See docs/design-system.md.

const TvTheme = preload("res://src/tv_theme.gd")
const ConsoleButton = preload("res://src/console_button.gd")
const StoresScreen = preload("res://src/stores_screen.gd")
const AchievementsPage = preload("res://src/achievements_page.gd")
const MetadataPage = preload("res://src/metadata_page.gd")
const VolumePopup = preload("res://src/volume_popup.gd")
const Card = preload("res://src/card.gd")
const IconButton = preload("res://src/icon_button.gd")
const AppOverlay = preload("res://src/app_overlay.gd")
const ListMenu = preload("res://src/list_menu.gd")
const ErrorScreen = preload("res://src/error_screen.gd")
const GameSummary = preload("res://src/game_summary.gd")
const Icons = preload("res://src/icons.gd")
const ProcessPill = preload("res://src/process_pill.gd")
const ProcessMenu = preload("res://src/process_menu.gd")
const StatusCorner = preload("res://src/status_corner.gd")
const AchievementToast = preload("res://src/achievement_toast.gd")

var _hero: ColorRect = null
var _hero_art: TextureRect = null
var _hero_text_scrim: TextureRect = null
var _hero_header_scrim: TextureRect = null
var _hero_art_path := ""
var _hero_art_stamp := 0
var _hero_requested_stamp := 0
var _hero_loading_stamp := 0
var _hero_art_cache: Dictionary = {}
var _game_summary: GameSummary = null
var _summary_row: Control = null

## The rows a fullscreen sheet covers, hidden together rather than painted over
## -- see _set_lower_deck_visible. `_title_block` is the empty-library sentence
## and `_rail_row` is the rail; exactly one of the two is visible at a time.
var _title_block: Control = null
var _rail_row: Control = null
var _hint_row: Control = null
## PS/Home toggles the bottom dock and restores the originating content focus.
var _bar_row: Control = null
var _bar_focus_origin: Control = null
var _bar_return_to_steam := false
var _surface_bar_visible := false
## True while the bar is up only because a failure alert needed somewhere to be
## seen -- see _on_apps_state_changed. Cleared the moment the person moves into
## the bar themselves, because then it is up for them.
var _bar_revealed_for_alert := false
var _status: Label = null
var _app_alert: Label = null
var _app_alert_timer: Timer = null
var _open_hint: Control = null
var _options_hint: Control = null
var _overlay: AppOverlay = null
var _achievement_toast: AchievementToast = null
var _volume_popup: VolumePopup = null
var _audio_button: Control = null
## Auxiliary Achievements and Metadata surfaces restore Home on Back.
var _details: Control = null
## The bar's focusable cluster, in the order they sit. Kept as one array as
## well as four members because every wiring loop below wants "all of them" --
## and a fifth icon arriving should not be a fifth line in four places.
var _bar_buttons: Array = []
## The bar's right-hand pill and the menu behind it: what is running in the
## background. It replaced the M.OS wordmark and the notification bell that
## used to share that corner -- see process_pill.gd.
var _process_pill: ProcessPill = null
var _process_menu: ProcessMenu = null
var _gear_button: Control = null
var _power_button: Control = null
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
var _header: Control
var _user_label: Label
var _home_actions: HBoxContainer
var _play_button: Button
var _details_button: Button
var _dock_scroll: ScrollContainer
var _stores: Control
var _card_menu: Control
var _hero_art_timer: Timer
var _hero_poll: Timer
var _hero_worker: Thread
var _hero_loading_path := ""
var _hero_requested_path := ""
var _home_hint: Control
var _layout_queued := false


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
	Downloads.opened.connect(_on_surface_opened)
	Downloads.closed.connect(_on_surface_closed)
	Profiles.opened.connect(_on_surface_opened)
	Profiles.closed.connect(_on_surface_closed)
	Profiles.changed.connect(_on_profile_changed)
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
	if OS.get_environment("MARWANOS_SHELL_WINDOWED").is_empty():
		Profiles.open.call_deferred(true)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_hero = background
	_hero_art = TextureRect.new()
	_hero_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero_art)
	_hero_text_scrim = TextureRect.new()
	_hero_text_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_text_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero_text_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_text_scrim.hide()
	_hero_art.add_child(_hero_text_scrim)
	_hero_header_scrim = TextureRect.new()
	_hero_header_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_header_scrim.texture = TvTheme.home_art_header_gradient()
	_hero_header_scrim.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hero_header_scrim.anchor_bottom = TvTheme.HERO_ART_TOP_FRACTION
	_hero_header_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_header_scrim.hide()
	_hero_art.add_child(_hero_header_scrim)
	_hero_art_timer = Timer.new()
	_hero_art_timer.one_shot = true
	_hero_art_timer.timeout.connect(_begin_hero_art)
	add_child(_hero_art_timer)
	_hero_poll = Timer.new()
	_hero_poll.wait_time = 0.025
	_hero_poll.timeout.connect(_finish_hero_art)
	add_child(_hero_poll)

	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 24)
	add_child(_header)
	_user_label = Label.new()
	_user_label.text = _display_name()
	_user_label.add_theme_font_size_override("font_size", 30)
	_user_label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_user_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_user_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_user_label)
	_app_alert = Label.new()
	_app_alert.add_theme_font_size_override("font_size", 24)
	_app_alert.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	_app_alert.hide()
	_header.add_child(_app_alert)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 24)
	_header.add_child(_status)
	_status_corner = StatusCorner.new()
	_status_corner.activated.connect(Info.open)
	_header.add_child(_status_corner)

	_rail_row = _build_rail()
	add_child(_rail_row)
	_game_summary = GameSummary.new()
	_summary_row = _game_summary
	add_child(_summary_row)
	_summary_row.minimum_size_changed.connect(_queue_layout)
	_home_actions = HBoxContainer.new()
	_home_actions.add_theme_constant_override("separation", 16)
	add_child(_home_actions)
	_play_button = ConsoleButton.new()
	_play_button.text = "Play"
	_play_button.primary = true
	_play_button.pill = true
	_play_button.pressed.connect(func():
		if is_instance_valid(_selected_card):
			_selected_card.activate())
	_home_actions.add_child(_play_button)
	_details_button = ConsoleButton.new()
	_details_button.text = "Options"
	_details_button.icon_only = true
	_details_button.glyph = "more"
	_details_button.pressed.connect(_open_card_menu)
	_home_actions.add_child(_details_button)
	_title_block = _build_home_placeholder()
	add_child(_title_block)
	_hint_row = _build_hints()
	add_child(_hint_row)
	_bar_row = _build_topbar()
	_bar_row.hide()
	add_child(_bar_row)
	resized.connect(_queue_layout)
	_layout_home.call_deferred()


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
	line.text = "No games yet. Press PS/Home to open the system menu."
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
	var previous := {}
	for card in _cards:
		previous[str(card.entry.get("id", ""))] = card
	var next: Array = []
	for entry in Installed.apps:
		if not _home_entry(entry):
			continue
		var id := str(entry.get("id", ""))
		var card: Control = previous.get(id)
		if card != null:
			previous.erase(id)
			card.refresh_entry(entry)
		else:
			card = Card.new()
			card.layout_unit = TvTheme.layout_unit(size)
			card.setup(entry)
			card.selected.connect(_on_card_selected)
			card.details_requested.connect(_focus_game_actions)
			_rail.add_child(card)
		_rail.move_child(card, next.size())
		next.append(card)
	for card in previous.values():
		if card == _selected_card: _selected_card = null
		if card == _last_focused: _last_focused = null
		_rail.remove_child(card)
		card.queue_free()
	_cards = next
	if not is_instance_valid(_selected_card) and not _cards.is_empty():
		_selected_card = _cards[0]
		_selected_card.set_selected_size(true)
	_queue_layout()
	if is_instance_valid(_selected_card) and _cards.has(_selected_card):
		_game_summary.show_entry(_selected_card.entry)
		_update_hero_art(_selected_card.entry)
		_play_button.text = "Continue setup" if _selected_card.entry.has("setup_id") else "Play"
		_play_button.disabled = not _selected_card.is_installed() and not _selected_card.entry.has("setup_id")
	ShellLog.info("home rail ready with %d cards" % _cards.size())


## Stores and download/setup tools have their own system destinations.
func _home_entry(entry: Dictionary) -> bool:
	var id := str(entry.get("id", "")).to_lower()
	var title := str(entry.get("title", "")).to_lower()
	if id in ["steam", "steam.desktop", "com.valvesoftware.steam", "org.freedownloadmanager.manager", "downloads"]:
		return false
	if title in ["steam", "downloads", "free download manager", "fdm", "fdm controller", "fdm classic"]:
		return false
	return not entry.has("setup_id") and str(entry.get("state", "")) == "installed"


func _focus_game_actions() -> void:
	if _bar_row.visible:
		_hide_bar()
	if not _play_button.disabled:
		_play_button.grab_focus()
	else:
		_details_button.grab_focus()


func _on_card_selected(entry: Dictionary) -> void:
	var card := get_viewport().gui_get_focus_owner()
	if card == null or not _cards.has(card):
		return
	if is_instance_valid(_selected_card) and _selected_card != card:
		_selected_card.set_selected_size(false)
	_selected_card = card
	card.set_selected_size(true)
	_game_summary.show_entry(entry)
	_play_button.text = "Continue setup" if entry.has("setup_id") else "Play"
	_play_button.disabled = not card.is_installed() and not entry.has("setup_id")
	_update_hero_art(entry)
	_scroll_to_selected()
	for button in _bar_buttons:
		if is_instance_valid(button):
			button.focus_neighbor_top = button.get_path_to(_play_button)
			button.focus_neighbor_bottom = button.get_path_to(card)
	for button in [_play_button, _details_button]:
		button.focus_neighbor_top = button.get_path_to(card)
		button.focus_neighbor_bottom = button.get_path_to(card)
	ShellLog.info("selected %s" % str(entry.get("id", "")))


func _update_hero_art(entry: Dictionary) -> void:
	var assets: Dictionary = entry.get("metadata", {}).get("assets", {})
	var path := ""
	for kind in ["background", "header", "cover"]:
		var candidate := str(assets.get(kind, {}).get("path", ""))
		if not candidate.is_empty() and FileAccess.file_exists(candidate):
			path = candidate
			break
	if path.is_empty():
		var cover := str(entry.get("cover", ""))
		if not cover.is_empty() and FileAccess.file_exists(cover):
			path = cover
	_hero_requested_path = path
	_hero_requested_stamp = FileAccess.get_modified_time(path) if not path.is_empty() else 0
	if path == _hero_art_path and _hero_requested_stamp == _hero_art_stamp:
		_hero_art_timer.stop()
		return
	_hero_art_timer.start(TvTheme.HERO_ART_DEBOUNCE_SECONDS)


func _scroll_to_selected() -> void:
	if _rail == null or not is_instance_valid(_selected_card):
		return
	# Deferred one frame: the card was resized this frame and the HBox has not
	# laid out yet, so its position is still the old one.
	await get_tree().process_frame
	if _rail == null or not is_instance_valid(_selected_card):
		return

	var target := size.x * 0.05 - _selected_card.position.x
	if _rail_tween != null and _rail_tween.is_valid():
		_rail_tween.kill()
	_rail_tween = create_tween()
	_rail_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rail_tween.tween_property(_rail, "position:x", target, TvTheme.RAIL_TWEEN_SECONDS)


## Exactly one of the rail and the empty-library sentence is visible.
func _refresh_empty_state() -> void:
	if _stores != null:
		return
	var has_library := not _cards.is_empty()
	if _home_actions != null:
		_home_actions.visible = has_library
	if _summary_row != null:
		_summary_row.visible = has_library
	if not has_library and _hero_art != null:
		_apply_hero_texture(null)
		_hero_art_path = ""
	if _rail_row != null:
		_rail_row.visible = has_library
	if _title_block != null:
		_title_block.visible = not has_library


## Reconcile the library by stable ID, preserving existing cards and selection.
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
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TvTheme.card_art_box(TvTheme.SURFACE))
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 24)
	panel.add_child(dock)
	_dock_scroll = ScrollContainer.new()
	_dock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_dock_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dock_scroll.follow_focus = true
	_dock_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.add_child(_dock_scroll)
	var bar := HBoxContainer.new()
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 10)
	_dock_scroll.add_child(bar)
	for item in [["home", "Home", _show_home], ["store", "Stores", _open_stores],
		["browser", "Browser", _open_browser], ["folder", "Files", _open_files],
		["download", "Downloads", Downloads.open],
		["speaker", "Audio", _open_audio], ["gear", "Settings", _open_settings],
		["download", "Install", WindowsInstall.open], ["user", "Switch user", Profiles.open], ["power", "Power", Power.open]]:
		var button := ConsoleButton.new()
		button.text = item[1]
		button.glyph = item[0]
		button.navigation = true
		button.active = item[1] == "Home"
		button.set_meta("destination", item[1])
		button.pressed.connect(item[2])
		bar.add_child(button)
		_bar_buttons.append(button)
		if item[1] == "Audio":
			_audio_button = button
		if item[1] == "Settings":
			_gear_button = button
		if item[1] == "Power":
			_power_button = button
	_process_pill = ProcessPill.new()
	_process_pill.activated.connect(_open_process_menu)
	dock.add_child(_process_pill)
	if _process_pill.visible:
		_bar_buttons.append(_process_pill)
	_bar_buttons.append(_status_corner)
	Installed.apps_changed.connect(_on_pill_membership_changed)
	return panel


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
	var hints := HFlowContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("h_separation", TvTheme.HINT_GAP)
	hints.add_theme_constant_override("v_separation", 12)
	# Kept as a member because it is hidden when the rail is empty -- see
	# _refresh_empty_state. B stays: it is inert at the rail but the glyph is
	# how a person learns that, and the top bar's icons still take an A.
	_open_hint = TvTheme.hint("A", "Open")
	hints.add_child(_open_hint)
	# OPTIONS is the only route to removing an application on a machine with no
	# terminal, so it is advertised rather than left to be discovered. Hidden
	# with the A hint when the rail is empty -- there is nothing to have options
	# about -- which is why it is a member too.
	_options_hint = TvTheme.hint("OPTIONS", "Options")
	hints.add_child(_options_hint)
	hints.add_child(TvTheme.hint("PS", "System menu"))
	return hints


## end up disagreeing.
func _on_pill_membership_changed(_apps: Array) -> void:
	if _process_pill == null:
		return
	var present := _bar_buttons.has(_process_pill)
	if _process_pill.visible == present:
		return
	if _process_pill.visible:
		_bar_buttons.insert(_bar_buttons.size() - 1, _process_pill)
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
		card.focus_neighbor_top = card.get_path_to(_play_button)
		card.focus_neighbor_bottom = card.get_path_to(_play_button if not _play_button.disabled else _details_button)

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
		if card_count > 0:
			button.focus_neighbor_top = button.get_path_to(_play_button)
	_play_button.focus_neighbor_left = _play_button.get_path_to(_play_button)
	_play_button.focus_neighbor_right = _play_button.get_path_to(_details_button)
	_details_button.focus_neighbor_left = _details_button.get_path_to(_play_button)
	_details_button.focus_neighbor_right = _details_button.get_path_to(_details_button)
	for action in [_play_button, _details_button]:
		action.focus_neighbor_bottom = action.get_path_to(_selected_card) if is_instance_valid(_selected_card) else action.get_path_to(action)
		if card_count > 0:
			action.focus_neighbor_top = action.get_path_to(_cards[0])
	if _stores != null:
		var selector: Control = _stores._steam
		selector.focus_neighbor_bottom = selector.get_path_to(_bar_buttons[0] if _bar_row.visible else selector)
		for button in _bar_buttons:
			button.focus_neighbor_top = button.get_path_to(selector)
			button.focus_neighbor_bottom = button.get_path_to(button)
	if not _bar_row.visible:
		_status_corner.focus_neighbor_left = _status_corner.get_path_to(_status_corner)
		_status_corner.focus_neighbor_right = _status_corner.get_path_to(_status_corner)


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
	if not is_visible_in_tree():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	if is_instance_valid(_last_focused) and _last_focused.is_visible_in_tree() \
			and _last_focused.is_inside_tree():
		_last_focused.grab_focus()
		return
	if _stores != null:
		_stores.focus_store()
		return
	if not _cards.is_empty():
		_cards[0].grab_focus()
		return
	for button in _bar_buttons:
		if is_instance_valid(button) and button.is_visible_in_tree():
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
	# The inbox remains authoritative. Achievements earned while a game draws
	# also get a separate passive surface without taking the game input lease.
	if str(entry.get("app", "")) == "Achievements" and Launcher.is_busy() and Launcher.app_on_screen() and _overlay == null:
		_show_achievement_toast(entry)
		return
	if visible and not Launcher.is_busy() and not Info.is_open():
		_on_launch_blocked("%s: %s" % [str(entry.get("app", "")), str(entry.get("summary", ""))])


func _show_achievement_toast(entry: Dictionary) -> void:
	_dismiss_achievement_toast()
	_achievement_toast = AchievementToast.new()
	get_tree().root.add_child(_achievement_toast)
	_achievement_toast.expired.connect(_on_achievement_toast_expired.bind(_achievement_toast), CONNECT_ONE_SHOT)
	if not _achievement_toast.present(entry):
		_dismiss_achievement_toast()


func _dismiss_achievement_toast() -> void:
	if _achievement_toast == null:
		return
	var toast := _achievement_toast
	_achievement_toast = null
	toast.retire()


func _on_achievement_toast_expired(toast: AchievementToast) -> void:
	if _achievement_toast == toast:
		_dismiss_achievement_toast()
	else:
		toast.retire()


func _exit_tree() -> void:
	_dismiss_achievement_toast()
	if _hero_worker != null and _hero_worker.is_started():
		_hero_worker.wait_to_finish()


func _on_windows_changed() -> void:
	var state: Dictionary = WindowsInstall.snapshot
	var detail := WindowsInstall.message
	if str(state.get("operation", "")) in ["remove", "discard"] and str(state.get("status", "")) == "failed":
		detail = str(state.get("detail", "Could not remove the app. Try again."))
	if visible and not detail.is_empty() and detail != _windows_feedback:
		_windows_feedback = detail
		_on_launch_blocked(detail)


func _on_launch_finished(_entry: Dictionary) -> void:
	_dismiss_achievement_toast()
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
	if Settings.is_open() or WindowsInstall.is_open() or Files.is_open() or Browser.is_open() or Downloads.is_open():
		return
	_take_screen_back()
	if _stores != null:
		_stores.focus_store()


func _on_surface_opened() -> void:
	_hand_screen_over()


func _on_surface_closed() -> void:
	_take_screen_back()


func _on_guided_setup_return() -> void:
	if visible and not WindowsInstall.is_open() and not Files.is_open() and not Browser.is_open() and not Settings.is_open() and not Downloads.is_open():
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
		_surface_bar_visible = _bar_row.visible
	_bar_row.hide()
	_bar_return_to_steam = false
	_queue_layout()
	hide()
	# Hiding a Control stops it drawing and stops it receiving GUI input, but
	# _unhandled_input keeps arriving regardless. The covering screen is a later
	# sibling and so is called first, and it consumes the press -- but relying on
	# dispatch order for "B does not do two things at once" is the kind of
	# assumption that breaks silently when a node is reparented.
	set_process_unhandled_input(false)


func _take_screen_back() -> void:
	show()
	_bar_row.visible = _surface_bar_visible
	_wire_focus_neighbours()
	_queue_layout()
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
## PS/Home toggles the dock on Home and Stores, before embedded Steam can
## consume it. Running applications retain their existing system overlay.
func _input(event: InputEvent) -> void:
	if _volume_popup != null:
		return
	if TextInput.handle_input(event):
		return
	if _handle_home_button(event):
		return
	if SteamEmbed.handle_input(event):
		return
	_handle_bar_return(event)


func _handle_home_button(event: InputEvent) -> bool:
	if not InputMap.has_action("ui_shell_home"):
		return false
	if not event.is_action_pressed("ui_shell_home"):
		return false
	if _overlay != null:
		return false
	if Launcher.is_busy() and Launcher.can_close():
		get_viewport().set_input_as_handled()
		_open_overlay()
		return true
	if not _bar_input_live():
		return false
	get_viewport().set_input_as_handled()
	if SteamEmbed.owns_input():
		_bar_return_to_steam = true
		SteamEmbed.leave_pane()
		_reveal_bar(true)
	elif _bar_row.visible:
		_hide_bar()
	else:
		_reveal_bar(true)
	return true


## THE HOME SCREEN IS THREE ROWS: the bar, the selected entry's title block,
## and the card rail. Only two of them are focusable -- the title block is
## prose about whatever the cursor is on -- so DOWN FROM THE BAR GOES TO THE
## CARDS, past the middle row, and that is the whole of this function.
##
## Consume the dock's Down press so it lands on the selected card once.
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
	below.grab_focus()


## The dock belongs to Home and Stores; layered menus keep their own input.
func _bar_input_live() -> bool:
	if not visible or _bar_row == null:
		return false
	return _process_menu == null and _details == null and _card_menu == null and _volume_popup == null


## Remember content focus, then focus the current destination when requested.
## Alerts can reveal the dock without taking the user's focus.
func _reveal_bar(take_focus: bool) -> void:
	if not _bar_row.visible:
		_bar_focus_origin = get_viewport().gui_get_focus_owner()
		_bar_row.visible = true
		_wire_focus_neighbours()
		_queue_layout()
		ShellLog.info("bottom dock shown")
	if take_focus:
		_bar_revealed_for_alert = false
		for button in _bar_buttons:
			if button is ConsoleButton and button.active and button.is_visible_in_tree():
				button.grab_focus()
				return
		for button in _bar_buttons:
			if is_instance_valid(button) and button.is_visible_in_tree():
				button.grab_focus()
				return


## Return focus to the originating content or embedded Steam. PS/Home can
## always reveal the dock again, including when the library is empty.
func _hide_bar() -> void:
	_bar_revealed_for_alert = false
	var owner := get_viewport().gui_get_focus_owner()
	var restore_focus := owner == null or _bar_buttons.has(owner)
	_bar_row.hide()
	_wire_focus_neighbours()
	_queue_layout()
	if _bar_return_to_steam and _stores != null and SteamEmbed.snapshot.get("phase", "") == "ready":
		_bar_return_to_steam = false
		SteamEmbed.enter_pane()
	else:
		_bar_return_to_steam = false
		if restore_focus:
			if is_instance_valid(_bar_focus_origin) and _bar_focus_origin.is_visible_in_tree():
				_bar_focus_origin.grab_focus()
			elif _stores != null:
				_stores.focus_store()
			elif is_instance_valid(_selected_card):
				_selected_card.grab_focus()
	_bar_focus_origin = null
	ShellLog.info("bottom dock hidden")


func _open_overlay() -> void:
	# gamescope selects one external overlay. Retire the passive surface before
	# Home maps the interactive one, so it cannot cover the menu or keep a lease.
	_dismiss_achievement_toast()
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
	if entry.has("setup_id"):
		WindowsInstall.open_selection(entry)
		return
	_focus_game_actions()


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
			or Info.is_open() or Files.is_open() or Browser.is_open() or WindowsInstall.is_open() or Downloads.is_open() or Launcher.is_busy():
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
	if _volume_popup != null:
		return
	if _details != null or _card_menu != null or _stores != null:
		if event.is_action_pressed("ui_cancel") and _stores != null:
			get_viewport().set_input_as_handled()
			_show_home()
		return
	if event.is_action_pressed("ui_shell_options") and is_instance_valid(_selected_card):
		get_viewport().set_input_as_handled()
		_open_card_menu()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _bar_row.visible:
			_hide_bar()
		if is_instance_valid(_selected_card):
			_selected_card.grab_focus()


func _display_name() -> String:
	return str(Profiles.current().name)

func _on_profile_changed() -> void:
	_user_label.text = _display_name()
	_on_apps_changed(Installed.apps)

func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_layout_home.call_deferred()

func _layout_home() -> void:
	_layout_queued = false
	if _header == null:
		return
	var unit := TvTheme.layout_unit(size)
	var gutter := size.x * 0.05
	var width := size.x - 2 * gutter
	_header.position = Vector2(gutter, size.y * 0.04)
	_header.size = Vector2(width, maxf(6 * unit, _header.get_combined_minimum_size().y))
	var content_top := maxf(13 * unit, _header.position.y + _header.size.y + 2 * unit)
	_rail_row.position = Vector2(0, content_top)
	_rail_row.size = Vector2(size.x, 31.5 * unit)
	_rail_row.custom_minimum_size.y = 31.5 * unit
	_rail.add_theme_constant_override("separation", roundi(1.5 * unit))
	for card in _cards:
		card.layout_unit = unit
		card.set_selected_size(card == _selected_card)
	var summary_top := maxf(43.5 * unit, content_top + 31.5 * unit)
	_summary_row.position = Vector2(gutter, summary_top)
	_summary_row.size = Vector2(minf(width, 100 * unit), 25 * unit)
	_hero_text_scrim.texture = TvTheme.home_art_text_gradient((gutter + _summary_row.size.x) / size.x)
	var actions_top := maxf(71 * unit, summary_top + 27.5 * unit)
	actions_top = maxf(actions_top, summary_top + _summary_row.get_combined_minimum_size().y + 2 * unit)
	_home_actions.position = Vector2(gutter, actions_top)
	_home_actions.size = Vector2(width, 7 * unit)
	_title_block.position = Vector2(gutter, summary_top)
	_title_block.size = Vector2(width, 20 * unit)
	var dock_height := maxf(12 * unit, ConsoleButton.NAVIGATION_DIAMETER + 2 * unit + 16)
	var reserved_dock_height := dock_height if _bar_row.visible else 0.0
	var hint_height := maxf(4 * unit, 90 if width < 1100 else 36)
	_hint_row.position = Vector2(gutter, size.y - reserved_dock_height - hint_height - 2 * unit)
	_hint_row.size = Vector2(width, hint_height)
	_bar_row.position = Vector2(0, size.y - dock_height)
	_bar_row.size = Vector2(size.x, dock_height)
	var box := TvTheme.card_art_box(TvTheme.SURFACE)
	box.set_corner_radius_all(0)
	box.content_margin_left = gutter
	box.content_margin_right = gutter
	box.content_margin_top = unit
	box.content_margin_bottom = unit
	_bar_row.add_theme_stylebox_override("panel", box)
	if _stores != null:
		_stores.position = Vector2(gutter, content_top)
		_stores.size = Vector2(width, size.y - reserved_dock_height - content_top - 3 * unit)
	if is_instance_valid(_selected_card):
		_scroll_to_selected()

func _set_destination(destination: String) -> void:
	for button in _bar_buttons:
		if button is ConsoleButton:
			button.active = button.get_meta("destination", "") == destination

func _show_home() -> void:
	_bar_return_to_steam = false
	if _stores != null:
		remove_child(_stores)
		_stores.queue_free()
		_stores = null
	_refresh_empty_state()
	_home_actions.visible = not _cards.is_empty()
	_hint_row.show()
	_hero_art.show()
	_set_destination("Home")
	_wire_focus_neighbours()
	_hide_bar()
	if is_instance_valid(_selected_card):
		_selected_card.grab_focus()
	else:
		_ensure_focus()

func _open_stores() -> void:
	if _stores != null:
		_stores.focus_store()
		return
	_stores = StoresScreen.new()
	_stores.keep_shell_navigation = true
	add_child(_stores)
	_bar_return_to_steam = false
	for item in [_rail_row, _summary_row, _title_block, _home_actions, _hint_row, _hero_art]:
		item.hide()
	_set_destination("Stores")
	_layout_home()
	_hide_bar()
	_stores.focus_store()

func _open_browser() -> void:
	Browser.open()

func _open_files() -> void:
	Files.open()

func _open_settings() -> void:
	Settings.open()

func _open_audio() -> void:
	if _volume_popup != null:
		_close_volume_popup()
		return
	_volume_popup = VolumePopup.new()
	_volume_popup.anchor_control = _audio_button
	_volume_popup.closed.connect(_close_volume_popup.call_deferred, CONNECT_ONE_SHOT)
	add_child(_volume_popup)

func _close_volume_popup() -> void:
	if _volume_popup == null:
		return
	_volume_popup.dismiss()
	_volume_popup = null
	if _audio_button.is_visible_in_tree():
		_audio_button.grab_focus()

func _open_card_menu() -> void:
	if _card_menu != null or _details != null or not visible:
		return
	var entry: Dictionary = _selected_card.entry
	_card_menu = ListMenu.new()
	_card_menu.title_text = str(entry.get("title", ""))
	_card_menu.items = [{"id": "details", "label": "View details", "icon": "more"},
		{"id": "achievements", "label": "Achievements", "icon": "controller"},
		{"id": "metadata", "label": "Metadata", "icon": "download"}]
	if entry.has("setup_id") or str(entry.get("id", "")).begins_with("managed."):
		_card_menu.items.append({"id": "remove", "label": "Remove game", "icon": "trash"})
	_card_menu.chosen.connect(_on_card_choice.bind(entry))
	_card_menu.closed.connect(_close_card_menu)
	add_child(_card_menu)

func _close_card_menu() -> void:
	if _card_menu == null:
		return
	var menu := _card_menu
	_card_menu = null
	remove_child(menu)
	menu.queue_free()
	if is_instance_valid(_selected_card):
		_selected_card.grab_focus()

func _begin_hero_art() -> void:
	if _hero_worker != null:
		return
	var path := _hero_requested_path
	if path.is_empty():
		_apply_hero_texture(null)
		_hero_art_path = path
		return
	var cache_key := path + ":" + str(_hero_requested_stamp)
	if _hero_art_cache.has(cache_key):
		_apply_hero_texture(_hero_art_cache[cache_key])
		_hero_art_path = path
		_hero_art_stamp = _hero_requested_stamp
		return
	_hero_loading_path = path
	_hero_loading_stamp = _hero_requested_stamp
	_hero_worker = Thread.new()
	var error := _hero_worker.start(_decode_hero.bind(path))
	if error != OK:
		_hero_worker = null
		return
	_hero_poll.start()

static func _decode_hero(path: String) -> Image:
	var image := Icons.load_icon_image(path)
	if image != null:
		var ratio := minf(1.0, minf(1920.0 / image.get_width(), 1080.0 / image.get_height()))
		if ratio < 1.0:
			image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)))
	return image

func _finish_hero_art() -> void:
	if _hero_worker == null or _hero_worker.is_alive():
		return
	var image: Image = _hero_worker.wait_to_finish()
	_hero_worker = null
	_hero_poll.stop()
	if _hero_loading_path == _hero_requested_path and _hero_loading_stamp == _hero_requested_stamp:
		_hero_art_path = _hero_loading_path
		_hero_art_stamp = _hero_loading_stamp
		_apply_hero_texture(null)
		if image != null:
			if _hero_art_cache.size() >= 4:
				_hero_art_cache.erase(_hero_art_cache.keys()[0])
			var cache_key := _hero_loading_path + ":" + str(_hero_loading_stamp)
			_hero_art_cache[cache_key] = ImageTexture.create_from_image(image)
			_apply_hero_texture(_hero_art_cache[cache_key])
	else:
		_hero_art_timer.start(TvTheme.HERO_ART_DEBOUNCE_SECONDS)

func _apply_hero_texture(texture: Texture2D) -> void:
	_hero_art.texture = texture
	_hero_text_scrim.visible = texture != null
	_hero_header_scrim.visible = texture != null

func _on_card_choice(id: String, entry: Dictionary) -> void:
	_close_card_menu()
	match id:
		"details":
			_open_details(entry)
		"remove":
			WindowsInstall.confirm_remove(entry)
		"achievements", "metadata":
			_details = AchievementsPage.new() if id == "achievements" else MetadataPage.new()
			_details.entry = entry
			_details.closed.connect(func(): _close_details.call_deferred(), CONNECT_ONE_SHOT)
			_hand_screen_over()
			get_tree().root.add_child(_details)
