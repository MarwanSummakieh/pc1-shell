extends Window

signal command_requested(command: String)
const Chrome = preload("res://src/browser_chrome.gd")
const TvTheme = preload("res://src/tv_theme.gd")
const HEIGHT := 104

static func panel_rect(screen: Rect2i) -> Rect2i:
	var width := mini(screen.size.x, clampi(roundi(screen.size.x * 0.55), 480, 760))
	return Rect2i(screen.end.x - width, screen.position.y, width, screen.size.y)

func _init() -> void:

	visible = false
	force_native = true
	borderless = true
	unresizable = true
	unfocusable = true
	always_on_top = true
	transient = false
	title = "Extensions"

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Chrome.WINDOW
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 12
	column.offset_top = 4
	column.offset_right = -12
	column.offset_bottom = -4
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var caption := Chrome.label("Extensions", 26)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(caption)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for entry in [["Open extension", "installed"], ["Close", "close"], ["Back", "back"], ["Store", "store"], ["Manage", "manage"], ["Type", "type"]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 44
		if entry[1] not in ["installed", "close"]: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 22)
		button.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
		button.add_theme_stylebox_override("normal", Chrome.box(Chrome.CONTENT))
		button.add_theme_stylebox_override("hover", Chrome.box(TvTheme.SURFACE_FOCUS))
		button.add_theme_stylebox_override("pressed", Chrome.box(TvTheme.SURFACE_PRESSED))
		button.pressed.connect(func(): command_requested.emit(entry[1]))
		(heading if entry[1] in ["installed", "close"] else row).add_child(button)

func show_toolbar() -> void:
	var panel := panel_rect(Rect2i(DisplayServer.screen_get_position(), DisplayServer.screen_get_size()))
	var desired := Vector2i(panel.size.x, HEIGHT)
	position = panel.position
	var external := OS.get_environment("MARWANOS_COMPOSITOR") != "x11"
	size = Vector2i.ONE if external else desired
	show()
	if external:
		var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window_id())
		var output: Array = []
		if handle <= 0 or OS.execute("/usr/bin/timeout", ["1", "xprop", "-id", str(handle), "-f", "GAMESCOPE_EXTERNAL_OVERLAY", "32c", "-set", "GAMESCOPE_EXTERNAL_OVERLAY", "1"], output, true) != 0:
			hide()
			return
	size = desired
	position = panel.position
