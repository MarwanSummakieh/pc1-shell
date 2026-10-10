extends CanvasLayer

## Display-only rest. The OS and Bluetooth broker keep running; no suspend is
## requested. Added last so wake input is consumed before any underlying menu.
signal woke()

var _active := false
var _saved: Dictionary = {}
var _previous_fps := 0
var _connected_slots: Array = []
var _poll := 0.0


static func supported() -> bool:
	return OS.get_name() == "Linux" and OS.get_environment("MARWANOS_COMPOSITOR") == "x11" \
		and not OS.get_environment("DISPLAY").is_empty()


static func recover_display() -> void:
	if not supported():
		return
	var recovery = load("res://src/rest_screen.gd").new()
	recovery._restore_saved_display()
	recovery.free()


func _ready() -> void:
	layer = 100
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(black)
	Input.joy_connection_changed.connect(_on_controller_connection)


func _display_supported() -> bool:
	return supported()


func _xset(arguments: Array) -> Dictionary:
	var output: Array = []
	var code := OS.execute("xset", arguments, output, true)
	return {"code": code, "output": "\n".join(output)}


func _state_path() -> String:
	var runtime := OS.get_environment("XDG_RUNTIME_DIR")
	return runtime.path_join("marwanos/rest-display.json") if not runtime.is_empty() else ""


func begin() -> bool:
	if _active or not _display_supported():
		return false
	var query := _xset(["q"])
	var expression := RegEx.new()
	expression.compile("Standby: (\\d+)\\s+Suspend: (\\d+)\\s+Off: (\\d+)")
	var match_value := expression.search(str(query.output))
	if int(query.code) != 0 or match_value == null or not "DPMS is " in str(query.output):
		return false
	_saved = {"enabled": "DPMS is Enabled" in str(query.output), "timeouts": [
		int(match_value.get_string(1)), int(match_value.get_string(2)), int(match_value.get_string(3))]}
	var path := _state_path()
	if path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_saved))
	file.close()
	# No automatic timeout is left behind after returning to the normal session.
	for arguments in [["+dpms"], ["dpms", "0", "0", "0"], ["dpms", "force", "off"]]:
		if int(_xset(arguments).code) != 0:
			_restore_saved_display()
			return false
	_active = true
	_previous_fps = Engine.max_fps
	Engine.max_fps = 10
	_connected_slots = _slots()
	ShellLog.info("rest mode entered (display off; PC stays running)")
	return true


func _slots() -> Array:
	var connected: Array = []
	for player in ControllerRouter.players:
		if bool(player.get("connected", false)):
			connected.append(int(player.get("slot", 0)))
	return connected


func _process(delta: float) -> void:
	if not _active:
		return
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	var current := _slots()
	for slot in current:
		if not _connected_slots.has(slot):
			wake()
			return
	_connected_slots = current


func _on_controller_connection(_device: int, connected: bool) -> void:
	# A pad that powered off while resting may consume PS while reconnecting.
	if _active and connected:
		wake()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_shell_home") \
		or (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed):
		wake()


func wake() -> void:
	if not _active:
		return
	_restore_saved_display()
	_active = false
	Engine.max_fps = _previous_fps
	ShellLog.info("rest mode ended")
	woke.emit()
	queue_free()


func _restore_saved_display() -> void:
	var path := _state_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var state = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not state is Dictionary or not state.get("timeouts") is Array or state.timeouts.size() != 3:
		return
	var arguments: Array = ["dpms"]
	for timeout in state.timeouts:
		arguments.append(str(clampi(int(timeout), 0, 65535)))
	var success := true
	for command in [["dpms", "force", "on"], arguments, ["+dpms" if bool(state.get("enabled", false)) else "-dpms"]]:
		if int(_xset(command).code) != 0:
			success = false
	if success:
		DirAccess.remove_absolute(path)
	else:
		ShellLog.warn("display restore failed; saved settings retained for next shell start")


func _exit_tree() -> void:
	if _active:
		_restore_saved_display()
		Engine.max_fps = _previous_fps
