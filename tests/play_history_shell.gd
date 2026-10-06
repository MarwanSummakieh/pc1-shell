extends SceneTree

var failures := 0

func check(value: bool, label_text: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var history := root.get_node("PlayHistory")
	var launcher := root.get_node("Launcher")
	check(launcher._history_steam_matches("STEAM_GAME = 1778820", "1778820"), "Steam handoff requires exact game app ID on foreground window")
	check(not launcher._history_steam_matches("STEAM_GAME = 769", "1778820") and not launcher._history_steam_matches("STEAM_GAME: not found.", "1778820"), "Steam client and unproven windows never count as game")
	history._folder = "/tmp/pc1-history-%d" % OS.get_process_id()
	history.reload()
	var game := {"id": "managed.tekken-a", "title": "Tekken", "state": "installed", "exec": ["fixture"], "metadata": {"provider": "Steam Store", "provider_id": "1778820", "description": "Fighting game"}}
	var second := game.duplicate(true)
	second.id = "managed.tekken-b"
	var tool := {"id": "org.freedownloadmanager.Manager", "state": "installed", "exec": ["fixture"]}
	history.sample(tool, true, 1000, 1000)
	check(history.games.is_empty(), "desktop tools do not generate history")
	var installer := game.duplicate(true)
	installer.executable = "/setup.exe"
	history.sample(installer, true, 1000, 1000)
	check(history.games.is_empty(), "installer executable excluded even with metadata")
	history.sample(game, false, 1000, 1000)
	check(history.games.is_empty(), "windowless/failed launch does not create a session or last played")
	history.sample(game, true, 2000, 1001)
	history.sample(game, true, 12000, 1011)
	check(history.stats(game.id).total_seconds == 0, "unobserved long interval never counted")
	for index in range(1, 5):
		history.sample(game, true, 12000 + index * 1000, 1011 + index)
	check(history.stats(game.id).total_seconds == 4, "confirmed foreground observations accumulate")
	history.pause(17000, 1016)
	history.sample(game, false, 117000, 1116)
	history.sample(game, true, 118000, 1117)
	history.sample(game, true, 119000, 1118)
	check(history.stats(game.id).sessions.size() == 1 and history.stats(game.id).total_seconds == 6, "minimize/resume retains one session and excludes background time")
	# Linux CLOCK_MONOTONIC can stop during suspend: wall clock catches that gap.
	history.sample(game, true, 120000, 2119)
	history.sample(game, true, 121000, 2120)
	check(history.stats(game.id).total_seconds == 7, "suspend gap excluded even when monotonic clock advances just one second")
	history.sample(game, false, 122000, 2121)
	history.sample(game, true, 123000, 2122)
	check(history.stats(game.id).total_seconds == 7, "unknown/focus loss observations pause conservatively")
	history.finish("exited", 124000, 2123)
	check(history.stats(game.id).total_seconds == 8 and history.stats(game.id).sessions[0].end_reason == "exited", "normal exit closes and persists foreground time")
	history.sample(second, true, 125000, 2124)
	history.sample(second, true, 126000, 2125)
	history.pause(127000, 2126)
	check(history.stats(game.id).total_seconds == 8 and history.stats(second.id).total_seconds == 2, "separate installations of the same game have separate totals")
	var sorted: Array = history.recently_played([tool, game, second])
	check(sorted[0].id == second.id and sorted[1].id == game.id and sorted[2].id == tool.id, "recently played descending, unplayed last")
	var plain := {"id": "plain", "state": "installed", "exec": ["fixture"]}
	check(history.recently_played([tool, plain])[0].id == tool.id, "unplayed tie retains scanner order")
	var restored: Node = load("res://src/play_history.gd").new()
	restored._folder = history._folder
	restored.reload()
	check(restored.stats(game.id).total_seconds == 8 and restored.stats(second.id).total_seconds == 2, "fresh observer reloads durable totals")
	check(restored.stats(second.id).sessions[0].end_reason == "observer-restarted" and restored.stats(second.id).sessions[0].ended_at == 2126, "crash/reboot closes at last checkpoint with no downtime backfill")
	# A corrupt primary recovers from the independently atomic backup.
	var file := FileAccess.open(history._folder.path_join("state.json"), FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	restored.reload()
	check(restored.stats(game.id).total_seconds == 8, "corrupt primary recovers valid backup")
	check(history.duration(3661) == "1 h 1 min", "human readable playtime")
	restored.free()
	print("Play history shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
