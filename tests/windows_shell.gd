extends SceneTree

# Run with the pinned Godot editor, --headless --path shell --script this file.
# Controller events exercise the actual screen. Worker/compositor state is a
# fixture; the Python suite and real-runtime run verify those other boundaries.
var failures := 0
var home := ""
var screen: Control


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)


func publish(status: String, library: Array = []) -> void:
	var file := FileAccess.open(home.path_join("state.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"heartbeat": Time.get_unix_time_from_system(), "status": status,
		"detail": status, "job_id": "current-job", "library": library,
		"recipes": [{"id": "example", "title": "Example", "version": "1", "filename": "setup.exe"}],
		"candidates": [],
	}))
	file.close()
	root.get_node("WindowsInstall")._poll()


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


func _run() -> void:
	# A synthetic controller has no OS GUID; assign its fixture identity.
	root.get_node("PlayerOne").device = 0
	var installs := root.get_node("WindowsInstall")
	var launcher := root.get_node("Launcher")
	home = installs.home
	DirAccess.make_dir_recursive_absolute(home.path_join("requests"))
	publish("idle")
	screen = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	await press(JOY_BUTTON_DPAD_RIGHT) # Settings -> Install on an empty rail.
	await press(JOY_BUTTON_A)
	check(installs.is_open(), "controller opens installation from home")
	check(not screen.visible, "home hides behind installation")
	check(str(root.gui_get_focus_owner().get_meta("key", "")) == "download.example", "first installer owns focus")
	await press(JOY_BUTTON_A)
	var requests := DirAccess.get_files_at(home.path_join("requests"))
	check(requests.size() == 1, "controller writes one installation request")
	if requests.size() == 1:
		var value: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(home.path_join("requests").path_join(requests[0])))
		check(value.get("verb") == "install" and value.get("recipe_id") == "example", "request names selected recipe")
	publish("installing")
	await press(JOY_BUTTON_A)
	check(DirAccess.get_files_at(home.path_join("requests")).size() == 1, "repeated accept cannot queue duplicate install")
	await press(JOY_BUTTON_B)
	check(not installs.is_open() and screen.visible, "back returns home during installation")
	check(installs.is_busy(), "back does not cancel installation")
	installs.open()
	await process_frame
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_A)
	check(DirAccess.get_files_at(home.path_join("requests")).size() == 2, "controller can cancel active job")
	publish("cancelled")
	await press(JOY_BUTTON_B)
	var entry := {"id": "managed.example", "recipe_id": "example", "title": "Example",
		"state": "installed", "exec": ["/bin/sleep", "60"], "icon": "", "subtitle": "Windows app"}
	publish("done", [entry])
	root.get_node("Installed")._poll()
	await process_frame
	check(screen._cards.size() == 1, "committed installation creates a library card")
	screen._cards[0].grab_focus()
	await press(JOY_BUTTON_A)
	check(launcher.is_busy() and not screen.visible, "controller launches library entry")
	launcher._watched_seconds = launcher.WINDOW_DEADLINE_SECONDS
	launcher._check_window()
	check(launcher._splash._failed, "missing compositor signal offers controller recovery")
	# Headless Godot has no compositor. Supply the successful window handoff.
	launcher._app_is_up()
	await press(JOY_BUTTON_BACK) # Share is the shell's alternate Home binding.
	check(screen._overlay != null, "controller opens overlay during application")
	check(not root.get_node("ControllerRouter")._app_input, "overlay neutralizes application controller input")
	await press(JOY_BUTTON_B)
	check(screen._overlay == null and launcher.is_busy(), "back resumes application")
	await press(JOY_BUTTON_BACK)
	await press(JOY_BUTTON_DPAD_DOWN) # Type -> Audio.
	await press(JOY_BUTTON_DPAD_DOWN) # Audio -> Minimize.
	var running_pid: int = launcher._pid
	await press(JOY_BUTTON_A)
	check(launcher.is_minimized() and not launcher.is_busy() and screen.visible, "minimize restores home without ending app")
	check(OS.is_process_running(running_pid), "minimize preserves original process")
	check(screen._overlay == null and not launcher.app_on_screen(), "minimize releases overlay and app input")
	launcher._handoff_seen = true
	launcher._handoff_shell_ticks = 2
	screen._open_process_menu()
	await process_frame
	check(screen._process_menu != null and screen._process_menu._rows.size() >= 2, "process menu offers background app resume and close")
	await press(JOY_BUTTON_A)
	check(screen._process_menu == null and launcher.is_busy() and launcher._pid == running_pid, "process menu resumes original process and releases focus")
	check(not launcher._handoff_seen and launcher._handoff_shell_ticks == 0, "resume restarts the handoff focus check")
	launcher._app_is_up()
	await press(JOY_BUTTON_BACK)
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_DPAD_DOWN) # Audio -> Minimize.
	await press(JOY_BUTTON_A)
	screen._cards[0].grab_focus()
	await press(JOY_BUTTON_A)
	check(launcher.is_busy() and launcher._pid == running_pid, "library resumes original process without relaunch")
	launcher._app_is_up()
	await press(JOY_BUTTON_BACK)
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_DPAD_DOWN) # Audio -> Minimize.
	await press(JOY_BUTTON_DPAD_DOWN) # Minimize -> Close.
	await press(JOY_BUTTON_A)
	await create_timer(0.7).timeout
	check(not launcher.is_busy() and screen.visible, "controller closes app and restores home")
	check(root.gui_get_focus_owner() == screen._cards[0], "library focus restored after exit")
	await press(JOY_BUTTON_START)
	check(installs._confirmation != null, "library Options opens removal confirmation")
	check(root.gui_get_focus_owner() == installs._confirmation._rows[0], "removal defaults to Cancel")
	var before_remove := DirAccess.get_files_at(home.path_join("requests")).size()
	await press(JOY_BUTTON_B)
	check(installs._confirmation == null and screen.visible, "Back cancels removal and restores home")
	check(DirAccess.get_files_at(home.path_join("requests")).size() == before_remove, "cancel removes no application")
	await press(JOY_BUTTON_START)
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_A)
	check(DirAccess.get_files_at(home.path_join("requests")).size() == before_remove + 1, "confirmed controller removal writes one request")
	var owner := root.gui_get_focus_owner()
	if owner != null:
		owner.release_focus()
	installs.guided_finished.emit()
	check(root.gui_get_focus_owner() == screen._cards[0], "a recovered setup ending restores controller focus to home")
	print("Windows shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
