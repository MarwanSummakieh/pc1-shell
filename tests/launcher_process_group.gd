extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print(("PASS: " if value else "FAIL: ") + label)
	if not value:
		failures += 1

func live(pid: int) -> bool:
	var file := FileAccess.open("/proc/%d/stat" % pid, FileAccess.READ)
	if file == null:
		return false
	var stat := file.get_line()
	return stat.substr(stat.rfind(")") + 1).strip_edges().get_slice(" ", 0) != "Z"

func _run() -> void:
	if not OS.has_feature("linux"):
		print("Launcher process group checks require Linux")
		quit(1)
		return
	var launcher := root.get_node("Launcher")
	var router := root.get_node("ControllerRouter")
	router.set_process(false)
	var screen: Control = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	check(not launcher._owns_process_group(-1), "invalid PID cannot own a group")
	check(not launcher._owns_process_group(1), "init cannot own a launch group")
	var folder := OS.get_environment("MARWANOS_LAUNCHER_TEST_HOME")
	check(not folder.is_empty(), "isolated fixture directory supplied")
	if folder.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(folder)
	var wrapper := folder.path_join("wrapper.sh")
	var file := FileAccess.open(wrapper, FileAccess.WRITE)
	# Same shape as Bloodborne: flock -> AppImage wrapper -> game descendant.
	file.store_string("#!/bin/sh\nsh -c 'sleep 120 & echo $! > \"$1/game.pid\"; wait' fixture \"$1\" &\necho $! > \"$1/inner.pid\"\nwait\n")
	file.close()
	var unrelated := OS.create_process("/bin/sleep", ["120"])
	for cycle in 2:
		var game_file := folder.path_join("game.pid")
		var inner_file := folder.path_join("inner.pid")
		DirAccess.remove_absolute(game_file)
		DirAccess.remove_absolute(inner_file)
		launcher.launch({"id": "fixture.wrapper", "title": "Wrapper fixture", "kind": "app", "state": "installed", "exec": ["/usr/bin/flock", "-n", folder.path_join("game.lock"), "/bin/sh", wrapper, folder]})
		var pid: int = launcher._pid
		for attempt in 100:
			if FileAccess.file_exists(game_file) and FileAccess.file_exists(inner_file):
				break
			await create_timer(0.02).timeout
		var game := FileAccess.get_file_as_string(game_file).strip_edges().to_int()
		var inner := FileAccess.get_file_as_string(inner_file).strip_edges().to_int()
		check(pid > 0 and game > 0 and inner > 0 and live(game) and live(inner), "cycle %d starts real wrapper descendants" % cycle)
		check(launcher._owns_process_group(pid), "cycle %d launch has its own process group and session" % cycle)
		check(not launcher._owns_process_group(game), "descendant cannot be mistaken for the group leader")
		launcher._app_is_up()
		if cycle == 1:
			launcher.minimize_current()
			check(launcher.is_minimized() and live(game), "minimize preserves the running game")
		# Exercise the actual PS menu action, including returning home/focus.
		screen._open_overlay()
		await process_frame
		check(screen._overlay != null, "PS menu opens for the tracked app")
		screen._overlay._rows.back().grab_focus()
		var event := InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		event = InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = false
		Input.parse_input_event(event)
		for attempt in 100:
			if not launcher.is_busy() and not launcher.is_minimized() and not live(game) and not live(inner):
				break
			await create_timer(0.02).timeout
		check(not launcher.is_busy() and not launcher.is_minimized() and screen.visible, "cycle %d Close App restores Home" % cycle)
		check(not live(pid) and not live(inner) and not live(game), "cycle %d Close App leaves no wrapper or game running" % cycle)
		check(OS.is_process_running(unrelated), "unrelated application survives Close App")
		# Keep a failing test from leaving fixture processes behind.
		if live(pid) or live(inner) or live(game):
			OS.execute("/usr/bin/kill", ["-KILL", "--", "-%d" % pid])
		if live(pid):
			OS.kill(pid)
		launcher._finish()
	OS.kill(unrelated)
	print("Launcher process group checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
