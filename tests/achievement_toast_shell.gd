extends SceneTree

var failures := 0
var native := false


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)


func _initialize() -> void:
	_run.call_deferred()


func overlay_property(window: Window) -> String:
	var output: Array = []
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id())
	if OS.execute("xprop", ["-id", str(handle), "-notype", "GAMESCOPE_EXTERNAL_OVERLAY"], output, true) != 0 or output.is_empty():
		return ""
	return str(output[0]).get_slice("=", 1).strip_edges()


func native_focus(stage: String) -> int:
	var output: Array = []
	OS.execute("xdotool", ["getwindowfocus"], output, true)
	var xid := str(output[0]).strip_edges().to_int() if not output.is_empty() else 0
	var name: Array = []
	OS.execute("xdotool", ["getwindowname", str(xid)], name, true)
	print("Toast fixture: X focus ", stage, " xid=", xid, " title=", " ".join(name).strip_edges())
	return xid


func check_suppressed(window: Window, stage: String) -> void:
	if window == null:
		check(false, stage + " has a retiring surface")
		return
	if not native:
		check(not window.visible, stage + " hides headless surface")
		return
	var output: Array = []
	var xid: int = window._native_handle
	check(xid > 0 and window._dismissing, stage + " retains WindowData during same-frame retirement")
	OS.execute("xprop", ["-id", str(xid), "-notype", "_NET_WM_WINDOW_OPACITY"], output, true)
	check(not output.is_empty() and str(output[0]).get_slice("=", 1).strip_edges() == "0", stage + " excludes retired surface from gamescope external selection immediately")
	output.clear()
	OS.execute("xdotool", ["search", "--onlyvisible", "--name", "^MarwanOS achievement notification$"], output, true)
	check(not "\n".join(output).split("\n").has(str(xid)), stage + " synchronously unmaps only retired native XID")
	check(overlay_property(window) == "1", stage + " keeps external tag until destruction")


