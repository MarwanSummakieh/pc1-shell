extends Node

signal changed()
signal opened()
signal closed()

const Page = preload("res://src/bluetooth_page.gd")
var snapshot: Dictionary = {}
var error := ""
var _folder := ""
var _raw := ""
var _screen: Control = null


func _ready() -> void:
	var fixture := OS.get_environment("MARWANOS_SHELL_STATUS_DIR")
	_folder = fixture.path_join("bluetooth") if not fixture.is_empty() else OS.get_environment("XDG_RUNTIME_DIR").path_join("marwanos/bluetooth")
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


func _poll() -> void:
	var path := _folder.path_join("state.json")
	var raw := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var data: Variant = JSON.parse_string(raw) if not raw.is_empty() else null
	if not data is Dictionary or absf(Time.get_unix_time_from_system() - float(data.get("updated_at", 0))) > 10:
		data = {"status": "unavailable", "available": false, "adapters": [], "devices": [], "prompt": {}, "error": "Bluetooth service unavailable. Try again."}
	var signature := JSON.stringify(data.duplicate())
	# Heartbeats do not rebuild controller rows or lose the selected device.
	data.erase("updated_at")
	signature = JSON.stringify(data)
	if signature != _raw:
		_raw = signature
		snapshot = data
		error = str(data.get("error", ""))
		changed.emit()


func request(action: String, target: String = "", extra: Dictionary = {}) -> bool:
	if DirAccess.make_dir_recursive_absolute(_folder) != OK:
		error = "Could not contact Bluetooth. Try again."
		changed.emit()
		return false
	var data := extra.duplicate()
	data.merge({"id": "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()], "action": action, "target": target}, true)
	var path := _folder.path_join("request.json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	FileAccess.set_unix_permissions(path + ".tmp", 384)
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return false
	return true


func open() -> void:
	if is_instance_valid(_screen):
		return
	_screen = Page.new()
	_screen.closed.connect(close)
	get_tree().root.add_child(_screen)
	opened.emit()
	request("refresh")


func close() -> void:
	if not is_instance_valid(_screen):
		return
	request("close")
	_screen.get_parent().remove_child(_screen)
	_screen.queue_free()
	_screen = null
	closed.emit()


func is_open() -> bool:
	return is_instance_valid(_screen)
