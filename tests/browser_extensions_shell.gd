extends SceneTree

class NativeFixture extends Control:
	var active := false
	var fail_open := false
	var selections: Array[bool] = []
	var commands: Array[String] = []
	var panel_bounds := Rect2()
	func set_extension_panel_rect(bounds: Rect2) -> void: panel_bounds = bounds
	func open_extensions(manage: bool) -> bool:
		selections.append(manage)
		active = not fail_open
		return active
	func is_extension_window_open() -> bool: return active
	func extension_command(command: String) -> void:
		commands.append(command)
		if command == "close": active = false

var failures := 0
var web: Control
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
func capture(filename: String) -> void:
	var directory := OS.get_environment("PC1_UI_CAPTURE_DIR")
	if directory.is_empty(): return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(filename))
func _run() -> void:
	for mapped_action in InputMap.get_actions():
		for event in InputMap.action_get_events(mapped_action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(mapped_action, event)
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	web = load("res://src/browser_screen.gd").new()
	root.add_child(web)
	await process_frame
	await process_frame
	web._chrome_action("extensions")
	check(web._menu_purpose == "extension_error", "missing native engine shows an actionable error")
	web._close_menu()
	var fixture := NativeFixture.new()
	web.add_child(fixture)
	web._view = fixture
	var tab_count: int = web._tabs.size()
	web._open_extensions()
	check(fixture.selections == [true] and web._extension_active, "puzzle button opens extension management directly in the panel")
	check(web._menu == null and web._tabs.size() == tab_count, "extensions preserve the current page and tab count")
	check(fixture.panel_bounds.position.y == 104 and fixture.panel_bounds.size.y > 0, "panel content leaves room for its compact controls")
	check(is_instance_valid(web._extension_overlay), "panel blocks clicks reaching the page behind it")
	check(not web.is_processing_unhandled_input(), "extension panel owns browser input")
	await capture("browser-extensions-1920.png")
	fixture.active = false
	web._sync_extension_window()
	check(web.is_processing_unhandled_input() and root.gui_get_focus_owner() != null, "closing native extensions restores browser input and focus")
	web._open_extensions()
	check(fixture.selections == [true, true], "reopening uses Chromium's persistent extension registry")
	fixture.extension_command("installed")
	check(fixture.commands[-1] == "installed", "installed extensions can be opened from the panel controls")
	web.suspend_surface()
	check(not fixture.active and fixture.commands[-1] == "close", "leaving the browser closes its native extension window")
	web.resume_surface()
	fixture.fail_open = true
	web._open_extensions()
	check(web._menu_purpose == "extension_error" and not web._extension_active, "failed native window creation keeps the shell usable")
	web._close_menu()
	root.size = Vector2i(960, 720)
	await process_frame
	web._open_extensions()
	await capture("browser-extensions-960.png")
	check(web._menu._panel.get_global_rect().end.x <= 960, "extension menu fits a narrow screen")
	var toolbar = load("res://src/browser_extension_toolbar.gd")
	for viewport in [Vector2i(1920, 1080), Vector2i(960, 720), Vector2i(400, 600)]:
		var bounds: Rect2i = toolbar.panel_rect(Rect2i(Vector2i.ZERO, viewport))
		check(bounds.end == viewport and bounds.position.x >= 0 and bounds.size.x <= 760, "extension panel stays attached to the right edge at %dpx" % viewport.x)
	web._close_menu()
	root.remove_child(web)
	web.queue_free()
	await process_frame
	print("Browser extension shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
