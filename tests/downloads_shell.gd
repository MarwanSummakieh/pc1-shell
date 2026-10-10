extends SceneTree

var failures := 0
var service: Node

class BrowserView extends Control:
	var cancelled := -1
	func cancel_download(id: int) -> void: cancelled = id

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func frames(count: int = 4) -> void:
	for _i in count: await process_frame

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	await frames()
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	root.push_input(event)
	await frames()

func state(tasks: Array, available: bool = true) -> void:
	var path: String = service._folder.path_join("state.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"updated_at": Time.get_unix_time_from_system(), "available": available, "tasks": tasks, "error": ""}))
	file.close()
	service._poll()

func task(id: String, status: String, received: int = 256000000) -> Dictionary:
	return {"id": id, "name": "Fedora Workstation Live 43.iso" if id == "linux" else "Controller tools and documentation.zip", "kind": "torrent" if id == "linux" else "http",
		"status": status, "total": 2000000000, "received": received, "speed": 6400000 if status == "active" else 0,
		"directory": service._folder, "files": [{"index": "1", "selected": true, "name": "Live.iso"}]}

func _run() -> void:
	await frames()
	service = root.get_node("Downloads")
	service._folder = OS.get_environment("MARWANOS_SHELL_STATUS_DIR").path_join("downloads")
	state([task("linux", "active"), task("tools", "paused")])
	var home: Control = load("res://src/shell_root.gd").new()
	root.add_child(home)
	current_scene = home
	await frames()
	var origin: Control
	for button: Control in home._bar_buttons:
		if button.get_meta("destination", "") == "Downloads": origin = button
	check(origin != null, "native Downloads destination exists")
	origin.grab_focus()
	service.open()
	await frames()
	var screen: Control = service._screen
	check(screen != null and not home.visible, "Downloads owns the shell surface")
	check(screen._rows.size() == 2, "service transfers appear")
	var row: Control = screen._rows.linux
	row.grab_focus()
	state([task("linux", "active", 512000000), task("tools", "paused")])
	await frames()
	check(screen._rows.linux == row and row.has_focus(), "progress updates keep the controller's selected row")
	await press("ui_accept")
	check(screen._modal != null, "row actions open from the controller")
	await press("ui_accept")
	var requests: PackedStringArray = DirAccess.get_files_at(service._folder.path_join("requests"))
	check(not requests.is_empty(), "pause request reaches the service spool")
	var last: Variant = JSON.parse_string(FileAccess.get_file_as_string(service._folder.path_join("requests").path_join(requests[-1])))
	check(last.action == "pause" and last.target == "linux", "pause targets the selected transfer")
	check(row.has_focus(), "closing actions restores transfer focus")
	await press("ui_shell_x")
	check(screen._modal != null and screen._modal.input_context == "url", "Add link opens the shared URL keyboard")
	screen._modal.cancelled.emit()
	await frames()
	check(row.has_focus(), "cancelled link restores focus")
	state([task("linux", "seeding", 2000000000), task("tools", "complete", 2000000000)])
	screen._change_filter("finished")
	await frames()
	check(screen._rows.size() == 2, "finished filter includes seeding payloads")
	var installs := root.get_node("WindowsInstall")
	for child in installs.get_children():
		if child is Timer: child.stop()
	var source: String = service._folder.path_join("setup.exe")
	installs.local_jobs = [{"id": "download-choice", "source": source, "created_at": 1, "status": "select",
		"choices": [{"id": "game", "title": "Downloaded game", "path": "bin/game.exe"}]}]
	screen._task_actions(screen._rows.tools.task)
	await frames()
	check(screen._modal.items[0].label == "Choose program to play", "finished transfer exposes program selection")
	await press("ui_accept")
	check(installs.is_open() and not service.is_open(), "program selection transfers surface ownership to setup")
	check(installs._screen._rows[0].get_meta("key") == "download-choice.game.game", "selection offers the exact installed game executable")
	await press("ui_cancel")
	check(service.is_open() and not installs.is_open(), "Back from program selection restores Downloads")
	screen = service._screen
	installs.local_jobs = []
	for child in installs.get_children():
		if child is Timer: child.start()
	var view := BrowserView.new()
	root.add_child(view)
	service.browser_updated({"id": 42, "state": "downloading", "name": "Browser file.zip", "total": 5000000, "received": 1200000}, view)
	screen._change_filter("all")
	await frames()
	check(screen._rows.size() == 3, "native and browser transfers share the queue")
	var browser_id: String = service.browser_tasks.keys()[0]
	service.request("remove", browser_id)
	check(view.cancelled == 42, "browser cancellation reaches the originating Chromium view")
	service.browser_updated({"id": 42, "state": "cancelled", "name": "Browser file.zip"}, view)
	check(not service.browser_tasks.has(browser_id), "late Chromium cancellation callbacks do not recreate removed entries")
	view.queue_free()
	state([], false)
	await frames()
	check(screen._actions[0].disabled, "service outage disables native transfer creation")
	state([task("linux", "active"), task("tools", "paused")])
	screen._change_filter("all")
	await frames()
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440), Vector2i(800, 900)]:
		root.size = dimensions
		await frames()
		check(screen._list.size.x <= screen.size.x, "queue stays within viewport at %s" % dimensions)
		check(screen._actions[1].get_global_rect().end.x <= screen.size.x, "toolbar wraps within viewport at %s" % dimensions)
		if not OS.get_environment("MARWANOS_DOWNLOADS_CAPTURE").is_empty():
			await RenderingServer.frame_post_draw
			var output := OS.get_environment("MARWANOS_DOWNLOADS_CAPTURE")
			var capture := root.get_texture().get_image()
			capture.save_png(output.get_base_dir().path_join("downloads-%dx%d.png" % [dimensions.x, dimensions.y]))
			if dimensions == Vector2i(1920, 1080): capture.save_png(output)
	await press("ui_cancel")
	check(not service.is_open() and home.visible and origin.has_focus(), "Back restores the originating system control")
	check(load("res://src/file_open.gd").plan("game.TORRENT").action == "torrent", "Files recognizes torrent metadata")
	root.get_node("Browser").open()
	await frames()
	var browser: Control = root.get_node("Browser")._screen
	browser._open_downloads()
	await frames()
	check(browser._picker != null and browser._picker.get_script().resource_path == "res://src/downloads_screen.gd", "browser opens the same native Downloads surface")
	await press("ui_cancel")
	check(browser._picker == null and browser.visible, "Downloads returns to the retained browser")
	root.get_node("Browser")._finish_deferred()
	await frames()
	root.get_node("Files").open()
	await frames()
	var files: Control = root.get_node("Files")._screen
	files._open_downloads(service._folder.path_join("example.torrent"))
	await frames()
	check(files._downloads != null and files._downloads._modal != null, "opening a torrent in Files presents review before creating a transfer")
	await press("ui_cancel")
	check(files._downloads._modal == null, "torrent review can be cancelled")
	await press("ui_cancel")
	check(files._downloads == null and files.visible, "torrent surface returns to the originating Files screen")
	root.get_node("Files").close()
	await frames()
	print("Downloads shell checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
