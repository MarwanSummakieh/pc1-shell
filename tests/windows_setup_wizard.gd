extends SceneTree

var failures := 0
var wizard: Control
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

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

func page(revision: int, controls: Array) -> void:
	var file := FileAccess.open(directory.path_join("page.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "title": "Setup fixture", "page": revision, "controls": controls}))
	file.close()
	wizard._refresh()

func command() -> Array:
	var file := FileAccess.open(directory.path_join("action.bin"), FileAccess.READ)
	if file == null:
		return []
	var result := [file.get_32(), file.get_64(), file.get_32()]
	var length := file.get_32()
	result.append(file.get_buffer(length).get_string_from_utf8())
	file.close()
	DirAccess.remove_absolute(directory.path_join("action.bin"))
	wizard._pending_until = 0
	return result

func _run() -> void:
	directory = root.get_node("WindowsInstall").home.path_join("setup-ui/local-fixture")
	DirAccess.make_dir_recursive_absolute(directory)
	var source_screen: Control = load("res://src/windows_install_screen.gd").new()
	source_screen.source_path = "/fixture/setup.exe"
	source_screen.source_name = "setup.exe"
	root.add_child(source_screen)
	wizard = load("res://src/windows_setup_wizard.gd").new()
	wizard.job_key = "local-fixture"
	root.add_child(wizard)
	root.get_node("WindowsInstall")._guided_screen = wizard
	await process_frame
	var next := {"id": 11, "kind": "button", "text": "&Next", "enabled": true}
	var back := {"id": 12, "kind": "button", "text": "&Back", "enabled": true}
	page(42, [next, back])
	var installs := root.get_node("WindowsInstall")
	installs.local_jobs = [{"id": "local-running", "source": "/fixture/setup.exe", "status": "installing"}]
	source_screen._refresh()
	check(wizard._rows.has(root.gui_get_focus_owner()), "background job updates cannot steal focus from the setup wizard")
	installs._guided_pid = OS.get_process_id()
	installs._guided_child = false
	installs._guided_owner_start = installs._process_start(OS.get_process_id())
	check(not installs._guided_owner_start.is_empty(), "process identity is read from procfs")
	installs._poll()
	check(installs._guided_screen == wizard and not wizard.is_queued_for_deletion(), "a recovered live setup remains open without child-process polling")
	installs._guided_pid = -1
	await press(JOY_BUTTON_A)
	check(command() == [42, 11, 1, ""], "A invokes only the selected live control")
	await press(JOY_BUTTON_B)
	check(command() == [42, 12, 1, ""], "B invokes Back rather than cancelling setup")
	var edit := {"id": 14, "kind": "edit", "text": "C:\\Apps & Games", "enabled": true}
	page(43, [edit, next])
	wizard._rows[0].grab_focus()
	await press(JOY_BUTTON_A)
	check(wizard._modal != null and wizard._modal.initial_text == "C:\\Apps & Games", "edit opens the controller keyboard with the exact current value")
	page(44, [edit, next])
	wizard._modal.submitted.emit("C:\\New folder")
	check(command() == [43, 14, 2, "C:\\New folder"], "text submission carries the original revision so changed pages are rejected")
	wizard._refresh()
	var combo := {"id": 16, "kind": "combo", "text": "English", "options": ["English", "Dansk"], "enabled": true}
	page(45, [combo, next])
	wizard._rows[0].grab_focus()
	await press(JOY_BUTTON_A)
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_A)
	check(command() == [45, 16, 3, "1"], "controller selects a real dropdown option")
	var list := {"id": 18, "kind": "list", "text": "", "enabled": true}
	page(46, [list, next])
	wizard._rows[0].grab_focus()
	await press(JOY_BUTTON_A)
	await press(JOY_BUTTON_DPAD_DOWN)
	check(command() == [46, 18, 4, "down"], "custom options receive controller navigation")
	await press(JOY_BUTTON_A)
	check(command() == [46, 18, 4, "space"], "A toggles the actual custom checkbox")
	await press(JOY_BUTTON_B)
	check(wizard._list_edit.is_empty() and command().is_empty(), "B leaves option editing without advancing or cancelling")
	var unknown := {"id": 20, "kind": "unsupported", "enabled": true}
	page(47, [unknown, next])
	check(wizard._rows[0].disabled, "unsupported choices block advancing rather than silently skipping options")
	page(48, [{"id": 22, "kind": "text", "text": "License & terms\n".repeat(100)}])
	wizard._rows[0].grab_focus()
	await press(JOY_BUTTON_A)
	check(wizard._read_scroll.get_child(0).text == "License & terms\n".repeat(100), "long license text is preserved in full")
	await press(JOY_BUTTON_B)
	check(wizard._modal == null, "B closes setup-text reading")
	var ram := {"id": 30, "kind": "check", "text": "Limit installer to 2 GB of RAM usage", "checked": 0, "enabled": true}
	var directx := {"id": 31, "kind": "check", "text": "Update DirectX", "checked": 1, "enabled": true}
	var cancel := {"id": 32, "kind": "button", "text": "Cancel", "enabled": true}
	page(49, [{"id": 33, "kind": "text", "text": "Select additional tasks"}, ram, directx, back, next, cancel])
	check(wizard._step.text == "Select additional tasks", "installer page heading stays above its options")
	check(wizard._body_rows.size() == 2 and wizard._footer_rows.size() == 4, "repack choices stay in the content panel and navigation stays in the footer")
	wizard._body_rows[0].grab_focus()
	await press(JOY_BUTTON_A)
	check(command() == [49, 30, 1, ""], "controller toggles the live RAM limit checkbox")
	wizard._body_rows[1].grab_focus()
	await press(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == wizard._footer_rows[0], "Down from the last option reaches installer navigation")
	await press(JOY_BUTTON_DPAD_RIGHT)
	check(root.gui_get_focus_owner() == wizard._footer_rows[1], "Left and Right navigate the installer footer")
	await press(JOY_BUTTON_A)
	check(command() == [49, 11, 1, ""], "footer Next invokes the original installer control")
	page(50, [ram, directx, back, next, cancel])
	check(str(root.gui_get_focus_owner().get_meta("key")) == "11", "live checked-state updates retain the focused footer action")
	await press(JOY_BUTTON_DPAD_UP)
	check(root.gui_get_focus_owner() == wizard._body_rows[-1], "Up from navigation returns to the options")
	var destination := {"id": 34, "kind": "edit", "text": "C:\\Games\\Fixture Game", "destination": true, "enabled": true}
	page(51, [destination, back, next])
	wizard._body_rows[0].grab_focus()
	await press(JOY_BUTTON_A)
	check(wizard._modal.title_text == "Install location" and wizard._modal.initial_text == "C:\\Games\\Fixture Game", "destination is named and editable with the controller")
	await press(JOY_BUTTON_B)
	var music := {"id": 35, "kind": "button", "text": "Installer music", "music": true, "enabled": true}
	page(52, [ram, music, next, cancel])
	check(wizard._footer_rows[0]._name_text == "Installer music", "icon-only speaker has a labelled controller footer action")
	wizard._footer_rows[0].grab_focus()
	await press(JOY_BUTTON_A)
	check(command() == [52, 35, 1, ""], "A toggles the real installer speaker without advancing setup")
	await press(JOY_BUTTON_DPAD_RIGHT)
	check(str(root.gui_get_focus_owner().get_meta("key")) == "11", "music participates in the same controller footer navigation")
	page(53, [unknown, music, next, cancel])
	check(not wizard._footer_rows[0].disabled and wizard._footer_rows[1].disabled, "music can be muted on an unsupported page while advancing stays blocked")
	var logo := {"id": 40, "kind": "unsupported", "class": "ThemeStaticOwnerDraw", "text": "", "enabled": true}
	var agreement := {"id": 41, "kind": "check", "text": "I &agree to the license terms and conditions", "checked": 0, "enabled": true}
	var install := {"id": 42, "kind": "button", "text": "&Install", "enabled": false}
	var close := {"id": 43, "kind": "button", "text": "&Close", "enabled": true}
	var license := {"id": 44, "kind": "text", "text": "Microsoft runtime license terms\n".repeat(30)}
	page(54, [logo, license, agreement, install, close])
	check(not wizard._status.visible and not wizard._body_rows[1].disabled, "WiX logo cannot disable the real license agreement checkbox")
	wizard._body_rows[0].grab_focus()
	await press(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == wizard._body_rows[1], "D-pad reaches agreement after license text")
	await press(JOY_BUTTON_A)
	check(command() == [54, 41, 1, ""], "A toggles the real Microsoft agreement control")
	agreement.checked = 1
	install.enabled = true
	page(55, [logo, license, agreement, install, close])
	await press(JOY_BUTTON_DPAD_DOWN)
	check(str(root.gui_get_focus_owner().get_meta("key")) == "42", "D-pad reaches Install when the native agreement enables it")
	await press(JOY_BUTTON_A)
	check(command() == [55, 42, 1, ""], "A invokes Microsoft Install")
	await press(JOY_BUTTON_DPAD_RIGHT)
	check(str(root.gui_get_focus_owner().get_meta("key")) == "43", "D-pad Right reaches Microsoft Close")
	await press(JOY_BUTTON_A)
	check(command() == [55, 43, 1, ""], "A invokes Microsoft Close")
	page(56, [unknown, agreement, install, close])
	check(not wizard._body_rows[0].disabled and wizard._footer_rows[0].disabled and not wizard._footer_rows[1].disabled, "real unsupported choices keep agreement and Close reachable while Install stays blocked")
	root.get_node("WindowsInstall").background_guided()
	check(not wizard.visible and source_screen._rows.has(root.gui_get_focus_owner()), "Return to Files restores installer focus while setup stays available")
	root.get_node("WindowsInstall").resume_guided()
	check(wizard.visible and wizard._rows.has(root.gui_get_focus_owner()), "Resume restores setup focus")
	root.get_node("WindowsInstall")._guided_screen = null
	print("Windows setup wizard checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
