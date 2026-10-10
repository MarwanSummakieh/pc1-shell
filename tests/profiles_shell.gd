extends SceneTree

var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1
func frames(count: int = 5) -> void:
	for frame in count:
		await process_frame
func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event, true)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await frames(2)
func _run() -> void:
	var profiles := root.get_node("Profiles")
	var history := root.get_node("PlayHistory")
	var installed := root.get_node("Installed")
	root.get_node("ControllerRouter").set_process(false)
	root.get_node("ControllerRouter")._routed = true
	root.get_node("PlayerOne").device = 15
	check(profiles.current().id == "owner", "original user is migrated")
	check(profiles.add_user(" \n\t", profiles.COLORS[0]).is_empty(), "blank user names cannot be saved")
	profiles.error = ""
	var original_games: Array = installed.apps.duplicate(true)
	var entry := {"id": "fixture.game", "title": "Shared game", "kind": "game", "state": "installed", "exec": ["never-run"]}
	history.sample(entry, true, 1000, 1000)
	history.sample(entry, true, 3000, 1002)
	history.finish("test", 3000, 1002)
	var alice: String = profiles.add_user("Alice", profiles.COLORS[1])
	check(not alice.is_empty(), "new user is stored")
	var steam := root.get_node("SteamEmbed")
	steam.snapshot = {"phase": "ready", "client": 123, "game_id": 0}
	var selected: bool = await profiles.select_user(alice)
	check(selected and profiles.current().name == "Alice", "selecting a user updates identity")
	check(steam.snapshot.get("client", 0) == 123 and steam._action == "shell", "switching users hides the Steam pane without closing its session")
	steam.snapshot = {"phase": "ready", "client": 123, "game_id": 42}
	selected = await profiles.select_user("owner")
	check(not selected and profiles.active == alice, "running Steam game still prevents switching users")
	steam.snapshot = {}
	profiles.error = ""
	check(history.games.is_empty(), "new user has fresh play history")
	check(installed.apps == original_games, "switching users preserves the shared library")
	history.sample(entry, true, 4000, 1004)
	history.sample(entry, true, 5000, 1005)
	history.finish("test", 5000, 1005)
	await profiles.select_user("owner")
	check(is_equal_approx(float(history.stats("fixture.game").total_seconds), 2.0), "original user's history is restored")
	await profiles.select_user(alice)
	check(is_equal_approx(float(history.stats("fixture.game").total_seconds), 1.0), "second user's history stays independent")
	check(profiles.edit_user("Alice renamed", profiles.COLORS[2]), "user name and avatar can be edited")
	profiles.reload()
	check(profiles.current().name == "Alice renamed", "profiles survive reloading")
	var launcher := root.get_node("Launcher")
	launcher._current = entry
	launcher._minimized = true
	selected = await profiles.select_user("owner")
	check(not selected and profiles.active == alice, "minimized game prevents switching users")
	launcher._current = {}
	launcher._minimized = false
	profiles.error = ""
	var home: Control = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(home)
	await frames()
	var switch_button: Control
	for button in home._bar_buttons:
		if str(button.get_meta("destination", "")) == "Switch user":
			switch_button = button
	check(switch_button != null, "Home system menu offers Switch user")
	if switch_button != null:
		switch_button.pressed.emit()
	await frames()
	check(profiles.is_open(), "Home Switch user opens the user management picker")
	var screen: Control = profiles._screen
	check(screen._buttons[0].focus_mode == Control.FOCUS_ALL, "user tiles are controller focusable")
	check(screen._buttons.size() == profiles.users.size() + 2, "picker offers users, add user and edit user")
	await press("ui_cancel")
	check(not profiles.is_open(), "Back closes Switch user and restores Home")
	for dimensions in [Vector2i(900, 1080), Vector2i(1920, 1080), Vector2i(2580, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		root.add_child(viewport)
		var responsive: Control = load("res://src/users_screen.gd").new()
		viewport.add_child(responsive)
		await frames()
		check(responsive._choices.get_global_rect().end.x <= dimensions.x - 90, "user tiles fit at %s" % dimensions)
		viewport.queue_free()
		await frames()
	var settings := root.get_node("Settings")
	settings.open()
	await frames()
	for row in settings._screen._rows:
		if row._name.text == "Users":
			row.activated.emit()
			break
	await frames()
	check(profiles.is_open() and not settings.is_open(), "Settings Users opens the picker")
	profiles._close()
	profiles.open(true)
	await frames()
	await press("ui_cancel")
	check(profiles.is_open(), "startup requires choosing a user")
	screen = profiles._screen
	screen._show_form(false)
	await frames()
	screen._enter_name()
	await frames()
	check(screen._keyboard != null, "Add user opens the controller keyboard")
	screen._keyboard.cancelled.emit()
	await frames()
	check(screen._keyboard == null, "cancelling a name returns to the form")
	await press("ui_cancel")
	check(not screen._editing, "Back returns from Add user to the picker")
	var capture := OS.get_environment("MARWANOS_PROFILES_CAPTURE")
	if not capture.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	profiles._close()
	await profiles.select_user("owner")
	home.queue_free()
	await frames()
	print("Profiles shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
