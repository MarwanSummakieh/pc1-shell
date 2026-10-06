extends SceneTree

var failures := 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func press(button: int) -> void:
	var router := root.get_node("ControllerRouter")
	var buttons: Array = router._buttons.duplicate()
	buttons[button] = true
	router._apply_state({"connected": true, "name": "Tools fixture controller",
		"buttons": buttons, "axes": router._axes.duplicate()})
	await process_frame
	buttons[button] = false
	router._apply_state({"connected": true, "name": "Tools fixture controller",
		"buttons": buttons, "axes": router._axes.duplicate()})
	await process_frame
	await process_frame

func trigger(axis: int, value: float) -> void:
	var router := root.get_node("ControllerRouter")
	var axes: Array = router._axes.duplicate()
	axes[axis] = value
	router._apply_state({"connected": true, "name": "Tools fixture controller",
		"buttons": router._buttons.duplicate(), "axes": axes})
	await process_frame

func paste_one(source: String, destination: String, cut: bool) -> Dictionary:
	var job = load("res://src/file_transfer.gd").new()
	job.begin([source], destination, cut)
	for _frame in 500:
		if not job.running:
			break
		job.step()
		await process_frame
	if not job.errors.is_empty():
		return {"error": str(job.errors[0])}
	return {"error": "", "name": str(job.completed[0]["name"])} if not job.completed.is_empty() else {"error": "Transfer did not finish"}

