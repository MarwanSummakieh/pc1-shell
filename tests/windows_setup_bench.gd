extends SceneTree

## Optional real FDM acceptance on the physical bench. Run with an isolated
## MARWANOS_WINDOWS_HOME, the real helper/bridge, and the bench's DISPLAY.
var installs: Node
var wizard: Control
var evidence := ""
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func press(button: int) -> void:
	root.get_node("PlayerOne").set_routed_controller(true, root.get_node("ControllerRouter").DEVICE, "Bench fixture")
	var event := InputEventJoypadButton.new()
	event.device = root.get_node("ControllerRouter").DEVICE
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(0.08).timeout
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await create_timer(0.4).timeout

func wait_text(text: String, timeout: float = 60.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(wizard):
			wizard._refresh()
			for control in wizard._page.get("controls", []):
				if text in str(control.get("text", "")):
					return true
		await create_timer(0.2).timeout
	return false

func choose(text: String) -> bool:
	var target := ""
	for control in wizard._page.get("controls", []):
		if control.get("kind") in ["button", "check", "radio", "edit", "combo", "list"] and text in str(control.get("text", "")).replace("&", ""):
			target = str(int(control.get("id", 0)))
			break
	if target.is_empty():
		check(false, "find control " + text)
		return false
	# Traverse the production focus chain using actual joypad events.
	wizard._rows[0].grab_focus()
	for attempt in wizard._rows.size() + 2:
		var owner := root.gui_get_focus_owner()
		if owner != null and str(owner.get_meta("key", "")) == target:
			await press(JOY_BUTTON_A)
			return true
		var footer_target := false
		for row in wizard._footer_rows:
			if str(row.get_meta("key", "")) == target:
				footer_target = true
		await press(JOY_BUTTON_DPAD_RIGHT if footer_target and wizard._footer_rows.has(owner) else JOY_BUTTON_DPAD_DOWN)
	check(false, "controller reaches " + text)
	return false

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name + ".png"))
	var file := FileAccess.open(evidence.path_join(name + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(wizard._page, "\t"))
	file.close()

func _run() -> void:
	installs = root.get_node("WindowsInstall")
	# Keep the physical session's controller broker attached to its own shell.
	var router := root.get_node("ControllerRouter")
	router.set_process(false)
	router._socket.close()
	router._routed = true
	evidence = OS.get_environment("PC1_SETUP_EVIDENCE")
	DirAccess.make_dir_recursive_absolute(evidence)
	var main: Control = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(main)
	await process_frame
	installs.guided_install("/home/player/fdm_x64_setup.exe")
	wizard = installs._guided_screen
	if not is_instance_valid(wizard):
		check(false, "setup screen starts")
		quit(1)
		return
	var started := await wait_text("Install for", 120)
	check(started, "real FDM install-mode page")
	if not started:
		installs.stop_guided()
		quit(1)
		return
	await capture("01-mode")
	var mode: Dictionary = {}
	for control in wizard._page.get("controls", []):
		if control.get("kind") == "button" and "all users" in str(control.get("text", "")):
			mode = control
	wizard._send(mode, 1, "", int(wizard._page.page) + 1)
	await create_timer(1).timeout
	wizard._refresh()
	check(not str(wizard._page.get("error", "")).is_empty() and await wait_text("Install for", 2), "stale page actions are rejected by the real bridge")
	await choose("all users")
	check(await wait_text("Select the language"), "real FDM language page")
	await capture("02-language")
	# Select a different language and then English, exercising the actual combo.
	await choose("English")
	check(wizard._modal != null and wizard._modal.items.size() > 20, "all FDM language choices are available")
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_A) # Dansk, from the first option.
	await create_timer(1).timeout
	check(await wait_text("Dansk", 5), "language choice reaches the actual installer")
	await choose("Dansk")
	for i in 5:
		await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_A)
	await create_timer(1).timeout
	check(await wait_text("English", 5), "English can be restored")
	await choose("OK")
	check(await wait_text("Select Destination Location"), "real FDM destination page")
	await capture("03-destination")
	await choose("C:\\Program Files")
	check(wizard._modal != null and wizard._modal.initial_text.begins_with("C:\\Program Files"), "real destination opens in the controller keyboard")
	await press(JOY_BUTTON_B) # Keep the actual default destination.
	await choose("Next")
	check(await wait_text("Select Start Menu Folder"), "real FDM Start Menu page")
	await press(JOY_BUTTON_B)
	check(await wait_text("Select Destination Location"), "controller Back returns to the actual previous page")
	await choose("Next")
	check(await wait_text("Select Start Menu Folder"), "can advance again after Back")
	await choose("Next")
	check(await wait_text("Select Additional Tasks"), "real FDM additional-task page")
	await capture("04-tasks")
	var list: Dictionary = {}
	for control in wizard._page.get("controls", []):
		if control.get("kind") == "list":
			list = control
	check(not list.is_empty() and wizard._images.size() == 1, "custom checkbox panel is visible")
	if not list.is_empty():
		# Empty text matches the first control; use its explicit row for this widget.
		for row in wizard._rows:
			if str(row.get_meta("key", "")) == str(int(list.id)):
				row.grab_focus()
		await press(JOY_BUTTON_A)
		await press(JOY_BUTTON_A) # Toggle the desktop shortcut off.
		await capture("05-task-toggled")
		await press(JOY_BUTTON_A) # Restore it for this test install.
		await press(JOY_BUTTON_B)
	await choose("Next")
	check(await wait_text("Ready to Install"), "real FDM summary page")
	await capture("06-summary")
	await choose("Install")
	check(await wait_text("Completing", 120), "real FDM installation completes")
	await capture("07-complete")
	# Avoid starting an application on the wizard's isolated display.
	for control in wizard._page.get("controls", []):
		if control.get("kind") == "check" and "Launch" in str(control.get("text", "")) and int(control.get("checked", 0)) != 0:
			await choose("Launch")
	await choose("Finish")
	var deadline := Time.get_ticks_msec() + 30000
	while installs._guided_pid > 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	check(installs._guided_pid <= 0, "Finish returns to PC1 and ends the setup runtime")
	installs._poll_local()
	var job: Dictionary = {}
	for item in installs.local_jobs:
		if item.get("id") == installs.guided_key:
			job = item
	check(job.get("status") == "select", "installed executable choices are discovered")
	var choice: Dictionary = {}
	for item in job.get("choices", []):
		if str(item.get("id", "")).ends_with("/fdm.exe"):
			choice = item
	check(not choice.is_empty(), "the real FDM executable is offered")
	if not choice.is_empty():
		installs.register_local(installs.guided_key, str(choice.id))
		await create_timer(2).timeout
		installs._poll_local()
		var entry: Dictionary = {}
		for item in installs.library():
			if item.get("recipe_id") == installs.guided_key:
				entry = item
		check(not entry.is_empty(), "FDM registers in the library")
		if not entry.is_empty():
			root.get_node("Launcher").launch(entry)
			await create_timer(12).timeout
			check(root.get_node("Launcher").app_on_screen(), "installed FDM launches on the bench display")
			root.get_node("Launcher").close_current()
			await create_timer(6).timeout
	print("Real FDM controller setup checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