func _run() -> void:
	print("Toast fixture: initializing")
	await process_frame
	native = DisplayServer.get_name() == "X11"
	var launcher := root.get_node("Launcher")
	# No actual launches/provider/save writes: all state below is an isolated UI
	# fixture. Stop sampling while validating that presentation does not mutate it.
	for child in launcher.get_children():
		if child is Timer:
			child.stop()
	var history := root.get_node("PlayHistory")
	history._foreground = true
	history._active_id = "toast-fixture"
	var router := root.get_node("ControllerRouter")
	router._app_input = true
	var kiosk := root.get_node("Kiosk")
	var home: Control = load("res://src/shell_root.gd").new()
	root.add_child(home)
	await process_frame
	print("Toast fixture: shell ready")
	var notification := {"id": 2, "app": "Achievements", "summary": "Achievement unlocked: No pain, no gain!", "body": "TEKKEN 8\nDealt 2000 damage in Practice mode."}
	var game: Window
	var game_keys: Array = []
	var game_clicks: Array = []
	var toast_keys: Array = []
	if native:
		game = Window.new()
		game.visible = false
		game.force_native = true
		game.transient = false
		game.title = "Achievement toast underlying game fixture"
		game.size = Vector2i(800, 600)
		game.window_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed:
				game_keys.append(event.keycode)
			if event is InputEventMouseButton and event.pressed:
				game_clicks.append(event.button_index))
		root.add_child(game)
		game.show()
		await create_timer(0.15).timeout
		game.grab_focus()
		await create_timer(0.15).timeout
		check(game.has_focus(), "underlying native game fixture starts focused")
		print("Toast fixture: underlying game focused")
	launcher._current = {"id": "fixture.game", "title": "Fixture", "exec": ["fixture"], "kind": "game"}
	launcher._app_on_screen = true
	launcher._pad_keys_paused = false
	home._hand_screen_over()
	# Observe the actual mapped native XID after show() returns, before tagging.
	# This catches the initial-map race, including backend clamping/minimum size,
	# rather than asserting only Godot's requested/cached geometry.
	var probe: Window = load(get_script().resource_path.get_base_dir().path_join("achievement_toast_probe.gd")).new()
	var initial_maps: Array = []
	root.add_child(probe)
	probe.before_classification = func():
		print("Toast fixture: initial map before classification")
		initial_maps.append(true)
		check(probe.size == Vector2i.ONE, "initial map remains inert 1x1 before classification")
		if native:
			check(overlay_property(probe) != "1", "initial map probe runs before external classification")
			print("Toast fixture: initial property inspected")
			var geometry: Array = []
			var xid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, probe.get_window_id())
			check(OS.execute("xdotool", ["getwindowgeometry", "--shell", str(xid)], geometry, true) == 0, "query actual initial native geometry")
			var fields := {}
			for line in "\n".join(geometry).split("\n"):
				if line.contains("="):
					fields[line.get_slice("=", 0)] = line.get_slice("=", 1).to_int()
			check(fields.get("WIDTH", 0) == 1 and fields.get("HEIGHT", 0) == 1, "actual unclassified native window is inert 1x1")
			print("Toast fixture: initial X geometry ", fields)
			var focus: Array = []
			OS.execute("xdotool", ["getwindowfocus"], focus, true)
			var game_xid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, game.get_window_id())
			check(not focus.is_empty() and str(focus[0]).strip_edges().to_int() == game_xid, "unclassified initial map preserves underlying native game focus")
	print("Toast fixture: presenting lifecycle probe")
	var presented: bool = probe.present(notification)
	check(presented, "lifecycle probe presents without interactive focus changes")
	if not presented:
		quit(1)
		return
	print("Toast fixture: lifecycle probe classified and expanded")
	if native:
		native_focus("after probe expansion")
	check(not native or initial_maps.size() == 1, "initial map classification interval was observed")
	print("Toast fixture: initial-map assertion complete")
	check(not native or probe.size == DisplayServer.screen_get_size(), "classified toast expands to output after inert map")
	print("Toast fixture: expansion assertion complete")
	if native:
		print("Toast fixture: reading classified probe property")
		check(probe.classification_calls == [true] and overlay_property(probe) == "1", "classification is verified before usable overlay size")
	print("Toast fixture: dismissing lifecycle probe")
	if native:
		native_focus("before probe hide")
	probe.dismiss()
	print("Toast fixture: lifecycle probe retirement started")
	if native:
		native_focus("after probe unmap")
	check_suppressed(probe, "same-frame probe")
	# A concurrent second dismiss must wait for the first, never destroy the
	# WindowData early while its MapNotify remains queued.
	await probe.dismiss()
	check(not probe.visible and probe._native_handle == 0, "dismiss destroys independent native surface")
	check(not probe.classification_calls.has(false), "dismiss never clears external classification while mapped")
	probe.queue_free()
	await process_frame
	if native:
		var game_xid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, game.get_window_id())
		check(native_focus("after probe free/frame") == game_xid, "isolated probe retirement preserves actual game focus")
		check(native_focus("before production toast") == game_xid, "production toast starts with actual underlying game focus")
	var main_transparent := root.transparent_bg
	var main_overlay: bool = kiosk._overlay_active
	var yielded: bool = kiosk._yielded
	var focus_request: int = kiosk._focus_request
	var app_window: int = kiosk._app_window
	var current: Dictionary = launcher._current.duplicate(true)
	home._on_system_notification(notification)
	var toast: Window = home._achievement_toast
	check(toast != null and toast.visible, "foreground achievement creates a visible independent toast")
	if toast != null:
		toast.window_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed:
				toast_keys.append(event.keycode))
		check(toast.force_native and toast.unfocusable and toast.mouse_passthrough, "toast declares native no-focus mouse passthrough before mapping")
		check(toast.transparent and toast.transparent_bg and toast.gui_disable_input, "toast has transparent content and disabled GUI input")
		check(not toast.transient and not toast.exclusive, "toast cannot acquire parent modal focus")
		check(toast._heading.text == notification.summary and toast._body.text == notification.body, "toast preserves genuine provider summary/game/description")
		check(toast._timer.time_left > 0 and toast._timer.time_left <= toast.LIFETIME_SECONDS, "toast starts a bounded lifetime")
	await create_timer(0.12).timeout
	check(not home.visible and root.transparent_bg == main_transparent, "passive toast leaves hidden main shell/transparency unchanged")
	check(kiosk._overlay_active == main_overlay and kiosk._yielded == yielded, "passive toast does not acquire interactive overlay/yield lease")
	check(kiosk._focus_request == focus_request and kiosk._app_window == app_window, "passive toast does not request base-layer/app focus")
	check(not launcher._pad_keys_paused and router._app_input, "controller/game input keeps flowing during passive toast")
	check(history._foreground and history._active_id == "toast-fixture", "passive toast leaves foreground history/session untouched")
	check(launcher._current == current, "passive toast neither changes nor restarts current game")
	if native and toast != null:
		check(not toast.is_embedded() and toast.get_window_id() != root.get_window_id(), "native toast owns a distinct OS window")
		check(overlay_property(toast) == "1", "only toast native XID carries verified external-overlay property")
		check(overlay_property(root) != "1", "main shell does not become an external overlay for a toast")
		check(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, toast.get_window_id()), "native backend retains no-focus flag")
		check(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, toast.get_window_id()), "native backend retains mouse-passthrough flag")
		var actual_focus: Array = []
		OS.execute("xdotool", ["getwindowfocus"], actual_focus, true)
		var game_xid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, game.get_window_id())
		# Godot's cached Window.has_focus can be true on multiple new subwindows;
		# query X's actual focus and prove real key delivery instead.
		check(not actual_focus.is_empty() and str(actual_focus[0]).strip_edges().to_int() == game_xid, "mapping toast preserves actual X keyboard focus on underlying game")
		OS.execute("xdotool", ["key", "F8"])
		OS.execute("xdotool", ["mousemove", str(game.position.x + 100), str(game.position.y + 100), "click", "1"])
		await create_timer(0.12).timeout
		check(game_keys.has(KEY_F8) and toast_keys.is_empty(), "real native keyboard event reaches underlying game rather than toast")
		check(game_clicks.has(MOUSE_BUTTON_LEFT), "real native mouse click passes through toast to underlying game")
		var image := toast.get_texture().get_image()
		check(image != null and image.get_pixel(0, 0).a == 0, "rendered toast viewport is actually transparent outside panel")
		var capture := OS.get_environment("MARWANOS_TOAST_CAPTURE_DIR")
		if not capture.is_empty() and image != null:
			image.save_png(capture.path_join("achievement-toast-%dx%d.png" % [toast.size.x, toast.size.y]))
		check(toast._panel.size.y > 0 and toast._heading.size.y > 0 and toast._body.size.y > 0, "toast heading/body render with positive visible height")
		check(Rect2(Vector2.ZERO, toast.get_visible_rect().size).encloses(toast._panel.get_global_rect()), "toast panel stays inside the native viewport")
	# Timer expiry destroys only the separate surface and cannot release an
	# interactive lease (which a later Home overlay may own).
	if toast != null:
		if native:
			native_focus("before production expiry")
		toast._timer.start(0.05)
	await create_timer(0.12).timeout
	check(home._achievement_toast == null, "timer expiry clears owning reference")
	await process_frame
	check(not is_instance_valid(toast), "timer expiry frees native toast window")
	if native:
		var game_xid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, game.get_window_id())
		check(native_focus("after production expiry") == game_xid, "production expiry preserves actual underlying game focus")
	check(not launcher._pad_keys_paused and router._app_input, "expiry does not divert game input")
	home._on_system_notification({"app": "FDM Controller", "summary": "Download complete"})
	check(home._achievement_toast == null, "background downloads do not interrupt game with achievement surface")
	# Multiple genuine notifications can be sampled in one shell frame. Old
	# completion callbacks must never retire the newest independently owned XID.
	home._on_system_notification(notification)
	var replaced: Window = home._achievement_toast
	home._on_system_notification(notification)
	var replacement: Window = home._achievement_toast
	check(replaced != replacement, "rapid replacement creates independent newest toast")
	check_suppressed(replaced, "rapid replacement")
	replaced.expired.emit()
	check(home._achievement_toast == replacement and replacement.visible, "late old expiry cannot dismiss newest toast")
	await process_frame
	await process_frame
	check(not is_instance_valid(replaced) and is_instance_valid(replacement), "rapid replacement frees only retired toast")
	if native:
		var game_xid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, game.get_window_id())
		check(native_focus("after rapid replacement") == game_xid, "rapid replacement retains actual game focus")
	home._dismiss_achievement_toast()
	await process_frame
	home._on_system_notification(notification)
	toast = home._achievement_toast
	home._open_overlay()
	check(home._achievement_toast == null, "Home clears passive owner before interactive overlay")
	check_suppressed(toast, "same-frame Home priority")
	check(home._overlay != null and launcher._pad_keys_paused, "Home retains its existing interactive input ownership")
	home._on_system_notification(notification)
	check(home._achievement_toast == null, "notifications during interactive overlay do not compete for external-overlay slot")
	await process_frame
	await process_frame
	check(not is_instance_valid(toast) and kiosk._overlay_active, "deferred toast destruction cannot clear interactive overlay lease")
	home._close_overlay()
	launcher._pad_keys_paused = false
	router._app_input = true
	home._on_system_notification(notification)
	check(home._achievement_toast != null, "future unlock can show after interactive overlay closes")
	launcher._current = {}
	launcher._app_on_screen = false
	home._on_launch_finished({})
	check(home._achievement_toast == null, "game exit/minimize cleans up passive toast")
	home._on_system_notification(notification)
	check(home._app_alert.visible and home._app_alert.text.contains(notification.summary), "existing home notification alert remains intact")
	root.get_node("Info").open()
	await process_frame
	home._app_alert.hide()
	home._on_system_notification(notification)
	check(not home._app_alert.visible and home._achievement_toast == null, "Info keeps notification history without competing toast")
	root.get_node("Info")._finish()
	# The toast is parented to SceneTree.root, not home. Its retirement must
	# finish even when the shell that initiated it is freed during the grace.
	launcher._current = current
	launcher._app_on_screen = true
	home._on_system_notification(notification)
	var teardown_toast: Window = home._achievement_toast
	check(teardown_toast != null, "shell teardown fixture maps a new toast")
	home.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(teardown_toast), "freeing shell during retirement leaves no independent native orphan")
	if game != null:
		game.queue_free()
	history._active_id = ""
	history._foreground = false
	await process_frame
	print("Achievement toast shell checks: %d failure(s); native=%s" % [failures, native])
	quit(1 if failures else 0)
