extends Node

## A separate no-focus native window can float above embedded Steam as well as
## ordinary application windows. AT-SPI identifies editors; the helper checks
## their real focus again before delivering each edit. Field values stay in apps.
const Keyboard = preload("res://src/keyboard.gd")
var _helper := "/usr/lib/marwanos/text_input.py"
var _directory := ""
var _pid := -1
var _clock := 0.0
var _serial := -1
var _request_id := 0
var _context: Dictionary = {}
var _window: Window
var _keyboard: Control
var _launcher_paused := false
var _forwarding := false
var _ready_for_input := false
var _direct_editor: Callable

func _ready() -> void:
	var override := OS.get_environment("MARWANOS_TEXT_INPUT_HELPER")
	if not override.is_empty(): _helper = override
	var runtime := OS.get_environment("XDG_RUNTIME_DIR")
	if OS.get_name() != "Linux" or DisplayServer.get_name() != "X11" or runtime.is_empty() or not FileAccess.file_exists(_helper):
		set_process(false)
		return
	_directory = runtime.path_join("marwanos/text-input-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_directory)
	_pid = OS.create_process("/usr/bin/python3", [_helper, "--directory", _directory, "--shell-pid", str(OS.get_process_id())])
	Launcher.launch_finished.connect(func(_entry: Dictionary): close())
	Launcher.minimized.connect(func(_entry: Dictionary): close())

func is_open() -> bool:
	return is_instance_valid(_keyboard)

func focus_viewport() -> Viewport:
	return _window if is_open() else get_viewport()

func _process(delta: float) -> void:
	if _direct_editor.is_valid():
		if is_open(): _write_overlay()
		return
	_clock += delta
	if _clock < 0.1: return
	_clock = 0.0
	if _pid <= 0 or not OS.is_process_running(_pid):
		close()
		set_process(false)
		return
	var path := _directory.path_join("focus.json")
	if not FileAccess.file_exists(path): return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or Time.get_unix_time_from_system() - float(value.get("heartbeat", 0)) > 2:
		close()
		return
	if int(value.get("serial", -1)) != _serial:
		_serial = int(value.get("serial", -1))
		_apply_context(value)
	if is_open():
		_write_overlay()

func _apply_context(value: Dictionary) -> void:
	if _direct_editor.is_valid(): return
	if not value.get("editable", false):
		close()
		return
	if is_open() and value.get("token") == _context.get("token"):
		return
	# The native browser has its own field bridge. Other shell dialogs retain
	# their existing keyboard ownership and cannot be covered by an app request.
	if not is_open() and not SteamEmbed.owns_input() and not Launcher.app_on_screen():
		return
	if not is_open() and Launcher._pad_keys_paused:
		return
	var paused := _launcher_paused if is_open() else Launcher._pad_keys_paused
	close()
	_launcher_paused = paused
	_context = value.duplicate()
	_open()

func open_browser_editor(editor: Callable) -> void:
	close()
	_direct_editor = editor
	_context = {"mode": "text"}
	_launcher_paused = Launcher._pad_keys_paused
	_open()

func _open() -> void:
	ControllerRouter.set_text_input(true)
	Launcher.set_pad_keys_paused(true)
	_window = Window.new()
	_window.visible = false
	_window.force_native = true
	_window.title = "MarwanOS keyboard"
	_window.borderless = true
	_window.unresizable = true
	_window.always_on_top = true
	_window.unfocusable = true
	_window.transient = false
	_window.transparent = true
	_window.transparent_bg = true
	_window.size = Vector2i(Keyboard.PANEL_WIDTH + Keyboard.PANEL_GAP * 2, 480)
	_window.content_scale_size = _window.size
	_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_window.close_requested.connect(close)
	add_child(_window)
	_keyboard = Keyboard.new()
	_keyboard.floating_window = true
	_keyboard.live_input = true
	_keyboard.masked = _context.get("type", "") == "password"
	_keyboard.input_context = str(_context.get("mode", "text"))
	_keyboard.title_text = "Password" if _keyboard.masked else "Type"
	_keyboard.text_inserted.connect(func(value: String): _edit({"kind": "text", "text": value}))
	_keyboard.editing_key.connect(func(key: String): _edit({"kind": "key", "key": key}))
	_keyboard.submitted.connect(func(_value: String): close())
	_keyboard.cancelled.connect(close)
	_keyboard.window_move_requested.connect(_move_window)
	_window.add_child(_keyboard)
	_layout_window.call_deferred()

func _layout_window() -> void:
	if not is_open(): return
	var logical: Vector2 = _keyboard._panel.get_combined_minimum_size() + Vector2.ONE * Keyboard.PANEL_GAP * 2
	var scale_factor := get_tree().root.get_screen_transform().get_scale().x
	_window.content_scale_size = Vector2i(logical.ceil())
	var native_size := Vector2i((logical * scale_factor).ceil())
	var screen := DisplayServer.screen_get_usable_rect()
	var native_position := screen.position + Vector2i((Vector2(screen.size - native_size) * _keyboard._saved_position).round())
	_window.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	_window.position = native_position
	var external := OS.get_environment("MARWANOS_COMPOSITOR") != "x11" and DisplayServer.get_name() == "X11"
	_window.size = Vector2i.ONE if external else native_size
	_window.show()
	# gamescope needs an explicit external-overlay property for native windows.
	# Classify a harmless 1x1 window before it can become a focus candidate.
	if external:
		var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, _window.get_window_id())
		var output: Array = []
		var result := OS.execute("/usr/bin/timeout", ["1", "xprop", "-id", str(handle), "-f", "GAMESCOPE_EXTERNAL_OVERLAY", "32c", "-set", "GAMESCOPE_EXTERNAL_OVERLAY", "1"], output, true)
		output.clear()
		if handle <= 0 or result != 0 or OS.execute("/usr/bin/timeout", ["1", "xprop", "-id", str(handle), "-notype", "GAMESCOPE_EXTERNAL_OVERLAY"], output, true) != 0 or output.is_empty() or str(output[0]).get_slice("=", 1).strip_edges() != "1":
			ShellLog.warn("Native keyboard overlay unavailable")
			close.call_deferred()
			return
	_window.size = native_size
	_window.position = native_position
	_move_window(Vector2.ZERO)
	_keyboard._restore_position()
	var first_row := 0 if _keyboard.input_context in ["numeric", "decimal", "tel", "number"] else 1
	_keyboard._keys[first_row][0].grab_focus()
	_ready_for_input = true
	_write_overlay()

