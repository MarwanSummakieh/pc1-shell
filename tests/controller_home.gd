extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print(("PASS: " if value else "FAIL: ") + label)
	if not value:
		failures += 1

func press(button: int) -> void:
	var router := root.get_node("ControllerRouter")
	var buttons: Array = router._buttons.duplicate()
	buttons[button] = true
	router._apply_state({"connected": true, "buttons": buttons, "axes": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]})
	await process_frame
	buttons[button] = false
	router._apply_state({"connected": true, "buttons": buttons, "axes": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]})
	await process_frame
	await process_frame

func _run() -> void:
	var router := root.get_node("ControllerRouter")
	router.set_process(false)
	router._routed = true
	router._apply_state({"connected": true, "name": "Home fixture controller", "buttons": [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]})
	var screen: Control = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	var launcher := root.get_node("Launcher")
	launcher.launch({"id": "fixture.home", "title": "Controller fixture", "kind": "app", "state": "installed", "exec": ["/bin/sleep", "60"]})
	await process_frame
	launcher._app_is_up()
	check(launcher.is_busy() and router._app_input, "foreground application receives controller input")
	await press(JOY_BUTTON_BACK)
	check(screen._overlay == null and router._app_input, "Share keeps application input active without opening the system menu")
	await press(JOY_BUTTON_GUIDE)
	check(screen._overlay != null and not router._app_input, "Guide opens the system menu and neutralizes application input")
	await press(JOY_BUTTON_B)
	check(screen._overlay == null and router._app_input, "Back resumes application input")
	launcher.close_current()
	await create_timer(0.7).timeout
	check(not launcher.is_busy(), "fixture application closes")
	print("Controller Home checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
