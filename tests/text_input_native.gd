extends SceneTree

## Driven by text_input_native.py on a separate Xvfb display and session bus.
var directory := ""
var service: Node
var last_command := 0
var clock := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = OS.get_environment("PC1_NATIVE_INPUT_CHECK")
	var shell: Control = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(shell)
	root.get_node("Launcher")._current = {"id": "native-input-fixture", "title": "Native input fixture"}
	root.get_node("Launcher")._app_on_screen = true
	root.get_node("ControllerRouter").set_app_input(true)
	service = root.get_node("TextInput")
	write_state()

func _process(delta: float) -> bool:
	if service == null: return false
	clock += delta
	if clock < 0.05: return false
	clock = 0.0
	var path := directory.path_join("command.json")
	if FileAccess.file_exists(path):
		var command: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if command is Dictionary and int(command.get("id", 0)) > last_command:
			last_command = int(command.id)
			if command.get("action") == "quit":
				service.close()
				quit()
			elif command.get("action") == "delete":
				_press("ui_shell_x")
			elif command.get("action") == "type_next":
				_press("ui_right")
				_press("ui_accept")
	write_state()
	return false

func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)

func write_state() -> void:
	var state := {"ready": true, "open": service.is_open() and service._ready_for_input, "paused": root.get_node("Launcher")._pad_keys_paused,
		"blocked": root.get_node("ControllerRouter")._text_input}
	var focus_path: String = service._directory.path_join("focus.json")
	if FileAccess.file_exists(focus_path):
		state["focus"] = JSON.parse_string(FileAccess.get_file_as_string(focus_path))
	if service.is_open():
		state["masked"] = service._keyboard.masked
		state["draft_empty"] = service._keyboard._text.is_empty()
		state["token"] = service._context.get("token")
		state["unfocusable"] = service._window.unfocusable
		var focused: Control = service.focus_viewport().gui_get_focus_owner()
		state["focused_key"] = focused.text if focused is Button else ""
		var factor: Vector2 = Vector2(service._window.size) / Vector2(service._window.content_scale_size)
		for label in ["q", "a", "Done"]:
			var key: Control = null
			for row: Array in service._keyboard._keys:
				for candidate: Button in row:
					if candidate.text == label: key = candidate
			if key != null:
				var at := Vector2(service._window.position) + key.get_global_rect().get_center() * factor
				state[label] = [at.x, at.y]
	var file := FileAccess.open(directory.path_join("state.json.tmp"), FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	DirAccess.rename_absolute(directory.path_join("state.json.tmp"), directory.path_join("state.json"))
