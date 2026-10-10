extends SceneTree

var failures := 0
var web: Control

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func wait_title(expected: String) -> bool:
	for attempt in 150:
		if web._view.get_page_title() == expected:
			return true
		await create_timer(0.1).timeout
	return false

func focus_field(y: float, expected_type: String, expected_mode: String = "") -> bool:
	web._close_keyboard()
	# The inset browser window is shorter than the fixture document. Start from
	# its top and scroll each target into the current content viewport.
	web._view.scroll(Vector2(0, 4000))
	await create_timer(0.2).timeout
	var offset := maxf(0, y - web._view.size.y + 100)
	if offset > 0:
		web._view.scroll(Vector2(0, -offset))
		await create_timer(0.2).timeout
	web._view.set_pointer(Vector2(90, y - offset))
	web._click(true)
	await create_timer(0.2).timeout
	check(web._keyboard == null, "field focus waits for click release")
	web._click(false)
	for attempt in 50:
		await create_timer(0.1).timeout
		if web._keyboard != null and web._field_context.get("type", "") == expected_type and web._field_context.get("mode", "") == expected_mode:
			return true
	return false

func _run() -> void:
	if not ClassDB.class_exists("MowserView"):
		push_error("FAIL: Chromium engine not registered")
		quit(1)
		return
	web = load("res://src/browser_screen.gd").new()
	root.add_child(web)
	var fixture := OS.get_environment("PC1_BROWSER_FIXTURE")
	web.open_url("file://" + fixture, "Browser verification")
	check(await wait_title("PC1 browser ready"), "Chromium renders a local page")
	check(web._view.is_engine_running(), "browser engine started")
	var player_one: Node = root.get_node("PlayerOne")
	# This harness injects a controller without registering physical hardware.
	# Stop the hot-plug backstop so it cannot discard that synthetic device while
	# a slower Chromium startup is still completing.
	for child in player_one.get_children():
		if child is Timer:
			child.stop()
	# Poll the same broker state as the appliance. Godot's native joy-axis
	# query does not retain axes for synthetic, unregistered devices.
	var router: Node = root.get_node("ControllerRouter")
	router.set_process(false)
	router._routed = true
	router._apply_state({"connected": true, "axes": [0.0, 0.0, 0.0, 1.0, 0.0, 0.0]})
	check(await wait_title("Right stick scrolled"), "right stick scrolls the page")
	router._apply_state({"connected": false})
	router._routed = false
	router.set_process(true)
	player_one.device = 0
	web._view.load_url("file://" + fixture)
	check(await wait_title("PC1 browser ready"), "page resets after right-stick check")
	await create_timer(0.5).timeout
	check(await focus_field(150, "text"), "focusing a text field opens the keyboard automatically")
	if web._keyboard == null:
		quit(1)
		return
	web._keyboard._insert("Controller text")
	check(await wait_title("Typed:Controller text"), "keyboard text reaches the page before Done")
	check(web._view.get_rect() == web._page_bounds, "floating keyboard preserves the page viewport")
	web._keyboard._on_done()
	await create_timer(0.2).timeout
	check(web._view.get_page_title() == "Typed:Controller text", "Done does not duplicate live text")
	web._open_keyboard()
	web._keyboard._on_backspace()
	check(await wait_title("Typed:Controller tex"), "reopened keyboard deletes existing page text")
	web._keyboard._move_caret(-1)
	web._keyboard._insert("!")
	check(await wait_title("Typed:Controller te!x"), "shoulder cursor edits inside existing page text")
	web._close_keyboard()
	web._view.set_pointer(Vector2(100, 265))
	web._view.click(1, true)
	web._view.click(1, false)
	check(await wait_title("PC1 clicked"), "pointer click activates page button")
	web._view.load_url("file://" + fixture + "#second")
	await create_timer(1.0).timeout
	check(web._view.can_go_back(), "browser records navigation history")
	web._view.go_back()
	await create_timer(1.0).timeout
	check(not web._view.get_page_url().ends_with("#second"), "back returns to previous page")
	check(await focus_field(430, "password"), "password context is detected")
	if web._keyboard != null:
		check(web._keyboard.masked and web._keyboard.live_input, "password stays in the browser's protected field")
		web._keyboard._insert("example-only")
		check(await wait_title("Password length:12"), "password input reaches Chromium")
		check(web._keyboard._text.is_empty(), "shell does not retain live password text")
	check(await focus_field(530, "email"), "email context is detected")
	if web._keyboard != null:
		check(web._keyboard._flat[39].text == ".com" and web._keyboard.done_label == "Next", "email shortcuts and Next follow field context")
		web._keyboard._on_done()
		await create_timer(0.5).timeout
		check(web._keyboard != null and web._keyboard.input_context == "numeric", "Next focuses the following field and updates the keyboard")
	check(web._field_context.get("mode", "") == "numeric", "inputmode selects a numeric keypad")
	if web._keyboard != null:
		check(web._keyboard._flat.size() == 15, "numeric keypad replaces letter grid")
	check(await focus_field(730, "search"), "search context is detected")
	if web._keyboard != null:
		check(web._keyboard.done_label == "Search", "search field labels its explicit submit action")
		web._keyboard._on_done()
		check(await wait_title("Search submitted"), "Search sends Enter only when confirmed")
	await focus_field(150, "text")
	await create_timer(0.6).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OS.get_environment("PC1_BROWSER_SCREENSHOT"))
	root.remove_child(web)
	web.queue_free()
	await create_timer(0.5).timeout
	var files: Control = load("res://src/files_screen.gd").new()
	root.add_child(files)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("PC1_BROWSER_SCREENSHOT").get_base_dir().path_join("files-verified.png"))
	root.remove_child(files)
	files.queue_free()
	print("Browser engine checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
