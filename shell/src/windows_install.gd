extends Node

signal changed()
signal opened()
signal closed()
signal guided_backgrounded()
signal guided_finished()

const InstallScreen = preload("res://src/windows_install_screen.gd")
const ListMenu = preload("res://src/list_menu.gd")
const SetupWizard = preload("res://src/windows_setup_wizard.gd")
const ACTIVE := ["queued", "downloading", "verifying", "installing", "removing"]
var _confirmation: Control = null
var _confirmation_focus: Control = null
var _confirmation_from_surface := false
var helper := "/usr/lib/marwanos/windows/manager.py"
var local_jobs: Array = []
var _local_signature := ""
var _local_libraries: Array = []
var _local_launch := ""
var snapshot: Dictionary = {}
var available := false
var home := ""
var message := ""
var _screen: Control = null
var guided_key := ""
var guided_source := ""
var _guided_pid := -1
var _guided_child := true
var _guided_owner_start := ""
var _guided_screen: Control = null
var _signature := ""
var _pending_until := 0


func _ready() -> void:
	if not OS.get_environment("MARWANOS_WINDOWS_HELPER").is_empty():
		helper = OS.get_environment("MARWANOS_WINDOWS_HELPER")
	home = OS.get_environment("MARWANOS_WINDOWS_HOME")
	if home.is_empty():
		home = OS.get_environment("HOME").path_join(".local/share/marwanos/windows")
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()
	Launcher.launch_finished.connect(_local_finished)


func is_open() -> bool:
	return is_instance_valid(_screen) or is_instance_valid(_confirmation) or (is_instance_valid(_guided_screen) and _guided_screen.visible)


func is_busy() -> bool:
	return _guided_pid > 0 or not _local_launch.is_empty() or (available and ACTIVE.has(str(snapshot.get("status", "")))) or Time.get_ticks_msec() < _pending_until


func guided_install(path: String) -> void:
	if path == guided_source and _guided_pid > 0:
		resume_guided()
		return
	if is_busy() or not Launcher.current_entry().is_empty():
		message = "Finish the current installation or close the running app first."
		changed.emit()
		return
	guided_key = "local-%d-%d" % [Time.get_ticks_usec(), randi()]
	guided_source = path
	_guided_child = true
	_guided_pid = OS.create_process(helper, ["guided", guided_key, path])
	if _guided_pid <= 0:
		message = "Could not start controller setup. Try again."
		changed.emit()
		return
	_guided_screen = SetupWizard.new()
	_guided_screen.job_key = guided_key
	_guided_screen.source_name = path.get_file()
	get_tree().root.add_child(_guided_screen)
	changed.emit()


func resume_guided() -> void:
	if is_instance_valid(_guided_screen):
		_guided_screen.show()
		_guided_screen.restore_focus()


func background_guided() -> void:
	if is_instance_valid(_guided_screen):
		_guided_screen.hide()
		changed.emit()
		guided_backgrounded.emit()


func stop_guided() -> void:
	if _guided_pid > 0:
		OS.create_process(helper, ["stop", guided_key])


func local_install(path: String, portable: bool = false) -> void:
	if is_busy() or not Launcher.current_entry().is_empty():
		message = "Finish the current installation first."
		changed.emit()
		return
	if not FileAccess.file_exists(helper):
		message = "Windows setup needs the updated system helper. Update this machine to continue."
		changed.emit()
		return
	_local_launch = "local-%d-%d" % [Time.get_ticks_usec(), randi()]
	message = ""
	Launcher.launch({"id": _local_launch, "title": "Setup: " + path.get_file(),
		"prefix": home.path_join("prefixes/" + _local_launch),
		"exec": [helper, "portable" if portable else "setup", _local_launch, path],
		"stop_exec": [helper, "stop", _local_launch], "input_mode": "pointer",
		"window_deadline": 600.0, "state": "installed", "icon": ""})


func _local_finished(entry: Dictionary) -> void:
	if str(entry.get("id", "")) != _local_launch or _local_launch.is_empty():
		return
	var key := _local_launch
	_local_launch = ""
	_poll_local()
	if not FileAccess.file_exists(home.path_join("jobs/" + key + ".json")):
		message = "Windows setup could not start. Check the system helper and try again."
	changed.emit()


