extends Control

signal closed()
signal chosen(id: String)

const TvTheme = preload("res://src/tv_theme.gd")
const AppMenuRow = preload("res://src/app_menu_row.gd")
const EdgePanel = preload("res://src/edge_panel.gd")
var title_text := ""
var items: Array = []
var note_text := ""
var _rows: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.color = Color(TvTheme.BACKGROUND, 0.45)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var panel := EdgePanel.new()
	add_child(panel)
	var pad := MarginContainer.new()
	for edge in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + edge, 32)
	for edge in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_Y)
	panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	pad.add_child(column)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var item_box := VBoxContainer.new()
	item_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_box.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	scroll.add_child(item_box)
	for item in items:
		var row := AppMenuRow.new()
		row.setup_item(str(item["id"]), str(item["label"]), str(item.get("icon", "")))
		row.chosen.connect(_on_item_chosen)
		item_box.add_child(row)
		row._value.hide()
		row._name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row._name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if str(item["id"]) in ["remove", "trash", "delete", "emptytrash", "emptytrashconfirmed"]:
			row._name.add_theme_color_override("font_color", TvTheme.TEXT_DESTRUCTIVE)
		_rows.append(row)
	if not note_text.is_empty():
		var note := Label.new()
		note.text = note_text
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
		note.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		column.add_child(note)
	var hints := HFlowContainer.new()
	hints.add_theme_constant_override("h_separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)
	TvTheme.wire_column(_rows)
	if not _rows.is_empty():
		_rows[0].grab_focus()

func _on_item_chosen(id: String) -> void:
	chosen.emit(id)
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
