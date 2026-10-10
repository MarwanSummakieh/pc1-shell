extends Node

## Native host and controller ownership live independently of the Stores screen.
signal changed()
signal navigation_requested()

var snapshot: Dictionary = {}
var _surface: Control = null
var _folder := ""
var _helper := "/usr/lib/marwanos/steam_embed.py"
var _pid := -1
var _clock := 0.0
var _want_focus := false
var _action := ""
var _action_id := 0
var _last_game := 0
var _unresponsive := false

func _ready() -> void:
	_folder = OS.get_environment("XDG_RUNTIME_DIR").path_join("marwanos/steam-embed")
	var override := OS.get_environment("MARWANOS_STEAM_EMBED_HELPER")
	if not override.is_empty():
		_helper = override

func supported() -> bool:
	var enabled := OS.get_environment("MARWANOS_STEAM_EMBED") == "1" or not OS.get_environment("MARWANOS_STEAM_EMBED_HELPER").is_empty()
	return enabled and OS.get_environment("MARWANOS_COMPOSITOR") == "x11" and FileAccess.file_exists(_helper)

func show_pane(surface: Control) -> void:
	_surface = surface
	if not supported():
		snapshot = {"phase": "unsupported", "detail": "Windowed Steam is not available on this display yet."}
		changed.emit()
		return
	DirAccess.make_dir_recursive_absolute(_folder)
	if _unresponsive and _pid > 0 and OS.is_process_running(_pid):
		# The native host's X save set preserves Steam even on forced host exit.
		OS.kill(_pid)
		_pid = -1
	if _pid <= 0 or not OS.is_process_running(_pid):
		_unresponsive = false
		snapshot = {"phase": "loading"}
		DirAccess.remove_absolute(_folder.path_join("state.json"))
		_pid = OS.create_process("/usr/bin/python3", [_helper, "--directory", _folder,
			"--shell-pid", str(OS.get_process_id())])
		if _pid <= 0:
			snapshot = {"phase": "error", "detail": "Steam could not open. Try again."}
			changed.emit()
			return
	_command("start")

func hide_pane() -> void:
	_want_focus = false
	_surface = null
	if Launcher.current_entry().is_empty():
		ControllerRouter.set_app_input(false)
	_command("shell")

func enter_pane() -> void:
	if snapshot.get("phase", "") != "ready":
		if is_instance_valid(_surface):
			show_pane(_surface)
		return
	_want_focus = true
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null:
		owner.release_focus()
	_command("focus")

func leave_pane() -> void:
	_want_focus = false
	ControllerRouter.set_app_input(false)
	_command("shell")
	navigation_requested.emit()

func owns_input() -> bool:
	return _want_focus and is_instance_valid(_surface) and Launcher.current_entry().is_empty()

func handle_input(event: InputEvent) -> bool:
	if not owns_input():
		return false
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		_command("menu")
		get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed("ui_shell_home"):
		leave_pane()
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction:
		get_viewport().set_input_as_handled()
		return true
	return false

func launch_fullscreen() -> void:
	hide_pane()
	if _pid > 0 and OS.is_process_running(_pid):
		_command("detach")
		var deadline := Time.get_ticks_msec() + 3000
		while int(snapshot.get("client", 0)) != 0 and OS.is_process_running(_pid) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if int(snapshot.get("client", 0)) != 0 and OS.is_process_running(_pid):
			return
	Launcher.launch({"id": "steam.signin", "title": "Steam", "kind": "application",
		"state": "installed", "exec": ["/usr/lib/marwanos/steamctl", "signin"]})

func close_game() -> void:
	_command("close_game")

func _command(action: String) -> void:
	_action_id += 1
	_action = action
	_write_request()

func _write_request() -> void:
	if _pid <= 0 or _folder.is_empty():
		return
	var visible := is_instance_valid(_surface) and _surface.is_visible_in_tree() and not Launcher.is_busy()
	var rect := Rect2(0, 0, 640, 480)
	if is_instance_valid(_surface):
		var screen_transform := _surface.get_viewport().get_screen_transform()
		rect = screen_transform * _surface.get_global_rect()
	var value := {"owner": DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE),
		"rect": [roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y)],
		"visible": visible, "focus": owns_input(), "action": _action, "action_id": str(_action_id)}
	var path := _folder.path_join("request.json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(value))
	file.close()
	FileAccess.set_unix_permissions(path + ".tmp", 384)
	DirAccess.rename_absolute(path + ".tmp", path)

func _process(delta: float) -> void:
	if _pid <= 0:
		return
	_clock += delta
	if _clock < 0.2:
		return
	_clock = 0.0
	_write_request()
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(_folder.path_join("state.json"))) if FileAccess.file_exists(_folder.path_join("state.json")) else null
	if value is Dictionary:
		var previous := str(snapshot.get("phase", "")) + str(snapshot.get("client", 0))
		snapshot = value
		if Time.get_unix_time_from_system() - float(snapshot.get("heartbeat", 0)) > 3:
			if not _unresponsive:
				var client := int(snapshot.get("client", 0))
				if client > 0:
					OS.execute("xdotool", ["windowunmap", str(client)])
				_want_focus = false
				ControllerRouter.set_app_input(false)
				if is_instance_valid(_surface) and _surface.is_visible_in_tree():
					navigation_requested.emit()
			_unresponsive = true
			snapshot = {"phase": "error", "detail": "Steam pane stopped responding. Open it again."}
			_want_focus = false
		if str(snapshot.get("phase", "")) + str(snapshot.get("client", 0)) != previous:
			changed.emit()
		var appid := int(snapshot.get("game_id", 0))
		if appid > 0 and appid != _last_game and Launcher.current_entry().is_empty():
			_last_game = appid
			_want_focus = false
			var entry := {"id": "steam." + str(appid), "title": "Steam game " + str(appid),
				"kind": "game", "state": "installed", "exec": ["/usr/lib/marwanos/steamctl", "launch", str(appid)]}
			for installed in Installed.apps:
				if installed.get("id", "") == entry.id:
					entry = installed.duplicate()
					break
			Launcher.adopt_steam_game(entry)
		if appid == 0:
			_last_game = 0
	if Launcher.current_entry().is_empty():
		var focused := bool(snapshot.get("client_has_focus", false))
		ControllerRouter.set_app_input(owns_input() and snapshot.get("visible", false) and focused)

func _exit_tree() -> void:
	ControllerRouter.set_app_input(false)
	_want_focus = false
	_surface = null
	_command("quit")