func register_local(key: String, choice: String) -> void:
	if OS.create_process(helper, ["register", key, choice]) <= 0:
		message = "Could not add this program. Try again."
		changed.emit()


func confirm_remove(entry: Dictionary) -> void:
	var key := str(entry.get("recipe_id", ""))
	if key.is_empty() or not str(entry.get("id", "")).begins_with("managed."):
		return
	_confirm("Remove %s?" % str(entry.get("title", "application")),
		"Removes this app and its saved data. Portable source files are kept." if bool(entry.get("portable", false)) else
		"Removes this app and its saved data from this machine.", "Remove app", "remove", key)


func confirm_discard(job: Dictionary) -> void:
	_confirm("Remove setup files?", "Removes this unfinished installation. The original installer is kept.",
		"Remove setup files", "discard", str(job.get("id", "")))


func _confirm(title: String, note: String, label: String, verb: String, key: String) -> void:
	if is_instance_valid(_confirmation) or is_busy():
		return
	_confirmation_focus = get_viewport().gui_get_focus_owner()
	_confirmation = ListMenu.new()
	_confirmation.title_text = title
	_confirmation.note_text = note
	_confirmation.items = [{"id": "cancel", "label": "Cancel", "icon": "close"},
		{"id": "remove", "label": label, "icon": "close"}]
	_confirmation.chosen.connect(func(id: String):
		if id == "remove":
			_request({"verb": verb, "app_id": key}))
	_confirmation.closed.connect(_close_confirmation, CONNECT_ONE_SHOT)
	_confirmation_from_surface = is_instance_valid(_screen) or Files.is_open() or Browser.is_open() or Settings.is_open()
	if not _confirmation_from_surface:
		opened.emit()
	get_tree().root.add_child(_confirmation)


func _close_confirmation() -> void:
	_close_confirmation_deferred.call_deferred()


func _close_confirmation_deferred() -> void:
	if is_instance_valid(_confirmation):
		_confirmation.get_parent().remove_child(_confirmation)
		_confirmation.queue_free()
	_confirmation = null
	if not _confirmation_from_surface:
		closed.emit()
	_confirmation_from_surface = false
	if is_instance_valid(_confirmation_focus) and _confirmation_focus.is_visible_in_tree():
		_confirmation_focus.grab_focus()


func _json_files(directory: String) -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for name in DirAccess.get_files_at(directory):
		if not name.ends_with(".json"):
			continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(name)))
		if value is Dictionary:
			result.append(value)
	return result


func _poll_local() -> void:
	var jobs := _json_files(home.path_join("jobs"))
	# A shell refresh must not abandon a setup still owned by its helper.
	if _guided_pid <= 0:
		for job in jobs:
			if not job.get("guided", false) or str(job.get("status", "")) != "installing":
				continue
			var key := str(job.get("id", ""))
			var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(home.path_join("running/" + key + ".json"))) if FileAccess.file_exists(home.path_join("running/" + key + ".json")) else null
			var verified := false
			if record is Dictionary:
				var start := _process_start(int(record.get("owner", -1)))
				verified = not start.is_empty() and start == str(record.get("owner_start", ""))
			if verified:
				_guided_pid = int(record["owner"])
				_guided_child = false
				_guided_owner_start = str(record["owner_start"])
				guided_key = key
				guided_source = str(job.get("source", ""))
				_guided_screen = SetupWizard.new()
				_guided_screen.job_key = guided_key
				_guided_screen.source_name = guided_source.get_file()
				# Recovery can happen during autoload startup, before the home
				# scene is added. Place setup above it after the root is ready.
				get_tree().root.add_child.call_deferred(_guided_screen)
				break
	var apps: Array = []
	for app in _json_files(home.path_join("apps")):
		if not str(app.get("executable", "")).is_empty() and not str(app.get("id", "")).is_empty():
			if not FileAccess.file_exists(str(app.get("executable", ""))):
				app["subtitle"] = "App file unavailable. Reconnect its drive or remove this app."
			apps.append(app)
	var signature := JSON.stringify([jobs, apps])
	if signature != _local_signature:
		_local_signature = signature
		local_jobs = jobs
		_local_libraries = apps
		changed.emit()


