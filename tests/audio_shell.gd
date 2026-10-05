extends SceneTree

var failures := 0
var _audio: Node
var _folder := ""
var _state: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label_text: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)


func write_state() -> void:
	_state["updated_at"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(_folder.path_join("state.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_state))
	file.close()
	_audio._poll()


func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func acknowledge() -> Dictionary:
	var path := _folder.path_join("request.json")
	var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(path)
	_state["request_id"] = request.id
	write_state()
	return request


func _run() -> void:
	await process_frame
	_audio = root.get_node("Audio")
	_folder = "/tmp/pc1-audio-shell-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_folder)
	_audio._folder = _folder
	_state = {"available": true, "error": "", "request_id": "", "default_output": "tv", "default_input": "mic",
		"outputs": [{"id": "1", "name": "tv", "label": "TV HDMI", "volume": 50, "muted": false,
			"port": "hdmi1", "ports": [{"name": "hdmi1", "label": "HDMI 1"}, {"name": "hdmi2", "label": "HDMI 2"}]},
			{"id": "2", "name": "usb", "label": "USB headphones", "volume": 60, "muted": false, "ports": []}],
		"inputs": [{"id": "3", "name": "mic", "label": "USB mic", "volume": 80, "muted": false, "ports": []}],
		"streams": [{"id": "7", "serial": "22", "label": "Game", "volume": 100, "muted": false}]}
	write_state()
	var settings := root.get_node("Settings")
	settings.open()
	await process_frame
	var parent: Control = settings._screen
	parent._audio_row.grab_focus()
	await press("ui_accept")
	check(parent._audio_screen != null, "Settings opens Audio with controller accept")
	var screen: Control = parent._audio_screen
	check(screen._controls.has("stream:7"), "live game mixer row")
	screen._controls["output:volume"].grab_focus()
	await press("ui_right")
	check(_audio.pending, "volume has a pending acknowledgement")
	var request := acknowledge()
	check(request.action == "volume" and request.value == 55, "controller raises volume by 5%")
	check(not _audio.pending, "matching service response clears pending")
	check(root.get_viewport().gui_get_focus_owner() == screen._controls["output:volume"], "heartbeat retains focus")
	await press("ui_accept")
	request = acknowledge()
	check(request.action == "mute" and request.value == true, "accept mutes output")
	screen._controls["input:volume"].grab_focus()
	await press("ui_accept")
	request = acknowledge()
	check(request.kind == "input" and request.target == "mic", "controller microphone mute")
	screen._controls["output"].grab_focus()
	await press("ui_accept")
	request = acknowledge()
	check(request.action == "default" and request.target == "usb", "select next output")
	screen._controls["output:port"].grab_focus()
	await press("ui_accept")
	request = acknowledge()
	check(request.action == "port" and request.value == "hdmi2", "select HDMI port")
	screen._controls["stream:7"].grab_focus()
	await press("ui_left")
	request = acknowledge()
	check(request.kind == "stream" and request.serial == "22" and request.value == 95, "live app volume uses stream identity")
	_state.streams = []
	write_state()
	check(not screen._controls.has("stream:7"), "closed app removed from mixer")
	check(root.get_viewport().gui_get_focus_owner() != null, "focus recovers after app exits")
	await press("ui_cancel")
	await process_frame
	check(parent._audio_screen == null and settings.is_open(), "back closes Audio only")
	check(root.get_viewport().gui_get_focus_owner() == parent._audio_row, "Settings restores Audio row focus")
	settings._finish()
	await process_frame
	var overlay: Control = load("res://src/app_overlay.gd").new()
	root.add_child(overlay)
	await process_frame
	var audio_row: Control
	for row in overlay._rows:
		if row.id == "audio":
			audio_row = row
	audio_row.grab_focus()
	await press("ui_accept")
	check(overlay._audio_screen != null and not overlay._menu.visible, "Home menu opens audio controls")
	await press("ui_cancel")
	await process_frame
	check(overlay._audio_screen == null and overlay._menu.visible, "Audio returns to Home menu")
	check(root.get_viewport().gui_get_focus_owner() == audio_row, "Home menu restores focus")
	overlay.queue_free()
	await process_frame
	_audio.request("output", "volume", _audio.outputs[0], 40)
	_audio._deadline = 0
	_audio._poll()
	check(not _audio.pending and _audio.error.contains("timed out"), "missing acknowledgement has recovery message")
	write_state()
	check(_audio.error.contains("timed out"), "unrelated heartbeat retains local error")
	_state.updated_at = 1
	var file := FileAccess.open(_folder.path_join("state.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_state))
	file.close()
	_audio._poll()
	check(not _audio.available and _audio.outputs.is_empty(), "stale service state disables devices")
	write_state()
	check(_audio.available, "audio service recovery")
	check(_audio.error.is_empty(), "recovered service clears unavailable error")
	if OS.get_environment("MARWANOS_AUDIO_PREVIEW") == "1":
		var preview_width := int(OS.get_environment("MARWANOS_AUDIO_PREVIEW_WIDTH"))
		if preview_width > 0:
			root.size = Vector2i(preview_width, 900)
		_state.streams = [{"id": "7", "serial": "22", "label": "Steam game", "volume": 70, "muted": false},
			{"id": "8", "serial": "23", "label": "Browser", "volume": 45, "muted": true}]
		write_state()
		var preview: Control = load("res://src/audio_screen.gd").new()
		root.add_child(preview)
		await create_timer(2).timeout
		var preview_path := OS.get_environment("MARWANOS_AUDIO_PREVIEW_PATH")
		root.get_texture().get_image().save_png(preview_path.get_basename() + "-outputs.png")
		preview._controls["stream:8"].grab_focus()
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png(preview_path)
	for filename in ["state.json", "request.json", "request.json.tmp"]:
		DirAccess.remove_absolute(_folder.path_join(filename))
	DirAccess.remove_absolute(_folder)
	print("Audio shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
