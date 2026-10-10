extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print(("PASS: " if value else "FAIL: ") + label)
	if not value:
		failures += 1

func frames() -> void:
	await process_frame
	await process_frame

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event, true)
	event = InputEventAction.new()
	event.action = action
	root.push_input(event, true)
	await frames()

func _run() -> void:
	var scene: Node = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(scene)
	await frames()
	var router := root.get_node("ControllerRouter")
	router.set_process(false)
	router.players = [{"slot": 1, "connected": true}]
	var menu: Control = load("res://src/power_screen.gd").new()
	root.add_child(menu)
	check(menu._rows.size() == 3, "power menu offers Rest mode without Sleep")
	check(menu._rest_row._value_text.is_empty(), "Rest mode has no description beside its label")
	menu.queue_free()
	await frames()
	var fixture = load("res://tests/rest_display_fixture.gd")
	var rest = fixture.new()
	root.add_child(rest)
	var previous_fps := Engine.max_fps
	var dock_was_visible: bool = scene._bar_row.visible
	check(rest.begin(), "rest turns off a supported display")
	check(rest.commands.has(["dpms", "force", "off"]), "rest requests DPMS display off")
	check(Engine.max_fps == 10, "rest reduces shell rendering while keeping its broker heartbeat alive")
	check(FileAccess.file_exists(rest._state_path()), "display recovery settings survive a shell crash")
	await press("ui_accept")
	await press("ui_down")
	check(rest._active, "ordinary buttons do not accidentally wake or navigate")
	await press("ui_shell_home")
	check(not is_instance_valid(rest), "PS wakes and removes the rest input shield")
	check(scene._bar_row.visible == dock_was_visible, "wake press is consumed before the Home dock")
	check(Engine.max_fps == previous_fps, "wake restores the previous rendering rate")
	var state_path: String = OS.get_environment("XDG_RUNTIME_DIR").path_join("marwanos/rest-display.json")
	check(not FileAccess.file_exists(state_path), "wake clears successful display recovery state")

	rest = fixture.new()
	root.add_child(rest)
	check(rest.begin(), "rest can be entered repeatedly")
	router.players = [{"slot": 1, "connected": false}]
	rest._process(0.3)
	router.players = [{"slot": 1, "connected": false}, {"slot": 2, "connected": true}]
	rest._process(0.3)
	check(not rest._active, "reconnecting either Bluetooth player wakes the screen")
	check(rest.commands.has(["dpms", "force", "on"]) and rest.commands.has(["dpms", "120", "240", "600"])
		and rest.commands.back() == ["-dpms"], "wake restores power state and original DPMS settings")
	await frames()

	rest = fixture.new()
	rest.fail_off = true
	root.add_child(rest)
	check(not rest.begin(), "failed display-off does not enter rest")
	check(rest.commands.has(["dpms", "force", "on"]), "failed entry rolls display settings back")
	check(Engine.max_fps == previous_fps, "failed entry preserves rendering rate")
	rest.queue_free()
	await frames()
	rest = fixture.new()
	rest.query = "DPMS extension not supported"
	root.add_child(rest)
	check(not rest.begin() and rest.commands.size() == 1, "unsupported displays fail without changing power settings")
	rest.queue_free()
	await frames()

	rest = fixture.new()
	root.add_child(rest)
	check(rest.begin(), "cleanup scenario enters rest")
	rest.free()
	check(not FileAccess.file_exists(state_path) and Engine.max_fps == previous_fps, "shell shutdown restores display and rendering settings")
	print("Rest shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