func open() -> void:
	if is_open() or Launcher.is_busy() or Settings.is_open() or Power.is_open() or Info.is_open() or Files.is_open() or Browser.is_open():
		return
	_screen = InstallScreen.new()
	_screen.closed.connect(_finish, CONNECT_ONE_SHOT)
	opened.emit()
	get_tree().root.add_child(_screen)
	ShellLog.info("Windows installation screen opened")


func _finish() -> void:
	_finish_deferred.call_deferred()


func _finish_deferred() -> void:
	if is_instance_valid(_screen):
		_screen.get_parent().remove_child(_screen)
		_screen.queue_free()
	_screen = null
	closed.emit()


func install(recipe_id: String, source_id: String = "download") -> void:
	if is_busy():
		return
	_request({"verb": "install", "recipe_id": recipe_id, "source_id": source_id})


func cancel() -> void:
	if not ACTIVE.has(str(snapshot.get("status", ""))):
		return
	_request({"verb": "cancel", "job_id": str(snapshot.get("job_id", ""))})


func _request(request: Dictionary) -> void:
	if not available:
		message = "Installation is unavailable. Try again in a moment."
		changed.emit()
		return
	var directory := home.path_join("requests")
	var path := directory.path_join("%d-%d.json" % [Time.get_ticks_usec(), randi()])
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		message = "Could not start the request. Try again."
		changed.emit()
		return
	file.store_string(JSON.stringify(request))
	file.close()
	FileAccess.set_unix_permissions(path + ".tmp", 384)
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		DirAccess.remove_absolute(path + ".tmp")
		message = "Could not start the request. Try again."
	else:
		_pending_until = Time.get_ticks_msec() + 10000
		message = "Cancelling installation…" if request["verb"] == "cancel" else (
			"Removing application…" if request["verb"] in ["remove", "discard"] else "Starting installation…")
		ShellLog.info("Windows request: %s" % JSON.stringify(request))
	changed.emit()


func _poll() -> void:
	# Godot's Unix process check only accepts its own children. A recovered
	# helper belongs to the previous shell or systemd; verify its start identity.
	var guided_alive := false
	if _guided_pid > 0:
		guided_alive = OS.is_process_running(_guided_pid) if _guided_child else _process_start(_guided_pid) == _guided_owner_start
	if _guided_pid > 0 and not guided_alive:
		_guided_pid = -1
		guided_source = ""
		if is_instance_valid(_guided_screen):
			if _guided_screen.get_parent() != null:
				_guided_screen.get_parent().remove_child(_guided_screen)
			_guided_screen.queue_free()
		_guided_screen = null
		changed.emit()
		guided_finished.emit()
	_poll_local()
	var value: Variant = null
	var path := home.path_join("state.json")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			value = JSON.parse_string(file.get_as_text())
	var next: Dictionary = value if value is Dictionary else {}
	var age := Time.get_unix_time_from_system() - float(next.get("heartbeat", 0))
	var live := age >= -5 and age < 15
	next.erase("heartbeat")
	var signature := JSON.stringify(next) + str(live)
	var pending_expired := _pending_until > 0 and Time.get_ticks_msec() >= _pending_until
	if signature == _signature and not pending_expired:
		return
	_signature = signature
	snapshot = next
	available = live
	_pending_until = 0
	message = ""
	changed.emit()


func _process_start(pid: int) -> String:
	var path := "/proc/%d/stat" % pid
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var line := file.get_line()
	var fields := line.substr(line.rfind(")") + 1).strip_edges().split(" ", false)
	return fields[19] if fields.size() > 19 else ""


func library() -> Array:
	var entries: Variant = snapshot.get("library", [])
	var result: Array = entries.duplicate() if entries is Array else []
	for app in _local_libraries:
		var found := false
		for entry in result:
			if entry.get("id") == app.get("id"):
				found = true
		if not found:
			result.append(app)
	return result
