extends Control

signal chosen(id: String)
signal closed()

const Chrome = preload("res://src/browser_chrome.gd")
const TvTheme = preload("res://src/tv_theme.gd")
var title_text := ""
var items: Array = []
var note_text := ""
var _information: RichTextLabel
var _panel: PanelContainer
var _rows: Array[Control] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = Color(Chrome.WINDOW, 0.5)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Chrome.box(Chrome.WINDOW, Chrome.LINE, 1))
	add_child(_panel)
	var pad := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: pad.add_theme_constant_override("margin_" + edge, 16)
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	pad.add_child(column)
	var title := Chrome.label(title_text, 28)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	column.add_child(title)
	if not note_text.is_empty():
		_information = RichTextLabel.new()
		_information.text = note_text
		_information.custom_minimum_size.y = 120
		_information.focus_mode = Control.FOCUS_ALL
		_information.add_theme_font_size_override("normal_font_size", 22)
		_information.add_theme_color_override("default_color", TvTheme.TEXT_SECONDARY)
		_information.add_theme_stylebox_override("focus", Chrome.box(Color.TRANSPARENT, Chrome.ACCENT, 2))
		column.add_child(_information)
		_rows.append(_information)
		_information.resized.connect(_fit_information)
		_fit_information.call_deferred()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for item: Dictionary in items:
		var button := Button.new()
		button.text = str(item.label)
		button.custom_minimum_size.y = 44
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 22)
		button.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
		button.add_theme_stylebox_override("normal", Chrome.box(Color.TRANSPARENT))
		button.add_theme_stylebox_override("hover", Chrome.box(TvTheme.SURFACE_FOCUS))
		button.add_theme_stylebox_override("pressed", Chrome.box(TvTheme.SURFACE_PRESSED))
		button.add_theme_stylebox_override("focus", Chrome.box(Color.TRANSPARENT, Chrome.ACCENT, 3))
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(item.label)
		button.pressed.connect(func():
			chosen.emit(str(item.id))
			closed.emit())
		list.add_child(button)
		_rows.append(button)
	var hints := HFlowContainer.new()
	hints.add_theme_constant_override("h_separation", 16)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)
	for index in _rows.size():
		_rows[index].focus_neighbor_top = _rows[index].get_path_to(_rows[(index - 1 + _rows.size()) % _rows.size()])
		_rows[index].focus_neighbor_bottom = _rows[index].get_path_to(_rows[(index + 1) % _rows.size()])
	if not items.is_empty(): _rows[1 if _information != null else 0].grab_focus()
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	_panel.position = Vector2(size.x - minf(560, size.x - 32) - 16, 16)
	_panel.size = Vector2(minf(560, size.x - 32), size.y - 32)

func _fit_information() -> void:
	if _information != null:
		_information.custom_minimum_size.y = clampf(_information.get_content_height() + 8, 44, minf(220, size.y * 0.35))

func _input(event: InputEvent) -> void:
	if _information == null or not _information.has_focus(): return
	var bar := _information.get_v_scroll_bar()
	var direction := 1 if event.is_action_pressed("ui_down") else (-1 if event.is_action_pressed("ui_up") else 0)
	if direction != 0 and ((direction > 0 and bar.value < bar.max_value - bar.page) or (direction < 0 and bar.value > bar.min_value)):
		bar.value += direction * 32
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
