extends Control

## The native Steam child is clipped by its helper-owned host, aligned to _pane.
const TvTheme = preload("res://src/tv_theme.gd")
const ConsoleButton = preload("res://src/console_button.gd")
const Icons = preload("res://src/icons.gd")
var _steam: Button
var _fullscreen: Button
var _window: Panel
var _message: Label
var _pane: Control
var _heading: Label
var _status_row: HBoxContainer
var _requested := false
## The approved shell keeps its navigation visible when embedding is unavailable.
var keep_shell_navigation := true
var _store_art: Control
var _store_name: Label
var _title: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	_title = title
	title.text = "Stores"
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	add_child(title)
	_steam = ConsoleButton.new()
	_steam.tooltip_text = "Steam"
	_steam.pressed.connect(_open_steam)
	add_child(_steam)
	_fullscreen = ConsoleButton.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_fullscreen.pressed.connect(_open_fullscreen)
	_fullscreen.hide()
	add_child(_fullscreen)
	_build_store_art()
	_window = Panel.new()
	_window.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	add_child(_window)
	_heading = Label.new()
	_heading.text = "Steam"
	_heading.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_window.add_child(_heading)
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 24)
	_status_row.add_child(TvTheme.hint("A", "Enter Steam"))
	_status_row.add_child(TvTheme.hint("SHARE", "Steam menu"))
	_status_row.add_child(TvTheme.hint("PS", "System menu"))
	_window.add_child(_status_row)
	_pane = Control.new()
	_pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_pane)
	_message = Label.new()
	_message.text = "Open Steam to browse the store."
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_message.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_window.add_child(_message)
	SteamEmbed.changed.connect(_refresh)
	SteamEmbed.navigation_requested.connect(focus_store)
	for direction in ["left", "right", "top"]:
		_steam.set("focus_neighbor_" + direction, _steam.get_path_to(_steam))
	resized.connect(_layout)
	_layout()
	_window.hide()
	if SteamEmbed.supported() or not keep_shell_navigation:
		_open_steam.call_deferred()

func _layout() -> void:
	if _steam == null or size.x <= 0 or size.y <= 0:
		return
	var unit := TvTheme.layout_unit(get_viewport_rect().size)
	var tile := unit * 15.5
	_steam.position = Vector2(0, maxf(8 * unit, _title.get_combined_minimum_size().y + 2 * unit))
	_steam.size = Vector2(tile, tile)
	_fullscreen.position = Vector2(0, 32 * unit)
	_fullscreen.size = Vector2(tile, 7 * unit)
	if _store_art is Label:
		var mark_size := _store_art.get_combined_minimum_size()
		_store_art.size = mark_size
		_store_art.scale = Vector2.ONE * tile * 0.84 / maxf(mark_size.x, mark_size.y)
		_store_art.position = (Vector2.ONE * tile - mark_size * _store_art.scale) * 0.5
	else:
		_store_art.position = Vector2.ONE * tile * 0.08
		_store_art.size = Vector2.ONE * tile * 0.84
	_store_name.position = Vector2(0, tile + unit)
	var caption_height := maxf(4 * unit, _store_name.get_combined_minimum_size().y)
	_store_name.size = Vector2(tile, caption_height)
	var viewport := get_viewport_rect().size
	var narrow := viewport.x < viewport.y * 1.15
	var stacked_top := _steam.position.y + tile + unit + caption_height + 3 * unit
	_window.position = Vector2(0, stacked_top) if narrow else Vector2(tile + 3 * unit, 0)
	_window.size = Vector2(maxf(0, size.x - _window.position.x), size.y)
	_window.size.y = maxf(0, size.y - _window.position.y)
	_heading.position = Vector2(2.2 * unit, 1.6 * unit)
	_status_row.position = Vector2(2.2 * unit, 7 * unit)
	_status_row.visible = _window.size.x > 60 * unit and SteamEmbed.supported()
	_pane.position = Vector2(unit, 12 * unit)
	_pane.size = Vector2(maxf(0, _window.size.x - 2 * unit), maxf(0, _window.size.y - 13 * unit))
	_message.position = Vector2(2.2 * unit, 12 * unit)
	_message.size = Vector2(maxf(0, _window.size.x - 4.4 * unit), maxf(0, _window.size.y - 14 * unit))

func _open_steam() -> void:
	if not SteamEmbed.supported() and not keep_shell_navigation:
		_open_fullscreen()
		return
	_window.show()
	if not _requested:
		_requested = true
		SteamEmbed.show_pane(_pane)
		_refresh()
		return
	if SteamEmbed.supported():
		SteamEmbed.enter_pane()

func _refresh() -> void:
	var state: Dictionary = SteamEmbed.snapshot
	_fullscreen.visible = (SteamEmbed.supported() or not keep_shell_navigation) and str(state.get("phase", "")) in ["error", "unsupported"]
	match str(state.get("phase", "loading")):
		"ready":
			_message.hide()
		"error", "unsupported":
			_message.text = str(state.get("detail", "Steam could not open. Try again."))
			_message.show()
		_:
			_message.text = "Opening Steam…"
			_message.show()

func _open_fullscreen() -> void:
	if keep_shell_navigation and not SteamEmbed.supported():
		return
	_requested = false
	SteamEmbed.launch_fullscreen()

func focus_store() -> void:
	_steam.grab_focus()

func _build_store_art() -> void:
	# Use the installed client's own logo when available; retain an honest fallback.
	for app in Installed.apps:
		if str(app.get("id", "")) != "steam":
			continue
		var image := Icons.load_icon_image(str(app.get("icon", "")))
		if image != null:
			var texture := TextureRect.new()
			texture.texture = ImageTexture.create_from_image(image)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_store_art = texture
			break
	if _store_art == null:
		_store_art = Icons.label("steam", 112, TvTheme.TEXT_PRIMARY)
	_store_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steam.add_child(_store_art)
	_store_name = Label.new()
	_store_name.text = "Steam"
	_store_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_store_name.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_store_name.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_store_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steam.add_child(_store_name)

func _exit_tree() -> void:
	SteamEmbed.hide_pane()
