extends SceneTree

var failures := 0
var screen: Control

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func press(button: int) -> void:
	root.get_node("PlayerOne").device = 0
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func wait_app(launcher: Node) -> void:
	for tick in 120:
		if launcher.app_on_screen():
			return
		await create_timer(0.25).timeout

func _run() -> void:
	# There is no physical pad in this container. Keep the synthetic identity
	# stable while software rendering waits; the hardware broker is tested apart.
	for child in root.get_node("PlayerOne").get_children():
		if child is Timer:
			child.stop()
	var launcher := root.get_node("Launcher")
	var installs := root.get_node("WindowsInstall")
	var entry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("PC1_REAL_MANIFEST")))
	installs._poll()
	root.get_node("Installed")._poll()
	screen = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	launcher.launch(entry)
	await wait_app(launcher)
	check(launcher.app_on_screen(), "real Windows application mapped")
	var pid: int = launcher._pid
	# The runner supplies an independent X window owned by an unrelated live
	# process with this app's WINEPREFIX, like a leftover setup wizard.
	var unrelated_window := OS.get_environment("PC1_UNRELATED_WINDOW").to_int()
	check(unrelated_window > 0 and not root.get_node("Kiosk")._window_belongs_to_app(unrelated_window, pid), "same-prefix unrelated process cannot complete launch focus")
	await press(JOY_BUTTON_GUIDE)
	check(screen._overlay != null, "controller opens real app overlay")
	check(not root.get_node("ControllerRouter")._app_input, "overlay keeps application controller neutral")
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_DPAD_DOWN) # Audio -> Minimize.
	await press(JOY_BUTTON_A)
	check(screen.visible and launcher.is_minimized() and OS.is_process_running(pid), "real app minimized with wrapper alive")
	await create_timer(0.7).timeout
	if OS.get_environment("MARWANOS_COMPOSITOR") == "x11":
		check(root.get_node("Kiosk").focused_window() == root.get_node("Kiosk").Focus.SHELL, "Openbox gives actual foreground focus to home")
	launcher.launch(entry)
	await wait_app(launcher)
	check(launcher.app_on_screen() and launcher._pid == pid, "real app resumes without respawn")
	if OS.get_environment("MARWANOS_COMPOSITOR") == "x11":
		check(root.get_node("Kiosk").focused_window() == root.get_node("Kiosk").Focus.ELSEWHERE, "Openbox gives actual foreground focus to app")
	check(root.get_node("Kiosk").focus_app_keyboard(), "typing targets real app keyboard focus")
	for cycle in 3:
		await press(JOY_BUTTON_GUIDE)
		await press(JOY_BUTTON_DPAD_DOWN)
		await press(JOY_BUTTON_DPAD_DOWN) # Audio -> Minimize.
		await press(JOY_BUTTON_A)
		await create_timer(0.7).timeout
		check(screen.visible and launcher.is_minimized() and OS.is_process_running(pid), "repeat %d preserves minimized process" % cycle)
		if OS.get_environment("MARWANOS_COMPOSITOR") == "x11":
			check(root.get_node("Kiosk").focused_window() == root.get_node("Kiosk").Focus.SHELL, "repeat %d focuses home" % cycle)
		launcher.launch(entry)
		await wait_app(launcher)
		check(launcher.app_on_screen() and launcher._pid == pid, "repeat %d resumes original process" % cycle)
	await press(JOY_BUTTON_GUIDE)
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_DPAD_DOWN) # Minimize -> Close.
	await press(JOY_BUTTON_A)
	for tick in 80:
		if not launcher.is_busy():
			break
		await create_timer(0.25).timeout
	check(not launcher.is_busy() and screen.visible, "managed close ends real runtime and restores home")
	check(not FileAccess.file_exists(installs.home.path_join("running/" + str(entry.recipe_id) + ".json")), "real runtime record removed")
	print("Real Windows shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
