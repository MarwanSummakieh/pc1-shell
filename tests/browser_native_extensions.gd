extends SceneTree

## Run on an isolated X11 display with the pinned CEF payload installed.
var failures := 0
var web: Control
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
func wait_closed() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while web._view.is_extension_window_open() and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	await process_frame
	await process_frame
func _run() -> void:
	# The bench's physical controller may be in use by its live game. Isolated
	# UI tests drive their own events and must not react to that controller.
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	web = load("res://src/browser_screen.gd").new()
	root.add_child(web)
	await create_timer(2).timeout
	web._open_extensions()
	await create_timer(4).timeout
	check(web._extension_active and web._view.is_extension_window_open(), "Chromium's extension manager opens beside the current page")
	check(is_instance_valid(web._extension_toolbar) and web._extension_toolbar.visible, "extension panel controls are visible")
	check(web._extension_toolbar.size == Vector2i(760, 104) and web._extension_toolbar.position == Vector2i(840, 0), "extension controls occupy only the right side")
	var handle: int = web._view.get_extension_panel_handle()
	var geometry: Array = []
	OS.execute("/usr/bin/xdotool", ["getwindowgeometry", "--shell", str(handle)], geometry)
	check("".join(geometry).contains("X=840") and "".join(geometry).contains("WIDTH=760"), "native content stays inside the side panel")
	check(web._tabs.size() == 1 and web._is_start_page(), "opening extensions preserves the underlying browser tab")
	check(not web.is_processing_unhandled_input(), "embedded page does not receive panel input")
	var capture := OS.get_environment("PC1_UI_CAPTURE_DIR")
	if not capture.is_empty():
		OS.execute("/usr/bin/import", ["-window", "root", capture.path_join("native-extension-manager.png")])
	web._extension_command("installed")
	await create_timer(1).timeout
	check(web._menu != null and web._menu_purpose == "extension_apps", "installed extensions are listed in the side panel")
	var entries: Array = load("res://src/browser_extensions.gd").installed_entries()
	check(not entries.is_empty(), "the installed test extension has an accessible action page")
	if not entries.is_empty():
		web._menu_chosen(str(entries[0].id))
		await create_timer(12).timeout
		check(web._view.get_extension_page_url() == entries[0].url, "installed extension opens its actual action page inside the panel")
	if not capture.is_empty(): OS.execute("/usr/bin/import", ["-window", "root", capture.path_join("native-extension-actions.png")])
	web._extension_command("type")
	await process_frame
	check(root.get_node("TextInput").is_open() and web._extension_pad.paused, "controller keyboard opens above the panel and pauses pointer input")
	if not capture.is_empty(): OS.execute("/usr/bin/import", ["-window", "root", capture.path_join("native-extension-keyboard.png")])
	root.get_node("TextInput").close()
	await process_frame
	await process_frame
	check(not web._extension_pad.paused, "closing the keyboard restores panel pointer input")
	# A real X11 click checks stacking and native-window hit testing too.
	OS.execute("/usr/bin/xdotool", ["mousemove", "1540", "26", "click", "1"])
	await wait_closed()
	check(not web._extension_active and web.is_processing_unhandled_input(), "Close dismisses the extension panel and restores browser input")
	check(root.gui_get_focus_owner() != null and web._is_start_page(), "returning to the browser restores its native search focus")
	web.open_url("https://chromewebstore.google.com/category/extensions")
	await create_timer(3).timeout
	check(web._view.is_extension_window_open(), "store URLs typed into the address bar route to the safe native installer")
	web.suspend_surface()
	await wait_closed()
	check(not web._view.is_extension_window_open(), "leaving the browser also closes its extension window")
	root.remove_child(web)
	web.queue_free()
	await create_timer(1).timeout
	print("Native extension window checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
