extends Control

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

var entry: Dictionary = {}
var _service: Node
var _heading: Label
var _summary: Label
var _message: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array = []
var _filter := 0
var _signature := ""


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
	_heading = _label(column, str(entry.get("title", "Game")) + " · Achievements", TvTheme.SIZE_HERO_TITLE)
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summary = _label(column, "", TvTheme.SIZE_BODY)
	_message = _label(column, "", TvTheme.SIZE_BODY)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 20)
	_scroll.add_child(_list)
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("↑ / ↓", "Browse"))
	hints.add_child(TvTheme.hint("L1 / R1", "Filter"))
	hints.add_child(TvTheme.hint("Y", "Refresh"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)
	_service = get_node_or_null("/root/Achievements")
	if _service != null:
		_service.changed.connect(_refresh)
	_refresh()


func _label(parent: Node, text: String, size_value: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _achievement(row: Dictionary) -> void:
	var button := Button.new()
	button.custom_minimum_size.y = 200
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", TvTheme.card_idle_box())
	button.add_theme_stylebox_override("hover", TvTheme.card_idle_box())
	button.add_theme_stylebox_override("pressed", TvTheme.row_pressed_box())
	button.add_theme_stylebox_override("focus", TvTheme.card_focus_ring())
	button.set_meta("achievement_id", str(row.get("id", "")))
	button.focus_entered.connect(func(): _ensure_visible.call_deferred(button))
	_list.add_child(button)
	_rows.append(button)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	button.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 24)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(line)
	var image := Icons.load_icon_image(str(row.get("icon", "")))
	if image != null:
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(image)
		picture.custom_minimum_size = Vector2(96, 96)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(picture)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 6)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text)
	var unlocked := bool(row.get("unlocked", false))
	var title := _label(text, str(row.get("name", "Achievement")), TvTheme.SIZE_BODY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var description := _label(text, str(row.get("description", "")), TvTheme.SIZE_SUPPLEMENTAL)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 2
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var status := "Unlocked" if unlocked else "Locked"
	var stamp := int(row.get("unlock_time", 0))
	if unlocked and stamp > 0:
		status += " · " + Time.get_datetime_string_from_unix_time(stamp).replace("T", " ") + " UTC"
	var maximum := float(row.get("progress_max", 0.0))
	var current := float(row.get("progress_current", 0.0))
	if maximum > 0.0:
		status += " · %s / %s" % [str(current), str(maximum)]
		var progress := ProgressBar.new()
		progress.custom_minimum_size.y = 12
		progress.show_percentage = false
		progress.max_value = maximum
		progress.value = maximum if unlocked else current
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(progress)
		button.custom_minimum_size.y = 220
	_label(text, status, TvTheme.SIZE_SUPPLEMENTAL)


func _ensure_visible(row: Control) -> void:
	if is_instance_valid(row) and _scroll.is_ancestor_of(row):
		_scroll.ensure_control_visible(row)


func _refresh() -> void:
	var record: Dictionary = _service.game(str(entry.get("id", ""))) if _service != null else {}
	var signature := JSON.stringify(record) + str(_filter)
	if signature == _signature:
		return
	_signature = signature
	var focused := get_viewport().gui_get_focus_owner()
	var focus_id := str(focused.get_meta("achievement_id", "")) if focused != null else ""
	var scroll_value := _scroll.scroll_vertical
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	var total: Variant = record.get("total_count")
	var count := int(record.get("unlocked_count", 0))
	var counts := "%d / %d unlocked" % [count, int(total)] if total != null else "%d unlocked · total unavailable" % count
	var provider := str(record.get("provider", "Unavailable"))
	_summary.text = "%s · %s · %s" % [counts, provider, ["All", "Locked", "Unlocked"][_filter]]
	_message.text = str(record.get("message", "Achievements will appear when the service has synchronized this game."))
	_message.visible = not _message.text.is_empty()
	var data: Variant = record.get("achievements", [])
	if data is Array:
		for row in data:
			if not row is Dictionary:
				continue
			if _filter == 1 and row.get("unlocked", false) or _filter == 2 and not row.get("unlocked", false):
				continue
			_achievement(row)
	if _rows.is_empty():
		_label(_list, "No achievements in this view." if not record.is_empty() else "Waiting for achievement data…", TvTheme.SIZE_BODY)
	else:
		TvTheme.wire_column(_rows)
		var restore: Control = _rows[0]
		for row in _rows:
			if row.get_meta("achievement_id") == focus_id:
				restore = row
		if visible:
			restore.grab_focus()
		_scroll.set_deferred("scroll_vertical", scroll_value)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
	elif event.is_action_pressed("ui_shell_l1") or event.is_action_pressed("ui_shell_r1"):
		get_viewport().set_input_as_handled()
		_filter = posmod(_filter + (-1 if event.is_action_pressed("ui_shell_l1") else 1), 3)
		_refresh()
	elif event.is_action_pressed("ui_shell_y"):
		get_viewport().set_input_as_handled()
		if _service != null:
			_service.request_refresh(str(entry.get("id", "")))
