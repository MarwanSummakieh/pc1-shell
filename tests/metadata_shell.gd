extends SceneTree

var failures := 0

func check(value: bool, label_text: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func _initialize() -> void:
	_run.call_deferred()

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

func _run() -> void:
	await process_frame
	var service := root.get_node("Metadata")
	service._folder = "/tmp/pc1-metadata-shell-%d" % OS.get_process_id()
	service.games = {"managed.tekken": {"title": "TEKKEN 8", "source": "Windows", "status": "ready", "provider": "Steam Store", "provider_id": "1778820", "description": "Game description", "genres": ["Action"], "overrides": {"title": "My Tekken"}}}
	var original := {"id": "managed.tekken", "title": "original", "exec": ["unchanged"], "state": "installed", "input_mode": "gamepad"}
	var enriched: Dictionary = service.enrich(original)
	check(enriched.title == "My Tekken", "manual title wins")
	check(enriched.id == original.id and enriched.exec == original.exec and enriched.input_mode == "gamepad", "metadata preserves launch identity")
	var home: Control = load("res://src/shell_root.gd").new()
	root.get_node("Installed").apps = [{"id": "steam", "title": "Steam", "state": "installed", "exec": ["fixture"]}, enriched]
	root.add_child(home)
	await process_frame
	home._cards[1].grab_focus()
	await press("ui_down")
	check(home._details != null and not home.visible, "controller Down opens details and hides rail")
	var screen: Control = home._details
	check(root.get_viewport().gui_get_focus_owner() == screen._rows[0], "details starts on Play")
	screen._rows[1].grab_focus()
	await press("ui_accept")
	var paths := DirAccess.get_files_at(service._folder.path_join("requests"))
	check(paths.size() == 1, "controller refresh publishes one request")
	var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(service._folder.path_join("requests").path_join(paths[0])))
	check(request.action == "refresh" and request.game_id == original.id, "refresh targets installation ID")
	home._on_apps_changed(root.get_node("Installed").apps)
	check(root.get_viewport().gui_get_focus_owner() == screen._rows[1], "metadata rail rebuild retains details focus")
	screen._rows[2].grab_focus()
	await press("ui_accept")
	check(screen._keyboard != null and not screen._keyboard.masked, "controller match correction opens unmasked keyboard")
	await press("ui_cancel")
	await process_frame
	check(screen._keyboard == null and home._details != null, "keyboard cancel returns to details")
	await press("ui_cancel")
	await process_frame
	check(home._details == null and home.visible, "Back returns to rail")
	check(root.get_viewport().gui_get_focus_owner() == home._cards[1], "Back restores selected game after metadata rebuild")
	home.queue_free()
	print("Metadata shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
