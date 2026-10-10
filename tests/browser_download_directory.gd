extends SceneTree

class DownloadView extends Control:
	signal download_updated(download: Dictionary)
	var directory := ""
	func set_download_directory(path: String) -> void:
		directory = path

var failures := 0

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var expected := OS.get_environment("HOME").path_join("Downloads")
	var system_directory := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	print("XDG download directory: %s; canonical: %s" % [system_directory, expected])
	check(system_directory != expected, "fixture exercises a missing or custom XDG Downloads directory")
	if DisplayServer.get_name() != "headless":
		var configured := OS.get_environment("HOME")
		if OS.get_environment("PC1_BROWSER_DIRECTORY_SCENARIO") == "custom":
			configured = configured.path_join("Custom downloads")
		check(system_directory == configured, "graphical OS lookup reproduces the configured XDG mismatch")
	var web: Control = load("res://src/browser_screen.gd").new()
	var view := DownloadView.new()
	web._configure_downloads(view)
	check(view.directory == expected, "engine destination uses the worker's HOME/Downloads root")
	var installs := root.get_node("WindowsInstall")
	DirAccess.make_dir_recursive_absolute(installs.home.path_join("requests"))
	installs.available = true
	var completed_path := expected.path_join("controller-download.exe")
	view.download_updated.emit({"id": 1, "name": "controller-download.exe", "path": completed_path, "state": "complete"})
	var found := false
	for name in DirAccess.get_files_at(installs.home.path_join("requests")):
		var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(installs.home.path_join("requests").path_join(name)))
		if request is Dictionary and request.get("verb") == "download" and request.get("path") == completed_path:
			found = true
	check(found, "engine completion forwards the canonical full path into the download worker request")
	check(web._downloads[1].path == completed_path, "Downloads menu retains the actual completed path")
	var downloads := root.get_node("Downloads")
	var task: Dictionary = downloads.browser_tasks.values().back()
	check(task.directory == view.directory, "shared Downloads retains the engine's canonical folder")
	var screen: Control = load("res://src/downloads_screen.gd").new()
	root.add_child(screen)
	screen._selected = task
	screen._task_action("folder")
	check(screen._modal.initial_directory == view.directory, "Open folder targets the same directory as the browser engine")
	root.remove_child(screen)
	screen.queue_free()
	web.free()
	view.free()
	print("Browser download directory checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