func _run() -> void:
	# Feed the real broker-state seam, as controller_shell.gd does. A synthetic
	# native index has no GUID and is correctly evicted by PlayerOne's timer.
	# Only UDP transport is paused; input ownership/reconciliation stay enabled.
	var router := root.get_node("ControllerRouter")
	router.set_process(false)
	router._routed = true
	router._apply_state({"connected": true, "name": "Tools fixture controller",
		"buttons": [false, false, false, false, false, false, false, false,
			false, false, false, false, false, false, false],
		"axes": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]})
	var home := OS.get_environment("PC1_TOOLS_TEST_HOME")
	var shell: Control = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	var files := root.get_node("Files")
	var browser := root.get_node("Browser")
	var installs := root.get_node("WindowsInstall")
	files.open()
	await process_frame
	check(files.is_open() and not shell.visible, "file explorer opens inside shell")
	check(root.gui_get_focus_owner() != null, "file explorer gives controller a focus target")
	browser.open()
	check(not browser.is_open(), "browser cannot steal an open file explorer")
	var screen: Control = files._screen
	var installer_path := home.path_join("source/setup.exe")
	check(load("res://src/file_open.gd").plan("setup.EXE").get("action") == "installer", "EXE files route to Windows installation")
	check(load("res://src/file_open.gd").plan("setup.MSI").get("action") == "installer", "MSI files route to Windows installation")
	installs.available = true
	installs.snapshot = {
		"status": "idle", "detail": "Choose an app to install.", "library": [],
		"recipes": [{"id": "example", "title": "Example", "version": "1", "filename": "setup.exe"}],
		"candidates": [{"id": "local-example", "path": installer_path, "name": "setup.exe", "recipe_id": "example", "location": "Downloads"}],
	}
	screen._on_item_activated({"is_dir": false, "path": installer_path, "name": "setup.exe"}, screen._pane())
	await process_frame
	check(screen._modal_open() and screen._installer != null, "opening an EXE shows the Windows installer inside Files")
	check(str(root.gui_get_focus_owner().get_meta("key", "")) == "local-example", "opened EXE owns installer focus")
	check(not screen._installer._status.text.contains("not supported"), "local setup does not require an approved recipe")
	installs.local_jobs = [{"id": "local-review", "source": installer_path, "status": "select",
		"detail": "Choose the program to add to your library.",
		"choices": [{"id": "drive_c/Program Files/Game.exe", "title": "Game", "detail": "Program Files/Game.exe"}]}]
	installs.changed.emit()
	check(screen._installer._rows[0].get_meta("key") == "local-review.drive_c/Program Files/Game.exe.game", "finished setup offers the installed executable as a game")
	check(screen._installer._rows[1].get_meta("key") == "local-review.drive_c/Program Files/Game.exe.app", "finished setup also offers the executable as an application")
	check(screen._installer._rows[0]._value_text == "Native controller input", "game choice explains its native controller profile")
	check(screen._installer._rows[1]._value_text == "Controller pointer", "application choice explains its pointer profile")
	# Exercise the real controller action and helper argv boundary without
	# registering an application or starting Wine in this disposable UI fixture.
	var old_helper: String = installs.helper
	var helper_path := home.path_join("register-fixture.sh")
	var register_helper := FileAccess.open(helper_path, FileAccess.WRITE)
	register_helper.store_string("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$0.args\"\n")
	register_helper.close()
	FileAccess.set_unix_permissions(helper_path, 448)
	installs.helper = helper_path
	for index in 2:
		DirAccess.remove_absolute(helper_path + ".args")
		screen._installer._rows[index].grab_focus()
		await press(JOY_BUTTON_A)
		for attempt in 10:
			if FileAccess.file_exists(helper_path + ".args"):
				break
			await create_timer(0.02).timeout
		var expected_mode := "gamepad" if index == 0 else "pointer"
		check(FileAccess.file_exists(helper_path + ".args"), "controller choice starts the registration helper")
		if FileAccess.file_exists(helper_path + ".args"):
			check(FileAccess.get_file_as_string(helper_path + ".args") == "register\nlocal-review\ndrive_c/Program Files/Game.exe\n" + expected_mode + "\n",
				"controller registration preserves the chosen executable and " + expected_mode + " profile")
	installs.helper = old_helper
	var generic_entry := {"id": "local-test", "title": "Setup", "state": "installed", "input_mode": "pointer"}
	screen._installer._on_launch_started(generic_entry)
	check(not screen.visible, "file list hides while Windows setup owns the display")
	screen._installer._on_launch_finished(generic_entry)
	check(screen.visible and root.gui_get_focus_owner() != null, "setup return restores Files and controller focus")
	installs.local_jobs = []
	await press(JOY_BUTTON_B)
	check(screen._installer == null and files.is_open(), "Back returns from installer to Files")
	var source := home.path_join("source/example.txt")
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_string("Keep this content")
	file.close()
	var copied: Dictionary = await paste_one(source, home.path_join("destination"), false)
	check(str(copied.get("error", "")).is_empty(), "copy succeeds")
	check(FileAccess.get_file_as_string(home.path_join("destination/example.txt")) == "Keep this content", "copy preserves content")
	var duplicate: Dictionary = await paste_one(source, home.path_join("destination"), false)
	check(duplicate.get("name") == "example (copy).txt", "copy collision preserves existing file")
	var recursive: Dictionary = await paste_one(home.path_join("source"), home.path_join("source/child"), false)
	check(not str(recursive.get("error", "")).is_empty(), "folder cannot be copied into itself")
	var moved: Dictionary = await paste_one(source, home.path_join("destination"), true)
	check(str(moved.get("error", "")).is_empty() and not FileAccess.file_exists(source), "move transfers source")
	check(screen._clean_name("../escape") == "", "rename rejects traversal")
	var cross: Dictionary = await paste_one(home.path_join("with-link"), OS.get_environment("PC1_TOOLS_CROSS_HOME"), true)
	check(str(cross.get("error", "")).contains("contains links"), "cross-filesystem move reports a skipped link")
	check(FileAccess.get_file_as_string(OS.get_environment("PC1_TOOLS_CROSS_HOME").path_join("with-link/original.txt")) == "Original data\n", "cross-filesystem move copies regular files before retaining source")
	check(FileAccess.file_exists(home.path_join("with-link/original.txt")) and FileAccess.file_exists(home.path_join("with-link/link.txt")), "incomplete cross-filesystem move preserves original and link")
	var file_keyboard_checks = load(get_script().resource_path.get_base_dir().path_join("file_keyboard_checks.gd")).new()
	await file_keyboard_checks.run(self, screen, home, check)
	screen._open_browser(screen._pane(), home.path_join("destination/example.txt"), "example.txt")
	await process_frame
	check(screen._modal_open() and root.gui_get_focus_owner() == null, "document browser releases file-list focus")
	await press(JOY_BUTTON_BACK)
	check(screen._browser == null and files.is_open(), "Share closes document and returns to files")
	files.close()
	await process_frame
	await process_frame
	check(shell.visible, "closing files restores home")
	# Reach the new tools from the controller-operated top bar.
	var buttons: Array = shell._bar_buttons
	check(buttons[buttons.size() - 3]._kind == "browser", "Browser uses its own top-bar icon")
	buttons[buttons.size() - 3].grab_focus() # Browser, then Power and status.
	await press(JOY_BUTTON_A)
	check(browser.is_open() and not shell.visible, "controller opens browser from bar")
	var web: Control = browser._screen
	check(web.address_url("example.org") == "https://example.org", "address defaults to HTTPS")
	check(web.address_url("two words").contains("q=two%20words"), "words become a search")
	check(web.address_url("javascript:alert(1)") == "", "address rejects executable scheme")
	await press(JOY_BUTTON_X)
	check(web._keyboard != null, "controller opens address keyboard")
	await press(JOY_BUTTON_B)
	check(web._keyboard == null and browser.is_open(), "back closes keyboard only")
	await press(JOY_BUTTON_START)
	check(web._menu != null, "controller opens browser options")
	await press(JOY_BUTTON_B)
	await press(JOY_BUTTON_BACK)
	check(not browser.is_open() and shell.visible, "Share returns home even without browser engine")
	check(root.gui_get_focus_owner() != null, "return restores controller focus")
	var keyboard: Control = load("res://src/keyboard.gd").new()
	keyboard.initial_text = "cat"
	keyboard.masked = false
	root.add_child(keyboard)
	await process_frame
	check(keyboard._panel.get_global_rect().position.x > root.size.x / 2.0, "keyboard occupies the side, leaving the center clear")
	await press(JOY_BUTTON_LEFT_SHOULDER)
	await press(JOY_BUTTON_X)
	keyboard._insert("o")
	check(keyboard._text == "cot", "shoulder moves caret and Square deletes existing text")
	await press(JOY_BUTTON_Y)
	check(keyboard._text == "co t", "Triangle inserts a space at the caret")
	await trigger(JOY_AXIS_TRIGGER_LEFT, 0.8)
	await trigger(JOY_AXIS_TRIGGER_LEFT, 0.9)
	check(keyboard._flat[10].text == "Q", "holding L2 toggles shift only once")
	await trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await trigger(JOY_AXIS_TRIGGER_LEFT, 0.8)
	check(keyboard._flat[10].text == "q", "a second L2 press returns to lowercase")
	var submissions: Array = []
	keyboard.submitted.connect(func(value: String): submissions.append(value))
	await trigger(JOY_AXIS_TRIGGER_RIGHT, 0.8)
	await trigger(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	check(submissions == ["co t"], "holding R2 confirms the draft only once")
	await trigger(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
	root.remove_child(keyboard)
	keyboard.queue_free()
	keyboard = load("res://src/keyboard.gd").new()
	keyboard.input_context = "numeric"
	root.add_child(keyboard)
	await process_frame
	check(keyboard._flat.size() == 15 and root.gui_get_focus_owner().text == "1", "numeric context opens a number pad")
	root.remove_child(keyboard)
	keyboard.queue_free()
	print("Tools shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
