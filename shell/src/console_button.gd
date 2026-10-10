extends Button

## Shared action and navigation control. The label determines width, never the screen.
const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")
const NAVIGATION_DIAMETER := 80

var primary := false
var glyph := ""
var navigation := false
var pill := false
var icon_only := false
var active := false:
	set(value):
		active = value
		if is_inside_tree():
			_refresh_style()

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	add_theme_color_override("font_color", TvTheme.TEXT_ON_PRIMARY if primary else TvTheme.TEXT_PRIMARY)
	add_theme_color_override("font_hover_color", TvTheme.TEXT_ON_PRIMARY if primary else TvTheme.TEXT_PRIMARY)
	add_theme_color_override("font_focus_color", TvTheme.TEXT_ON_PRIMARY if primary else TvTheme.TEXT_PRIMARY)
	add_theme_color_override("font_pressed_color", TvTheme.TEXT_PRIMARY)
	add_theme_color_override("font_disabled_color", TvTheme.TEXT_SECONDARY)
	custom_minimum_size.y = 64
	if pill:
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if navigation or icon_only:
		var caption := text
		text = ""
		var diameter := NAVIGATION_DIAMETER if navigation else 64
		custom_minimum_size = Vector2(diameter, diameter)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var column := VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(column)
		if not glyph.is_empty():
			var mark := Icons.label(glyph, 36 if navigation else 32, TvTheme.TEXT_PRIMARY)
			mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(mark)
		tooltip_text = caption
		accessibility_name = caption
	_refresh_style()

func _refresh_style() -> void:
	var round_icon := navigation or icon_only
	var radius := 999 if round_icon or pill else 8
	var ring := TvTheme.card_focus_ring(radius)
	ring.corner_detail = 16
	add_theme_stylebox_override("focus", ring)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(radius)
		box.corner_detail = 16
		box.content_margin_left = 0 if round_icon else 28
		box.content_margin_right = 0 if round_icon else 28
		box.content_margin_top = 0 if round_icon else 12
		box.content_margin_bottom = 0 if round_icon else 12
		if icon_only:
			box.set_border_width_all(2)
			box.border_color = TvTheme.TEXT_SECONDARY
		box.bg_color = TvTheme.PRIMARY if primary else TvTheme.SURFACE
		if navigation and not active:
			box.bg_color = Color.TRANSPARENT
		if state == "hover":
			box.bg_color = TvTheme.FOCUS_RING if primary else TvTheme.SURFACE_FOCUS
		if navigation and active:
			box.bg_color = TvTheme.SURFACE_FOCUS
		if state == "pressed":
			box.bg_color = TvTheme.SURFACE_PRESSED
		if state == "disabled":
			box.bg_color = TvTheme.SURFACE
		add_theme_stylebox_override(state, box)
