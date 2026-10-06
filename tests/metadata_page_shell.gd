extends SceneTree

var failures := 0
var service: Node
var details: Control
const GAME_ID := "managed.controller-metadata"

func check(ok: bool, text: String) -> void:
	if ok:
		print("PASS: " + text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func _initialize() -> void:
	_run.call_deferred()

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func requests() -> Array:
	var result: Array = []
	for name in DirAccess.get_files_at(service._folder.path_join("requests")):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(service._folder.path_join("requests").path_join(name)))
		if value is Dictionary:
			result.append(value)
	return result

func update_record(record: Dictionary) -> void:
	service.games[GAME_ID] = record
	service.changed.emit()

func _run() -> void:
	await process_frame
	service = root.get_node("Metadata")
	service.games = {GAME_ID: {"title": "TEKKEN 8", "status": "ready", "provider": "Steam Store", "provider_id": "1778820", "description": "Original cached description", "assets": {}, "candidates": []}}
	details = load("res://src/game_details.gd").new()
	details.entry = {"id": GAME_ID, "title": "TEKKEN 8", "state": "installed", "exec": ["never-run"], "input_mode": ""}
	root.add_child(details)
	await process_frame
	await press("ui_shell_options")
	var page: Control = details._metadata_page
	check(page != null and not details.visible, "Options opens the separate Metadata page")
	check(details._rows.size() == 1 and details._rows[0].get_meta("details_key") == "play", "Details retains exactly one Play action")
	check(root.gui_get_focus_owner() == page._rows[0] and page._rows[0].get_meta("metadata_key") == "refresh", "metadata starts on controller Refresh")
	check(page._source.text == "Source: Steam Store · App 1778820", "current provider and match are visible")
	await press("ui_accept")
	check(requests().size() == 1 and requests()[0] == {"action": "refresh", "game_id": GAME_ID}, "controller Refresh writes the real current-game metadata request")
	await press("ui_accept")
	check(requests().size() == 1, "repeated controller accept does not duplicate a pending request")
	check(page._message.text.contains("Waiting"), "request has visible pending feedback")
	update_record({"title": "TEKKEN 8", "status": "error", "provider": "Steam Store", "provider_id": "1778820", "description": "Original cached description", "error": "Metadata download failed. Refresh to retry.", "assets": {}, "candidates": []})
	check(page._message.text.contains("failed") and service.games[GAME_ID].description == "Original cached description", "offline refresh exposes the error while retaining cached data")
	update_record({"title": "TEKKEN 8", "status": "needs-match", "provider": "Steam Store", "description": "Original cached description", "candidates": [{"provider_id": "123", "title": "TEKKEN 8 Demo"}, {"provider_id": "1778820", "title": "TEKKEN 8"}, {"provider_id": "-1", "title": "Invalid candidate"}]})
	check(page._rows.size() == 4 and page._message.text.contains("matches"), "ambiguous candidates have named controller choices and invalid IDs are excluded")
	await press("ui_down")
	await press("ui_down")
	check(root.gui_get_focus_owner().get_meta("metadata_key") == "match:1778820", "D-pad selects the correct candidate independently of default focus")
	await press("ui_accept")
	check(requests().size() == 2 and requests()[1] == {"action": "match", "game_id": GAME_ID, "provider_id": "1778820"}, "candidate selection sends the exact provider match and installation identity")
	update_record({"title": "Corrected TEKKEN 8", "status": "ready", "provider": "Steam Store", "provider_id": "1778820", "description": "Corrected description", "candidates": []})
	check(page._heading.text == "Corrected TEKKEN 8 · Metadata" and page._rows.size() == 2, "completed correction replaces stale candidates and updates title")
	await press("ui_cancel")
	check(details._metadata_page == null and details.visible and root.gui_get_focus_owner() == details._rows[0], "Back returns to Details with Play focused")
	check(details._heading.text == "Corrected TEKKEN 8" and details._rows.size() == 1, "corrected metadata reaches Details without adding buttons")
	await press("ui_shell_y")
	check(details._achievements != null and not details.visible, "existing Y Achievements shortcut remains available")
	await press("ui_cancel")
	check(details._achievements == null and details.visible, "achievement Back still returns to Details")
	await press("ui_shell_options")
	page = details._metadata_page
	update_record({"title": "TEKKEN 8", "status": "loading", "provider": "Steam Store", "candidates": [{"provider_id": "1778820", "title": "TEKKEN 8"}]})
	check(page._rows[0].disabled and page._rows[1].disabled and not page._rows[2].disabled, "loading disables duplicate work but leaves Back reachable")
	check(root.gui_get_focus_owner().get_meta("metadata_key") == "back", "loading retains a usable controller focus")
	await press("ui_cancel")
	details.get_parent().remove_child(details)
	details.queue_free()
	await process_frame
	print("Metadata page shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
