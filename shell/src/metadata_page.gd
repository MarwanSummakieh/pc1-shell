extends Control

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")

var entry: Dictionary = {}
var _heading: Label
var _source: Label
var _message: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array = []
var _signature := ""
var _request_message := ""
var _pending_until := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_X)
	for edge in ["top", "bottom"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_Y)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	safe.add_child(column)
	_heading = _label(column, TvTheme.SIZE_HERO_TITLE)
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_source = _label(column, TvTheme.SIZE_BODY)
	_message = _label(column, TvTheme.SIZE_BODY)
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
	hints.add_child(TvTheme.hint("↑ / ↓", "Choose"))
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)
	Metadata.changed.connect(_metadata_changed)
	_refresh()


func _label(parent: Node, size_value: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _row(key: String, title: String, detail: String, action: Callable, enabled: bool = true) -> void:
	var row := ActionRow.new()
	row.setup(title, detail)
	row.set_meta("metadata_key", key)
	row.activated.connect(action)
	row.focus_entered.connect(func(): _ensure_visible.call_deferred(row))
	row.disabled = not enabled
	_list.add_child(row)
	row._name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row._name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.append(row)


func _ensure_visible(row: Control) -> void:
	if is_instance_valid(row) and _scroll.is_ancestor_of(row):
		_scroll.ensure_control_visible(row)


func _metadata_changed() -> void:
	var record: Dictionary = Metadata.games.get(str(entry.get("id", "")), {})
	if JSON.stringify(record) != _signature:
		_request_message = ""
		_pending_until = 0
	_refresh()


func _refresh() -> void:
	var fresh: Dictionary = Metadata.enrich(entry)
	var record: Dictionary = fresh.get("metadata", {})
	_signature = JSON.stringify(record)
	var owner := get_viewport().gui_get_focus_owner()
	var focused := str(owner.get_meta("metadata_key", "refresh")) if owner != null else "refresh"
	var scroll_value := _scroll.scroll_vertical
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_heading.text = str(fresh.get("title", "Game")) + " · Metadata"
	var provider := str(record.get("provider", "Steam Store"))
	_source.text = "Source: " + provider
	if not str(record.get("provider_id", "")).is_empty():
		_source.text += " · App " + str(record.provider_id)
	var loading := str(record.get("status", "")) == "loading"
	var values: Variant = record.get("candidates", [])
	var candidates: Array = values if values is Array else []
	_message.text = str(record.get("error", ""))
	if loading:
		_message.text = "Downloading metadata…"
	elif not candidates.is_empty():
		_message.text = "Choose the game that matches this installation."
	elif str(record.get("status", "")) == "unmatched":
		_message.text = "No matching game was found. Refresh to try again."
	if not _request_message.is_empty():
		_message.text = _request_message
	_message.visible = not _message.text.is_empty()
	_row("refresh", "Refresh from " + provider, "Download current information and missing artwork.", _request.bind("refresh", {}), not loading)
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		var appid := str(candidate.get("provider_id", ""))
		if not _valid_provider_id(appid):
			continue
		_row("match:" + appid, "Use " + str(candidate.get("title", "Game")), "Steam Store · App " + appid, _request.bind("match", {"provider_id": appid}), not loading)
	_row("back", "Back", "Return to game details.", func(): closed.emit())
	var enabled: Array = _rows.filter(func(row): return not row.disabled)
	TvTheme.wire_column(enabled)
	if visible and not enabled.is_empty():
		var target: Control = enabled[0]
		for row in enabled:
			if str(row.get_meta("metadata_key")) == focused:
				target = row
		target.grab_focus()
		_scroll.set_deferred("scroll_vertical", scroll_value)


func _valid_provider_id(value: String) -> bool:
	if value.is_empty() or value.length() > 10:
		return false
	for code in value.to_ascii_buffer():
		if code < 48 or code > 57:
			return false
	return true


func _request(action: String, extra: Dictionary) -> void:
	if Time.get_ticks_msec() < _pending_until:
		return
	if Metadata.request(action, str(entry.get("id", "")), extra):
		_pending_until = Time.get_ticks_msec() + 5000
		_request_message = "Refresh requested. Waiting for the metadata service." if action == "refresh" else "Match requested. Waiting for the metadata service."
	else:
		_request_message = "Could not save the request. Try again."
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
