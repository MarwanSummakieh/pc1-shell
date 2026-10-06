extends SceneTree

var failures := 0
var installs: Node
var flow: Node
var folder := ""

func check(value: bool, label_text: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func _initialize() -> void:
	_run.call_deferred()

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func receipts(items: Array) -> void:
	var file := FileAccess.open(folder.path_join("state.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"heartbeat": Time.get_unix_time_from_system(), "status": "idle", "downloads": items, "library": [], "recipes": [], "candidates": []}))
	file.close()
	installs._poll()

func requests() -> Array:
	var result: Array = []
	for name in DirAccess.get_files_at(folder.path_join("requests")):
		if name.ends_with(".json"):
			var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("requests").path_join(name)))
			if value is Dictionary:
				result.append(value)
	return result

func has_request(verb: String, action: String = "", path: String = "") -> bool:
	for item in requests():
		if item.get("verb", "") == verb and (action.is_empty() or item.get("action", "") == action) and (path.is_empty() or item.get("path", "") == path):
			return true
	return false

func dismiss() -> void:
	await press("ui_cancel")
	await process_frame

func _run() -> void:
	await process_frame
	installs = root.get_node("WindowsInstall")
	flow = root.get_node("DownloadInstall")
	folder = installs.home
	DirAccess.make_dir_recursive_absolute(folder.path_join("requests"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("jobs"))
	var helper := FileAccess.open(folder.path_join("capture-helper"), FileAccess.WRITE)
	helper.store_string("#!/bin/sh\nprintf '%s\\n' \"$@\" >> '" + folder.path_join("helper-args") + "'\n")
	helper.close()
	FileAccess.set_unix_permissions(folder.path_join("capture-helper"), 493)
	installs.helper = folder.path_join("capture-helper")
	var home := Control.new()
	root.add_child(home)
	current_scene = home
	var ready := {"id": "ready-later", "source": folder.path_join("setup.exe"), "status": "ready", "torrent": false}
	receipts([ready])
	flow._poll()
	await process_frame
	check(flow._menu != null and flow._menu.items[0].id == "start" and flow._menu.items[1].id == "defer", "ready download defaults to Install with explicit Later")
	check(root.gui_get_focus_owner() == flow._menu._rows[0], "ready receipt focuses Install")
	await press("ui_down")
	await press("ui_accept")
	await process_frame
	check(flow._menu == null and has_request("download-action", "defer"), "controller Later defers without running installer")
	check(not installs.is_open(), "Later leaves installation surface closed")
	ready.id = "ready-start"
	receipts([ready])
	flow._poll()
	await process_frame
	await press("ui_accept")
	await process_frame
	check(has_request("download-action", "start") and installs.is_open(), "controller Install starts the concrete downloaded setup surface")
	check(installs._screen.source_path == ready.source, "installation uses exact receipt source path")
	# The fixture helper captures argv and never executes an installer.
	if is_instance_valid(installs._guided_screen):
		installs._guided_screen.get_parent().remove_child(installs._guided_screen)
		installs._guided_screen.queue_free()
		installs._guided_screen = null
	installs._guided_pid = -1
	installs.guided_source = ""
	installs._finish_deferred()
	var installed := {"id": "installed-keep", "source": ready.source, "status": "installed", "torrent": false}
	receipts([installed])
	flow._poll()
	await process_frame
	check(flow._menu.items[0].id == "keep" and flow._menu.items[1].id == "cleanup", "successful installation defaults to Keep and offers explicit Cleanup")
	check(root.gui_get_focus_owner() == flow._menu._rows[0], "cleanup is never the default focus")
	await press("ui_accept")
	await process_frame
	check(has_request("download-action", "keep") and not has_request("download-action", "cleanup"), "default controller accept keeps files")
	installed.id = "installed-cleanup"
	receipts([installed])
	flow._poll()
	await process_frame
	await press("ui_down")
	await press("ui_accept")
	await process_frame
	check(has_request("download-action", "cleanup"), "cleanup requires selecting its row explicitly")
	installed.id = "installed-torrent"
	installed.torrent = true
	receipts([installed])
	flow._poll()
	await process_frame
	check(flow._menu.items.size() == 1 and flow._menu.items[0].id == "keep" and flow._menu.note_text.contains("seeding"), "torrent completion keeps seeding files and has no cleanup action")
	await dismiss()
	var pending := {"id": "never-interrupt", "source": ready.source, "status": "ready", "torrent": false}
	receipts([pending])
	var launcher := root.get_node("Launcher")
	launcher._current = {"id": "fixture-game", "title": "Running game"}
	flow._poll()
	check(flow._menu == null and not flow._prompted.has("never-interrupt:ready"), "foreground game is never interrupted or receipt consumed")
	launcher._current = {}
	home.hide()
	flow._poll()
	check(flow._menu == null, "hidden home/details surface is not interrupted")
	home.show()
	installs.snapshot.status = "installing"
	flow._poll()
	check(flow._menu == null, "active installer is not interrupted")
	installs.snapshot.status = "idle"
	for pair in [["Settings", "settings_screen.gd"], ["Files", "files_screen.gd"], ["Power", "power_screen.gd"], ["Info", "info_screen.gd"]]:
		var owner: Node = root.get_node(pair[0])
		var surface: Control = load("res://src/" + pair[1]).new()
		owner.set("_screen", surface)
		flow._poll()
		check(flow._menu == null, pair[0] + " surface is not interrupted")
		owner.set("_screen", null)
		surface.free()
	var browser := root.get_node("Browser")
	browser._screen = Control.new()
	browser._visible = true
	flow._poll()
	check(flow._menu == null, "browser is not interrupted")
	browser._screen.free()
	browser._screen = null
	browser._visible = false
	launcher._current = {"id": "fixture-game", "title": "Minimized game"}
	launcher._minimized = true
	flow._poll()
	await process_frame
	check(flow._menu != null, "minimized game permits home receipt prompt")
	await dismiss()
	launcher._current = {}
	launcher._minimized = false
	flow._on_notification({"app": "Other app", "summary": "Download complete", "body": "/ignored.exe"})
	check(not has_request("download", "", "/ignored.exe"), "other applications cannot trigger FDM receipt workflow")
	flow._on_notification({"app": "FDM Controller", "summary": "Download complete", "body": "/legacy.exe"})
	flow._on_notification({"app": "FDM Controller", "summary": "Download complete", "body": "display only", "download": {"path": "/structured.exe", "torrent": true}})
	check(has_request("download", "", "/legacy.exe") and has_request("download", "", "/structured.exe"), "legacy and structured FDM completion preserve exact source path")
	var torrent_receipt := false
	for item in requests():
		if item.get("path", "") == "/structured.exe":
			torrent_receipt = item.get("torrent", false)
	check(torrent_receipt, "structured FDM torrent flag reaches worker")
	# Registration choices pass native game input vs pointer app input to helper.
	receipts([])
	var screen: Control = load("res://src/windows_install_screen.gd").new()
	root.add_child(screen)
	await process_frame
	var count: int = screen._rows.size()
	screen._add_choices({"id": "job-fixture", "status": "select", "choices": [{"id": "TEKKEN 8.exe", "title": "Tekken"}]})
	screen._rows[count].grab_focus()
	await press("ui_accept")
	screen._rows[count + 1].grab_focus()
	await press("ui_accept")
	await create_timer(0.15).timeout
	var args := FileAccess.get_file_as_string(folder.path_join("helper-args"))
	check(args.contains("register\njob-fixture\nTEKKEN 8.exe\ngamepad\n") and args.contains("register\njob-fixture\nTEKKEN 8.exe\npointer\n"), "controller registration distinguishes native game from pointer application")
	screen.queue_free()
	home.queue_free()
	print("Download install shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
