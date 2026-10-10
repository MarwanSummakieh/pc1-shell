extends "res://src/console_button.gd"

## Places use the shared control states, with location independent of focus.
var _title := ""
var _value := ""
var _icon := ""
var _marker: ColorRect
var _value_label: Label

signal activated()

func setup(caption: String, value: String, icon_name: String) -> void:
	_title = caption
	_value = value
	_icon = icon_name

func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(0, 88 if not _value.is_empty() else 68)
	pressed.connect(func(): activated.emit())
	tooltip_text = _title
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 12)
	add_child(pad)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	pad.add_child(row)
	row.add_child(Icons.label(_icon, 30, TvTheme.TEXT_SECONDARY))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	for content in [[_title, TvTheme.SIZE_BODY, TvTheme.TEXT_PRIMARY], [_value, TvTheme.SIZE_SUPPLEMENTAL, TvTheme.TEXT_SECONDARY]]:
		if str(content[0]).is_empty():
			continue
		var label := Label.new()
		label.text = content[0]
		label.add_theme_font_size_override("font_size", content[1])
		label.add_theme_color_override("font_color", content[2])
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
		if content[1] == TvTheme.SIZE_SUPPLEMENTAL:
			_value_label = label
	_marker = ColorRect.new()
	_marker.color = TvTheme.PRIMARY
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_marker.offset_top = 16
	_marker.offset_bottom = -16
	_marker.offset_right = 3
	add_child(_marker)
	_refresh_style()


func set_value(value: String) -> void:
	_value = value
	if is_instance_valid(_value_label):
		_value_label.text = value

func _refresh_style() -> void:
	super._refresh_style()
	var box := get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	box.bg_color = TvTheme.SURFACE_FOCUS if active else Color.TRANSPARENT
	add_theme_stylebox_override("normal", box)
	if is_instance_valid(_marker):
		_marker.visible = active
