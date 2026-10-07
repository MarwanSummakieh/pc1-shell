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
	var service := root.get_node_or_null("Achievements")
	if service == null:
		service = load("res://src/achievements.gd").new()
		service.name = "Achievements"
		root.add_child(service)
	service._folder = "/tmp/pc1-achievements-shell-%d" % OS.get_process_id()
	service.games = {"managed.tekken": {"status": "ready", "provider": "RUNE local", "unlocked_count": 1, "total_count": 2, "message": "", "achievements": [{"id": "ONE", "name": "First step", "description": "Do a thing", "unlocked": true, "unlock_time": 123}, {"id": "TWO", "name": "Next step", "unlocked": false, "progress_current": 2, "progress_max": 10}]}}
	var page: Control = load("res://src/achievements_page.gd").new()
	page.entry = {"id": "managed.tekken", "title": "TEKKEN 8"}
	root.add_child(page)
	await process_frame
	check(page._rows.size() == 2 and page._summary.text.contains("1 / 2 unlocked"), "all view shows truthful counts and rows")
	check(root.get_viewport().gui_get_focus_owner() == page._rows[0], "first achievement takes controller focus")
	await press("ui_shell_r1")
	check(page._rows.size() == 1 and page._rows[0].get_meta("achievement_id") == "TWO", "R1 filters locked achievements")
	await press("ui_shell_r1")
	check(page._rows.size() == 1 and page._rows[0].get_meta("achievement_id") == "ONE", "R1 filters unlocked achievements")
	await press("ui_shell_y")
	check(DirAccess.open(service._folder.path_join("requests")).get_files().size() == 1, "Y writes a refresh request")
	service.games["managed.tekken"].status = "offline"
	service.games["managed.tekken"].message = "Cached achievements are available offline."
	service.changed.emit()
	check(page._rows.size() == 1 and page._message.text.contains("offline"), "cached achievements remain browsable offline")
	service.games["managed.tekken"] = {"status": "unavailable", "message": "Unsupported provider."}
	service.changed.emit()
	check(page._rows.is_empty() and page._summary.text.contains("total unavailable"), "unsupported providers do not display fake completion")
	var closed := [false]
	page.closed.connect(func(): closed[0] = true)
	await press("ui_cancel")
	check(closed[0], "B closes the page without mouse input")
	page.queue_free()
	print("Achievements shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
