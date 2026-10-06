extends Control

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")
const ActionRow = preload("res://src/action_row.gd")
const Keyboard = preload("res://src/keyboard.gd")

var entry: Dictionary = {}
var _list: VBoxContainer
var _scroll: ScrollContainer
var _rows: Array = []
var _keyboard: Control
var _signature := ""
var _local_error := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_X)
	for edge in ["top", "bottom"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_Y)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	_scroll.add_child(_list)
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)
	Metadata.changed.connect(_refresh)
	_refresh()


func _label(parent: Node, text: String, font_size: int = TvTheme.SIZE_BODY) -> void:
	if text.is_empty():
		return
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)


func _picture(parent: Node, path: String, dimensions: Vector2) -> void:
	var image := Icons.load_icon_image(path)
	if image == null:
		return
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = dimensions
	parent.add_child(rect)


func _row(key: String, title: String, callback: Callable) -> void:
	var row := ActionRow.new()
	row.setup(title, "")
	row.set_meta("details_key", key)
	row.activated.connect(callback)
	row.focus_entered.connect(func(): _scroll.ensure_control_visible.call_deferred(row))
	_list.add_child(row)
	_rows.append(row)


func _refresh() -> void:
	var fresh := Metadata.enrich(entry)
	var metadata: Dictionary = fresh.get("metadata", {})
	var signature := JSON.stringify([fresh, _local_error])
	if signature == _signature or _keyboard != null:
		return
	_signature = signature
	var focus := get_viewport().gui_get_focus_owner()
	var focus_key := str(focus.get_meta("details_key", "play")) if focus != null else "play"
	var scroll_value := _scroll.scroll_vertical
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_label(_list, str(fresh.get("title", "Game")), TvTheme.SIZE_WORDMARK)
	var overview := HBoxContainer.new()
	overview.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	_list.add_child(overview)
	_picture(overview, str(fresh.get("cover", fresh.get("icon", ""))), Vector2(240, 360))
	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(facts)
	var source := str(entry.get("id", "")).get_slice(".", 0)
	var source_label := str({"managed": "Windows", "win": "Windows", "steam": "Steam", "epic": "Epic", "gog": "GOG", "rom": "Emulated"}.get(source, "Application"))
	_label(facts, "Source: " + source_label)
	_label(facts, str(metadata.get("description", "")))
	for pair in [["release_date", "Released"], ["genres", "Genres"], ["developers", "Developer"], ["publishers", "Publisher"], ["platforms", "Platforms"]]:
		var value: Variant = metadata.get(pair[0], "")
		var text := ", ".join(value) if value is Array else str(value)
		if not text.is_empty():
			_label(facts, pair[1] + ": " + text)
	var assets: Dictionary = metadata.get("assets", {})
	var media := HBoxContainer.new()
	media.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	_list.add_child(media)
	_picture(media, str(assets.get("background", {}).get("path", "")), Vector2(620, 220))
	_picture(media, str(assets.get("logo", {}).get("path", "")), Vector2(280, 140))
	if not str(metadata.get("provider", "")).is_empty():
		_label(_list, "Metadata: %s · %s" % [metadata.provider, metadata.get("provider_id", "")], TvTheme.SIZE_SUPPLEMENTAL)
	var status := str(metadata.get("status", ""))
	var message := str(metadata.get("error", ""))
	if status in ["", "loading"]:
		message = "Downloading metadata…" if status == "loading" else "Metadata will download automatically when the service is available."
	elif status == "needs-match":
		message = "Choose the matching game or search for another title."
	elif status == "unmatched":
		message = "No automatic match. Search for the game title."
	_label(_list, _local_error if not _local_error.is_empty() else message)
	_label(_list, str(metadata.get("search_error", "")))
	_row("play", "Play", _play)
	_row("refresh", "Refresh metadata", func(): _request("refresh"))
	_row("search", "Change metadata match", func(): _edit("search"))
	_row("title", "Edit title", func(): _edit("title"))
	for candidate in metadata.get("candidates", []):
		var id := str(candidate.get("provider_id", ""))
		_row("match:" + id, "%s · Steam %s" % [candidate.get("title", ""), id], _choose.bind(id))
	if str(entry.get("id", "")).begins_with("managed."):
		_row("remove", "Remove application", _remove)
	TvTheme.wire_column(_rows)
	if visible:
		var restore: Control = _rows[0]
		for row in _rows:
			if row.get_meta("details_key") == focus_key:
				restore = row
		restore.grab_focus()
		_scroll.set_deferred("scroll_vertical", scroll_value)


func _request(action: String, extra: Dictionary = {}) -> void:
	_local_error = "" if Metadata.request(action, str(entry.get("id", "")), extra) else "Could not save the metadata request. Try again."
	_refresh()


func _choose(provider_id: String) -> void:
	_request("match", {"provider_id": provider_id})


func _edit(action: String) -> void:
	if _keyboard != null:
		return
	_keyboard = Keyboard.new()
	_keyboard.title_text = "Search game title" if action == "search" else "Game title"
	_keyboard.masked = false
	_keyboard.initial_text = str(Metadata.enrich(entry).get("title", ""))
	_keyboard.submitted.connect(func(text: String):
		_request(action, {"query": text} if action == "search" else {"title": text})
		_close_keyboard.call_deferred())
	_keyboard.cancelled.connect(func(): _close_keyboard.call_deferred())
	add_child(_keyboard)


func _close_keyboard() -> void:
	remove_child(_keyboard)
	_keyboard.queue_free()
	_keyboard = null
	_signature = ""
	_refresh()


func _play() -> void:
	closed.emit()
	Launcher.launch(entry)


func _remove() -> void:
	closed.emit()
	WindowsInstall.confirm_remove.call_deferred(entry)


func _unhandled_input(event: InputEvent) -> void:
	if _keyboard == null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
