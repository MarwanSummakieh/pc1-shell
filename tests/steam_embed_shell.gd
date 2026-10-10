extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func _run() -> void:
	var embed := root.get_node("SteamEmbed")
	var launcher := root.get_node("Launcher")
	var router := root.get_node("ControllerRouter")
	embed.set_process(false)
	router.set_process(false)
	check(not embed.supported(), "embedding is opt-in and unavailable outside Xorg")
	var pane := Control.new()
	root.add_child(pane)
	embed._surface = pane
	embed.snapshot = {"phase": "ready"}
	embed.enter_pane()
	check(embed.owns_input(), "entering Steam transfers controller ownership")
	var select := InputEventJoypadButton.new()
	select.button_index = JOY_BUTTON_A
	select.pressed = true
	check(embed.handle_input(select), "Steam consumes Select before shell navigation")
	var share := select.duplicate()
	share.button_index = JOY_BUTTON_BACK
	check(embed.handle_input(share) and embed._action == "menu" and embed.owns_input(), "Share opens Steam menu without returning to the shell")
	var guide := select.duplicate()
	guide.button_index = JOY_BUTTON_GUIDE
	check(embed.handle_input(guide) and not embed.owns_input() and not router._app_input, "Guide returns and immediately neutralizes application input")
	embed.enter_pane()
	launcher._current = {"id": "steam.1030300"}
	check(not embed.owns_input(), "a running game excludes Steam pane input")
	launcher._current = {}
	embed.hide_pane()
	check(not embed.owns_input() and not router._app_input, "hiding Stores neutralizes Steam input")
	check(not launcher._history_steam_matches("STEAM_GAME = 769", "1030300"), "Steam client never counts as the game")
	check(launcher._history_steam_matches("STEAM_GAME = 1030300", "1030300"), "history requires the exact Steam game identity")
	embed.snapshot = {"phase": "ready", "client": 123, "game_id": 1030300, "heartbeat": Time.get_unix_time_from_system()}
	launcher._current = {"id": "steam.1030300", "exec": ["never-run"]}
	launcher._handoff = true
	launcher._app_on_screen = true
	launcher._check_window()
	check(launcher._embedded_steam_game, "shell library launches also preserve an existing embedded Steam session")
	launcher.close_current()
	check(embed._action == "close_game", "Close targets the observed game and keeps Steam running")
	launcher._current = {}
	launcher._handoff = false
	launcher._embedded_steam_game = false
	launcher._app_on_screen = false
	print("Steam embedding shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
