extends Node

## Linux audio state and atomic, acknowledged requests. Never blocks the UI.
signal changed()

var available := false
var outputs: Array = []
var inputs: Array = []
var streams: Array = []
var default_output := ""
var default_input := ""
var error := ""
var pending := false

var _folder := ""
var _request_id := ""
var _deadline := 0
var _last_raw := ""
var _serial := 0
var _local_error := false


func _ready() -> void:
	var fixture := OS.get_environment("MARWANOS_SHELL_STATUS_DIR")
	var runtime := OS.get_environment("XDG_RUNTIME_DIR")
	_folder = fixture.path_join("audio") if not fixture.is_empty() else runtime.path_join("marwanos/audio")
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


func selected(kind: String) -> Dictionary:
	var items: Array = outputs if kind == "output" else inputs
	var target := default_output if kind == "output" else default_input
	for item in items:
		if str(item.get("name", "")) == target:
			return item
	return {}


func summary() -> String:
	if not available:
		return "Audio unavailable"
	var output := selected("output")
	if output.is_empty():
		return "No output device"
	return "%s · %s" % [str(output.get("label", "Output")),
		"Muted" if output.get("muted", false) else "%d%%" % int(output.get("volume", 0))]


func request(kind: String, action: String, item: Dictionary, value: Variant = null) -> bool:
	if pending or (action != "refresh" and (not available or item.is_empty())):
		return false
	_serial += 1
	var request_id := "%d-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec(), _serial]
	var payload := {"id": request_id, "kind": kind, "action": action,
		"target": str(item.get("id" if kind == "stream" else "name", "")),
		"serial": str(item.get("serial", "")), "value": value}
	var path := _folder.path_join("request.json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		_local_error = true
		_request_id = ""
		error = "Could not send audio change. Try again."
		changed.emit()
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	FileAccess.set_unix_permissions(path + ".tmp", 384)
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		DirAccess.remove_absolute(path + ".tmp")
		error = "Could not send audio change. Try again."
		_local_error = true
		_request_id = ""
		changed.emit()
		return false
	_request_id = request_id
	_deadline = Time.get_ticks_msec() + 12000
	pending = true
	_local_error = false
	error = ""
	changed.emit()
	return true


func _poll() -> void:
	var path := _folder.path_join("state.json")
	var raw := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var data: Variant = JSON.parse_string(raw) if not raw.is_empty() else null
	var fresh := data is Dictionary and Time.get_unix_time_from_system() - float(data.get("updated_at", 0)) < 12.0
	if not fresh:
		if available:
			available = false
			outputs = []
			inputs = []
			streams = []
			error = "Audio service unavailable. Try again."
			changed.emit()
	elif raw != _last_raw:
		_last_raw = raw
		var was_available := available
		available = bool(data.get("available", false))
		if available and not was_available:
			_local_error = false
		outputs = data.get("outputs", [])
		inputs = data.get("inputs", [])
		streams = data.get("streams", [])
		default_output = str(data.get("default_output", ""))
		default_input = str(data.get("default_input", ""))
		var acknowledged := not _request_id.is_empty() and str(data.get("request_id", "")) == _request_id
		if acknowledged:
			_local_error = false
		if (not pending and not _local_error) or acknowledged:
			pending = false
			error = str(data.get("error", ""))
		changed.emit()
	if pending and Time.get_ticks_msec() >= _deadline:
		pending = false
		_local_error = true
		error = "Audio change timed out. Try again."
		changed.emit()
