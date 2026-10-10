extends Node

signal changed()
signal opened()
signal closed()

var snapshot: Dictionary = {}
var browser_tasks: Dictionary = {}
var _dismissed_browser: Dictionary = {}
var _screen: Control
var _folder := ""
var _signature := ""
var error := ""

func _ready() -> void:
	var fixture := OS.get_environment("MARWANOS_SHELL_STATUS_DIR")
	_folder = (fixture if not fixture.is_empty() else OS.get_environment("XDG_RUNTIME_DIR").path_join("marwanos")).path_join("downloads")
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()
	WindowsInstall.changed.connect(func(): changed.emit())

func _poll() -> void:
	var path := _folder.path_join("state.json")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not data is Dictionary or absf(Time.get_unix_time_from_system() - float(data.get("updated_at", 0))) > 10:
		data = {"available": false, "tasks": [], "error": "Downloads service unavailable. Try again."}
	data.erase("updated_at")
	var signature := JSON.stringify(data)
	if signature == _signature: return
	_signature = signature
	snapshot = data
	error = str(data.get("error", ""))
	changed.emit()

func tasks() -> Array:
	var result: Array = snapshot.get("tasks", []).duplicate(true)
	for task: Dictionary in browser_tasks.values():
		var ref: Variant = task.get("view")
		if task.get("status") == "active" and (not ref is WeakRef or not is_instance_valid(ref.get_ref())):
			task["status"] = "cancelled"
		result.append(task)
	for receipt: Dictionary in WindowsInstall.snapshot.get("downloads", []):
		if receipt.get("status") not in ["ready", "deferred", "installing", "installed"]: continue
		var source := str(receipt.get("source", ""))
		if source.is_empty(): continue
		var represented := false
		for task: Dictionary in result:
			if _contains_source(task, source): represented = true
		if not represented:
			result.append({"id": "receipt:" + str(receipt.get("id", "")), "name": source.get_file(),
				"kind": "setup", "status": "complete", "path": source, "directory": source.get_base_dir(),
				"total": 0, "received": 0, "speed": 0, "files": [], "error": "Ready to install"})
	# Retain unfinished setup after the original transfer leaves the queue.
	for job: Dictionary in WindowsInstall.local_jobs:
		if job.get("status") not in ["select", "failed"]:
			continue
		var source := str(job.get("source", ""))
		if source.is_empty(): continue
		var represented := false
		for task: Dictionary in result:
			if _contains_source(task, source): represented = true
		if not represented:
			result.append({"id": "setup:" + str(job.get("id", "")), "name": source.get_file(),
				"kind": "setup", "status": "complete", "path": source, "directory": source.get_base_dir(),
				"total": 0, "received": 0, "speed": 0, "files": [], "error": "Choose the program to play"})
	for task: Dictionary in result:
		if task.get("status") not in ["complete", "seeding"]: continue
		for source: String in installation_sources(task):
			var job := installation_job(source)
			if job.get("status") in ["select", "failed"] and not job.get("choices", []).is_empty():
				task["error"] = "Choose program to play"
				break
			if job.get("status") in ["done", "installed"]:
				task["error"] = "Installed — ready to play"
	return result


func _contains_source(task: Dictionary, source: String) -> bool:
	var path := str(task.get("path", "")).simplify_path()
	if not path.is_empty(): return path == source.simplify_path()
	var directory := str(task.get("directory", "")).simplify_path().trim_suffix("/")
	return not directory.is_empty() and source.simplify_path().begins_with(directory + "/")


func installation_sources(task: Dictionary) -> Array:
	var sources: Array = []
	for receipt: Dictionary in WindowsInstall.snapshot.get("downloads", []):
		var source := str(receipt.get("source", ""))
		if not source.is_empty() and _contains_source(task, source) and source not in sources:
			sources.append(source)
	for job: Dictionary in WindowsInstall.local_jobs:
		var source := str(job.get("source", ""))
		if not source.is_empty() and _contains_source(task, source) and source not in sources:
			sources.append(source)
	var path := str(task.get("path", ""))
	if path.get_extension().to_lower() in ["exe", "msi"] and path not in sources:
		sources.append(path)
	return sources


func installation_job(source: String) -> Dictionary:
	var latest: Dictionary = {}
	for job: Dictionary in WindowsInstall.local_jobs:
		if str(job.get("source", "")) == source and float(job.get("created_at", 0)) >= float(latest.get("created_at", 0)):
			latest = job
	return latest


## Close the queue before handing ownership to setup; Back restores the transfer.
func open_installation(source: String, start_setup: bool, task_id: String) -> void:
	if WindowsInstall.is_busy() or Launcher.is_busy():
		error = "Finish the current installation or close the running game first."
		changed.emit()
		return
	_finish()
	WindowsInstall.closed.connect(func():
		open()
		if is_instance_valid(_screen): _screen.focus_task.call_deferred(task_id), CONNECT_ONE_SHOT)
	if start_setup:
		DownloadInstall.completed(source)
		WindowsInstall.open_download(source)
	else:
		WindowsInstall.open_selection({"source": source, "title": source.get_file()})

func browser_updated(download: Dictionary, view: Control) -> void:
	var key := "browser:%d:%s" % [view.get_instance_id() if is_instance_valid(view) else 0, str(download.get("id", ""))]
	if _dismissed_browser.has(key): return
	var state := str(download.get("state", ""))
	var task := {"id": key, "browser_id": download.get("id", 0), "view": weakref(view) if is_instance_valid(view) else null,
		"name": str(download.get("name", "Download")), "kind": "browser", "directory": str(download.get("path", "")).get_base_dir(),
		"path": str(download.get("path", "")), "total": int(download.get("total", 0)), "received": int(download.get("received", 0)),
		"speed": 0, "status": {"downloading": "active", "failed": "error"}.get(state, state), "error": str(download.get("detail", "")), "files": []}
	browser_tasks[key] = task
	changed.emit()

func request(action: String, target: String = "", extra: Dictionary = {}) -> bool:
	if target.begins_with("browser:"):
		var task: Dictionary = browser_tasks.get(target, {})
		if action == "remove":
			_dismissed_browser[target] = true
			var ref: Variant = task.get("view")
			var view: Variant = ref.get_ref() if ref is WeakRef else null
			if is_instance_valid(view) and task.get("status") == "active": view.cancel_download(task.browser_id)
			browser_tasks.erase(target)
			changed.emit()
			return true
		return false
	if not snapshot.get("available", false):
		error = "Downloads service unavailable. Try again."
		changed.emit()
		return false
	var folder := _folder.path_join("requests")
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return false
	var ident := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var data := extra.duplicate()
	data.merge({"id": ident, "action": action, "target": target}, true)
	var path := folder.path_join(ident + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	file.close()
	FileAccess.set_unix_permissions(path + ".tmp", 384)
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: return false
	error = ""
	changed.emit()
	return true

func is_open() -> bool:
	return is_instance_valid(_screen)

func open() -> void:
	if is_open() or Launcher.is_busy() or Files.is_open() or Browser.is_open() or Settings.is_open() or Power.is_open() or Info.is_open() or WindowsInstall.is_open(): return
	_screen = load("res://src/downloads_screen.gd").new()
	_screen.closed.connect(close)
	opened.emit()
	get_tree().root.add_child(_screen)

func close() -> void:
	_finish.call_deferred()

func _finish() -> void:
	if not is_instance_valid(_screen): return
	_screen.get_parent().remove_child(_screen)
	_screen.queue_free()
	_screen = null
	closed.emit()
