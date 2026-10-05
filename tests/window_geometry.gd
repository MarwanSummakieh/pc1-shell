extends SceneTree

var failures := 0

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	OS.set_environment("MARWANOS_COMPOSITOR", "gamescope")
	root.gui_embed_subwindows = false
	var app := Window.new()
	app.title = "Desktop geometry fixture"
	app.size = Vector2i(950, 610)
	root.add_child(app)
	app.show()
	await create_timer(0.3).timeout
	var kiosk := root.get_node("Kiosk")
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, app.get_window_id())
	OS.execute("xprop", ["-id", str(handle), "-f", "_NET_WM_WINDOW_TYPE", "32a", "-set", "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_NORMAL"])
	OS.execute("xprop", ["-root", "-f", "GAMESCOPE_FOCUSED_WINDOW", "32c", "-set", "GAMESCOPE_FOCUSED_WINDOW", str(handle)])
	kiosk.remember_app_window(true)
	await create_timer(0.3).timeout
	var native := DisplayServer.screen_get_size(DisplayServer.get_primary_screen())
	check(app.size == native, "desktop application backing window uses native display pixels")
	app.size = Vector2i(950, 610)
	await create_timer(0.2).timeout
	kiosk.focus_app()
	await create_timer(0.2).timeout
	check(app.size == native, "resuming desktop application restores native pixels")
	kiosk.minimize_app_window()
	await create_timer(0.2).timeout
	var visible: Array = []
	OS.execute("xdotool", ["search", "--onlyvisible", "--name", app.title], visible)
	check(visible.is_empty() or not str(visible[0]).contains(str(handle)), "minimize unmaps app window without closing it")
	check(is_instance_valid(app), "minimize preserves app instance")
	kiosk.focus_app()
	await create_timer(0.2).timeout
	visible.clear()
	OS.execute("xdotool", ["search", "--onlyvisible", "--name", app.title], visible)
	check(not visible.is_empty() and str(visible[0]).contains(str(handle)), "resume remaps the same app window")
	app.size = Vector2i(950, 610)
	await create_timer(0.2).timeout
	OS.execute("xprop", ["-id", str(handle), "-f", "_NET_WM_WINDOW_TYPE", "32a", "-set", "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_DIALOG"])
	kiosk._fit_app_to_screen()
	await create_timer(0.2).timeout
	check(app.size == Vector2i(950, 610), "dialog retains its requested size")
	OS.execute("xprop", ["-id", str(handle), "-f", "_NET_WM_WINDOW_TYPE", "32a", "-set", "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_NORMAL"])
	OS.execute("xprop", ["-id", str(handle), "-f", "_NET_WM_STATE", "32a", "-set", "_NET_WM_STATE", "_NET_WM_STATE_FULLSCREEN"])
	kiosk._fit_app_to_screen()
	await create_timer(0.2).timeout
	check(app.size == Vector2i(950, 610), "application fullscreen mode is not resized")
	print("Window geometry checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
