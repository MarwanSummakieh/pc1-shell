extends SceneTree

var failures := 0
var web: Control
var router: Node
var buttons := []
var axes := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
func state() -> void:
	router._apply_state({"connected": true, "name": "Panel test pad", "buttons": buttons, "axes": axes})
func pointer() -> Vector2i:
	var output: Array = []
	OS.execute("xdotool", ["getmouselocation", "--shell"], output)
	var values := {}
	for line in "".join(output).split("\n"):
		var parts := line.split("=")
		if parts.size() == 2: values[parts[0]] = int(parts[1])
	return Vector2i(values.get("X", 0), values.get("Y", 0))
func _run() -> void:
	router = root.get_node("ControllerRouter")
	router.set_process(false)
	router._routed = true
	buttons.resize(15)
	buttons.fill(false)
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion: event.device = 15
	state()
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	var fixture := OS.get_environment("PC1_EXTENSION_FIXTURE_PATH")
	var config: Control = ClassDB.instantiate("MowserView")
	check(config.set_extension_paths(PackedStringArray([fixture])), "controller fixture registers")
	config.free()
	web = load("res://src/browser_screen.gd").new()
	root.add_child(web)
	await create_timer(2).timeout
	web._open_extensions()
	await create_timer(3).timeout
	var initial := pointer()
	check(initial.x >= 840 and initial.y >= 104, "opening the panel places the pointer inside its content")
	web._extension_command("installed")
	await create_timer(0.3).timeout
	check(web._extension_pad.paused and web._menu != null, "extension chooser owns controller input instead of the native pointer bridge")
	buttons[JOY_BUTTON_A] = true
	state()
	await create_timer(0.1).timeout
	buttons[JOY_BUTTON_A] = false
	state()
	await create_timer(0.5).timeout
	check(web._menu == null and not web._extension_pad.paused, "controller Cross opens the selected installed extension")
	var entry := {"uid": web._view.get_active_extension_paths()[0].get_file()}
	var url: String = load("res://src/browser_extensions.gd").page_url(entry, web._view.get_active_extension_paths())
	check(not url.is_empty() and web._view.open_extension_page(url.replace("setup.html", "popup.html")), "controller fixture opens in native panel")
	await create_timer(3).timeout
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "extension panel exposes a visible native pointer in kiosk mode")
	root.get_node("Kiosk")._assert_display_policy()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "kiosk focus restoration preserves the native panel pointer")
	OS.execute("xdotool", ["mousemove", "900", "145"])
	var before := pointer()
	axes[0] = 1.0
	state()
	await create_timer(0.35).timeout
	axes[0] = 0.0
	state()
	await create_timer(0.15).timeout
	check(pointer().x > before.x + 50, "routed controller moves native pointer while panel owns focus")
	OS.execute("xdotool", ["mousemove", "850", "145"])
	axes[0] = -1.0
	state()
	await create_timer(0.3).timeout
	axes[0] = 0.0
	state()
	await create_timer(0.15).timeout
	check(pointer().x >= 840, "controller pointer stays within the panel and toolbar")
	OS.execute("xdotool", ["mousemove", "960", "145"])
	buttons[JOY_BUTTON_A] = true
	state()
	await create_timer(0.1).timeout
	buttons[JOY_BUTTON_A] = false
	state()
	await create_timer(2).timeout
	check(web._view.get_extension_page_url().ends_with("setup.html"), "controller Cross clicks extension setup button")
	web._close_extension_window()
	await create_timer(1).timeout
	check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "closing the panel restores the console cursor policy")
	print("Extension controller checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