func _move_window(amount: Vector2) -> void:
	if not is_open(): return
	var screen := DisplayServer.screen_get_usable_rect()
	var available := (screen.size - _window.size).max(Vector2i.ZERO)
	var scale_factor := Vector2(_window.size) / Vector2(_window.content_scale_size)
	_window.position = (_window.position + Vector2i(amount * scale_factor)).clamp(screen.position, screen.position + available)
	_keyboard._saved_position = Vector2(
		float(_window.position.x - screen.position.x) / available.x if available.x > 0 else 0.5,
		float(_window.position.y - screen.position.y) / available.y if available.y > 0 else 1.0)
	_write_overlay()

func _write_overlay() -> void:
	if _directory.is_empty() or not is_open(): return
	var factor := Vector2(_window.size) / Vector2(_window.content_scale_size)
	var panel: Rect2 = _keyboard.get_panel_rect()
	var rect := Rect2(Vector2(_window.position) + panel.position * factor, panel.size * factor)
	_write_json("overlay.json", {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "heartbeat": Time.get_unix_time_from_system()})

func _edit(value: Dictionary) -> void:
	if _direct_editor.is_valid():
		_direct_editor.call(value)
		return
	if not is_open() or _directory.is_empty(): return
	_request_id += 1
	value["token"] = _context.get("token", "")
	value["id"] = _request_id
	_write_json("edit-%012d.json" % _request_id, value)

func _write_json(filename: String, value: Dictionary) -> void:
	var path := _directory.path_join(filename)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value))
	file.close()
	FileAccess.set_unix_permissions(path + ".tmp", 384)
	DirAccess.rename_absolute(path + ".tmp", path)

func handle_input(event: InputEvent) -> bool:
	if not is_open():
		# A native-window shortcut can close the board before the main viewport
		# receives the same broker event. Consume it before Steam/app handling.
		if event.get_meta("marwanos_keyboard_input", false):
			get_viewport().set_input_as_handled()
			return true
		return false
	if _forwarding: return false
	if event is InputEventMouse: return false
	# Broker events arrive at the main viewport even though X focus remains in
	# the app. Route them into the keyboard's native window once.
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_shell_home"):
		close()
	elif _ready_for_input:
		_forwarding = true
		_window.push_input(event)
		_forwarding = false
	return true

func close() -> void:
	if not is_open(): return
	_ready_for_input = false
	var window := _window
	_keyboard.set_process_input(false)
	window.hide()
	_window = null
	_keyboard = null
	_context = {}
	_direct_editor = Callable()
	# Keep the viewport in the tree until its current GUI event has finished.
	window.queue_free()
	ControllerRouter.set_text_input(false)
	Launcher.set_pad_keys_paused(_launcher_paused)
	if not _directory.is_empty():
		_write_json("overlay.json", {})

func _exit_tree() -> void:
	close()
	if _pid > 0 and OS.is_process_running(_pid): OS.kill(_pid)
	if not _directory.is_empty():
		for filename in DirAccess.get_files_at(_directory):
			DirAccess.remove_absolute(_directory.path_join(filename))
		DirAccess.remove_absolute(_directory)
