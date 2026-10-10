extends SceneTree

## Exercise real broker/GUI events, including a held Cross and its release.
var failures := 0
var router: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func button(index: int, pressed: bool) -> void:
	var buttons: Array = router._buttons.duplicate()
	buttons[index] = pressed
	router._apply_state({"connected": true, "name": "Keyboard timing fixture",
		"buttons": buttons, "axes": router._axes.duplicate()})
	await process_frame
	await process_frame

func _run() -> void:
	router = root.get_node("ControllerRouter")
	router.set_process(false)
	router._routed = true
	router._apply_state({"connected": true, "name": "Keyboard timing fixture",
		"buttons": [false, false, false, false, false, false, false, false,
			false, false, false, false, false, false, false],
		"axes": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]})
	for mode in ["draft", "live", "numeric"]:
		var keyboard: Control = load("res://src/keyboard.gd").new()
		keyboard.live_input = mode == "live"
		keyboard.masked = false
		if mode == "numeric": keyboard.input_context = "numeric"
		var inserts: Array = []
		keyboard.text_inserted.connect(func(value: String): inserts.append(value))
		root.add_child(keyboard)
		await process_frame
		await process_frame
		var key: Button = root.gui_get_focus_owner()
		var expected := key.text
		var start := Time.get_ticks_usec()
		await button(JOY_BUTTON_A, true)
		var immediate: bool = inserts == [expected] if mode == "live" else keyboard._text == expected
		check(immediate, mode + ": letter enters while Cross is still held")
		await create_timer(0.18).timeout
		check(inserts == [expected] if mode == "live" else keyboard._text == expected,
			mode + ": holding Cross does not duplicate the letter")
		await button(JOY_BUTTON_A, false)
		check(inserts == [expected] if mode == "live" else keyboard._text == expected,
			mode + ": release does not enter another letter")
		print("TIMING: %s delivered_before_release=%s hold_ms=%.1f" %
			[mode, immediate, (Time.get_ticks_usec() - start) / 1000.0])
		await button(JOY_BUTTON_DPAD_RIGHT, true)
		await button(JOY_BUTTON_DPAD_RIGHT, false)
		check(root.gui_get_focus_owner() != key, mode + ": D-pad still moves between keys")
		expected += root.gui_get_focus_owner().text
		await button(JOY_BUTTON_A, true)
		await button(JOY_BUTTON_A, false)
		check("".join(inserts) == expected if mode == "live" else keyboard._text == expected,
			mode + ": a second press types exactly one new letter")
		root.remove_child(keyboard)
		keyboard.queue_free()
		await process_frame
	var keyboard: Control = load("res://src/keyboard.gd").new()
	keyboard.masked = false
	root.add_child(keyboard)
	await process_frame
	await process_frame
	var key: Button = keyboard._keys[1][0]
	var motion := InputEventMouseMotion.new()
	motion.position = key.get_global_rect().get_center()
	root.push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = key.get_global_rect().get_center()
	click.pressed = true
	root.push_input(click, true)
	check(keyboard._text == key.text, "mouse: letter enters on button down")
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	check(keyboard._text == key.text, "mouse: release does not duplicate the letter")
	root.remove_child(keyboard)
	keyboard.queue_free()
	await process_frame
	print("Keyboard input timing checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
