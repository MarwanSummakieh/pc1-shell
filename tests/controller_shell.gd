extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var native_apps: Array = root.get_node("Installed")._parse(
		"org.freedownloadmanager.Manager\tFree Download Manager\t\t\tflatpak run org.freedownloadmanager.Manager\tinstalled\n"
		+ "steam.123\tGame\t\t\tsteam steam://rungameid/123\tinstalled\n")
	check(native_apps.size() == 2, "native FDM and game entries load")
	if native_apps.size() == 2:
		check(native_apps[0].get("input_mode") == "pointer", "Linux FDM uses the controller pointer profile")
		check(native_apps[1].get("input_mode") == "", "games retain ordinary controller routing")
	var router := root.get_node("ControllerRouter")
	var player := root.get_node("PlayerOne")
	var scene: Node = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	router.set_process(false)
	router._routed = true
	var buttons: Array = []
	buttons.resize(15)
	buttons.fill(false)
	var axes := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	router._apply_state({"connected": true, "name": "Test controller", "buttons": buttons, "axes": axes})
	check(player.device == 15, "broker controller claims player one")
	buttons[0] = true
	axes[2] = 0.75
	router._apply_state({"connected": true, "name": "Test controller", "buttons": buttons, "axes": axes})
	await process_frame
	check(player.button(JOY_BUTTON_A), "routed button reaches player input state")
	check(Input.is_action_pressed("ui_accept"), "routed button activates shell actions")
	check(absf(player.axis(JOY_AXIS_RIGHT_X) - 0.75) < 0.01, "routed stick supports cursor and movable keyboard")
	buttons[JOY_BUTTON_BACK] = true
	router._apply_state({"connected": true, "buttons": buttons, "axes": axes})
	await process_frame
	check(player.button(JOY_BUTTON_BACK), "Share remains an ordinary player button")
	check(not Input.is_action_pressed("ui_shell_home"), "Share does not activate system Home")
	player._reconcile()
	check(player.device == 15, "native enumeration cannot evict routed controller")
	var bridge: Node = load("res://src/pad_keys.gd").new()
	bridge.mode = "pointer"
	root.add_child(bridge)
	bridge.set_paused(true)
	bridge.set_paused(false)
	bridge._process(0.1)
	check(bridge._await_neutral, "pointer bridge waits for held menu controls to release")
	router._apply_state({"connected": false})
	await process_frame
	check(player.device == -1, "broker disconnect releases player one")
	check(not player.button(JOY_BUTTON_A), "disconnect releases held button")
	check(player.axis(JOY_AXIS_RIGHT_X) == 0.0, "disconnect neutralizes held stick")
	buttons.fill(false)
	buttons[0] = true  # A disconnected first slot cannot navigate with stale data.
	buttons[JOY_BUTTON_BACK] = true  # Share is not a global Home control.
	buttons[5] = true  # Home remains available on another local player's pad.
	router._apply_state({"connected": false, "buttons": buttons,
		"players": [{"slot": 1, "connected": false}, {"slot": 2, "connected": true, "rumble": true}]})
	await process_frame
	check(not Input.is_action_pressed("ui_accept"), "secondary player cannot navigate while player one is disconnected")
	check(not router._buttons[JOY_BUTTON_BACK], "disconnected player one cannot receive another player's Share")
	check(Input.is_action_pressed("ui_shell_home"), "another player can open Home while player one is disconnected")
	check(router.players.size() == 2 and router.players[1].get("rumble", false), "shell receives independent multiplayer slot capabilities")
	router._apply_state({"connected": false})
	await process_frame
	check(not Input.is_action_pressed("ui_shell_home"), "global Home releases without a connected first pad")
	bridge._process(0.1)
	check(not bridge._await_neutral, "pointer bridge resumes after neutral controls")
	bridge.queue_free()
	print("Controller routing shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
