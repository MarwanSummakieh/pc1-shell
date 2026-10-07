extends Window

## A passive surface, separate from the shell's interactive Home overlay.
## gamescope 3.16.23 composites external overlays but excludes them from the
## normal focus candidates. Never acquire the main window's overlay/input lease.
signal expired()
signal dismissed()

const TvTheme = preload("res://src/tv_theme.gd")
const OVERLAY_PROPERTY := "GAMESCOPE_EXTERNAL_OVERLAY"
const LIFETIME_SECONDS := 7.0

var _timer: Timer
var _heading: Label
var _body: Label
var _panel: PanelContainer
var _native_handle := 0
var _map_frame := -1
var _dismissing := false
var _dismissed := false
var _retiring := false


func _init() -> void:
	visible = false
	force_native = true
	unfocusable = true
	mouse_passthrough = true
	transparent = true
	transparent_bg = true
	borderless = true
	unresizable = true
	transient = false
	exclusive = false
	title = "MarwanOS achievement notification"
	set_process_input(false)
	set_process_unhandled_input(false)
	gui_disable_input = true
	# Use the same 1080p design coordinates as the main shell, preserving width
	# on ultrawide outputs rather than stretching the notification horizontally.
	content_scale_size = Vector2i(1920, 1080)
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _ready() -> void:
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -796
	_panel.offset_right = -96
	_panel.offset_top = 54
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = TvTheme.SURFACE
	box.set_corner_radius_all(16)
	box.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", box)
	surface.add_child(_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	_heading = Label.new()
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_font_size_override("font_size", 30)
	_heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_heading)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 26)
	_body.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_expire)
	add_child(_timer)
	close_requested.connect(_expire)


func present(entry: Dictionary, lifetime: float = LIFETIME_SECONDS) -> bool:
	_heading.text = str(entry.get("summary", "Achievement unlocked")).left(180)
	_body.text = str(entry.get("body", "")).left(360)
	var screen := DisplayServer.window_get_current_screen()
	var output_size := DisplayServer.screen_get_size(screen)
	var output_position := DisplayServer.screen_get_position(screen)
	# Godot creates/maps the native XID inside show() and clamps off-screen
	# initial positions. gamescope explicitly ignores 1x1 override/dropdown
	# windows, so keep that inert size until external classification is verified.
	initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	size = Vector2i.ONE
	position = output_position
	_map_frame = Engine.get_process_frames()
	show()
	if DisplayServer.get_name() == "X11":
		_native_handle = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window_id())
		if not _set_external_overlay(true):
			dismiss()
			ShellLog.warn("achievement toast overlay unavailable; notification remains in Info")
			return false
	elif DisplayServer.get_name() != "headless":
		dismiss()
		ShellLog.warn("achievement toast needs XWayland; notification remains in Info")
		return false
	# xprop's synchronous read-back precedes these configure events, so gamescope
	# sees the external classification before a usable overlay-sized rectangle.
	size = output_size
	position = output_position
	_timer.start(clampf(lifetime, 0.05, LIFETIME_SECONDS))
	ShellLog.info("passive achievement toast shown on window %s" % _native_handle)
	return true


func _set_external_overlay(enabled: bool) -> bool:
	if _native_handle <= 0:
		return false
	var value := "1" if enabled else "0"
	var output: Array = []
	if _run_x11("xprop", ["-id", str(_native_handle), "-f", OVERLAY_PROPERTY, "32c", "-set", OVERLAY_PROPERTY, value], output) != 0:
		return false
	output.clear()
	if _run_x11("xprop", ["-id", str(_native_handle), "-notype", OVERLAY_PROPERTY], output) != 0 or output.is_empty():
		return false
	return str(output[0]).get_slice("=", 1).strip_edges() == value


func _run_x11(command: String, arguments: Array, output: Array) -> int:
	# An unresponsive X server must not leave the shell blocked indefinitely.
	var result := OS.execute("/usr/bin/timeout", ["--kill-after=0.1", "1", command] + arguments, output, true)
	if result != 0:
		ShellLog.warn("achievement toast %s failed (%s): %s" % [command, result, " ".join(output)])
	return result


func dismiss() -> void:
	if _dismissed:
		return
	if _dismissing:
		await dismissed
		return
	_dismissing = true
	if _timer != null:
		_timer.stop()
	if _native_handle > 0 and Engine.get_process_frames() == _map_frame:
		# Godot's X11 event queue can still contain this new XID's MapNotify.
		# Destroying its WindowData now makes that event fall back to the main
		# window and focus it. Keep the tagged XID alive through the next frame.
		# gamescope scans even unmapped external windows, but excludes opacity0;
		# set opacity BEFORE unmap removes its property event subscription.
		var output: Array = []
		if _run_x11("xprop", ["-id", str(_native_handle), "-f", "_NET_WM_WINDOW_OPACITY", "32c", "-set", "_NET_WM_WINDOW_OPACITY", "0"], output) != 0:
			ShellLog.warn("achievement toast opacity suppression unavailable")
		output.clear()
		if _run_x11("xdotool", ["windowunmap", str(_native_handle)], output) != 0:
			ShellLog.warn("achievement toast native unmap unavailable")
		await get_tree().process_frame
	# Retain external classification until native destruction, never exposing
	# an ordinary override window to gamescope focus selection.
	hide()
	_native_handle = 0
	_dismissed = true
	dismissed.emit()


func retire() -> void:
	if _retiring:
		return
	_retiring = true
	# Cleanup belongs to this independently parented Window, so freeing the
	# shell Control during the grace frame cannot leave an orphan behind.
	await dismiss()
	queue_free()


func _expire() -> void:
	expired.emit()
	retire()


func _exit_tree() -> void:
	if _timer != null:
		_timer.stop()
