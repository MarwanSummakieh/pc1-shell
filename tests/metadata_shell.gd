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
	service.games = {"managed.tekken": {"title": "TEKKEN 8", "source": "Windows", "status": "ready", "provider": "Steam Store", "provider_id": "1778820", "description": "Game description", "genres": ["Action"], "release_date": "Jan 25, 2024", "developers": ["Bandai Namco"], "overrides": {"title": "My Tekken"}}}
	var original := {"id": "managed.tekken", "title": "original", "exec": ["unchanged"], "state": "installed", "input_mode": "gamepad"}
	var enriched: Dictionary = service.enrich(original)
	check(enriched.title == "My Tekken", "manual title wins")
	check(enriched.id == original.id and enriched.exec == original.exec and enriched.input_mode == "gamepad", "metadata preserves launch identity")
	var home: Control = load("res://src/shell_root.gd").new()
	root.get_node("Installed").apps = [{"id": "steam", "title": "Steam", "state": "installed", "exec": ["fixture"]}, enriched]
	root.add_child(home)
	await process_frame
	home._cards[1].grab_focus()
	check(home._summary_row.visible and home._game_summary._title.text == "My Tekken", "selected title is displayed on home")
	check(home._game_summary._facts.text.contains("Action") and home._game_summary._facts.text.contains("2024") and home._game_summary._facts.text.contains("Bandai Namco"), "home displays genre, release and developer")
	check(home._game_summary._description.text == "Game description", "home displays description without opening details")
	home._cards[0].grab_focus()
	check(home._game_summary._title.text == "Steam" and not home._game_summary._facts.visible, "another selection replaces metadata without stale game facts")
	home._cards[1].grab_focus()
	await press("ui_down")
	check(home._details != null and not home.visible, "controller Down opens details and hides rail")
	var screen: Control = home._details
	check(root.get_viewport().gui_get_focus_owner() == screen._rows[0], "details starts on Play")
	check(screen._rows.size() == 1 and screen._rows[0].get_meta("details_key") == "play", "Play is the only details action")
	service.games[original.id].status = "needs-match"
	service.games[original.id].candidates = [{"title": "Other Tekken", "provider_id": "123"}]
	screen._refresh()
	await process_frame
	check(screen._rows.size() == 1, "ambiguous metadata does not add extra buttons")
	check(root.get_viewport().gui_get_focus_owner() == screen._rows[0], "metadata update retains Play focus")
	home._on_apps_changed(root.get_node("Installed").apps)
	check(root.get_viewport().gui_get_focus_owner() == screen._rows[0], "metadata rail rebuild retains details focus")
	await press("ui_shell_y")
	check(screen._achievements != null and not screen.visible and home._details == screen, "Y opens achievements from details without another action button")
	await press("ui_cancel")
	await process_frame
	check(screen._achievements == null and screen.visible and root.get_viewport().gui_get_focus_owner() == screen._rows[0], "achievement Back restores Play focus without closing details")
	await press("ui_cancel")
	await process_frame
	check(home._details == null and home.visible, "Back returns to rail")
	check(root.get_viewport().gui_get_focus_owner() == home._cards[1], "Back restores selected game after metadata rebuild")
	home.queue_free()
	print("Metadata shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
