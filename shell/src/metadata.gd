extends Node

signal changed()

var games: Dictionary = {}
var _folder := ""
var _raw := ""


func _ready() -> void:
	_folder = OS.get_environment("MARWANOS_METADATA_HOME")
	if _folder.is_empty():
		_folder = OS.get_environment("HOME").path_join(".local/share/marwanos/metadata")
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


func _poll() -> void:
	var path := _folder.path_join("state.json")
	if not FileAccess.file_exists(path):
		return
	var raw := FileAccess.get_file_as_string(path)
	if raw == _raw:
		return
	var data: Variant = JSON.parse_string(raw)
	if not data is Dictionary or not data.get("games") is Dictionary:
		return
	_raw = raw
	games = data.games
	changed.emit()


func enrich(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	var metadata: Dictionary = games.get(str(entry.get("id", "")), {})
	result["metadata"] = metadata
	if not str(metadata.get("title", "")).is_empty():
		result["title"] = metadata.title
	var title := str(metadata.get("overrides", {}).get("title", ""))
	if not title.is_empty():
		result["title"] = title
	# Keep installation source, executable, input mode and stable library ID local.
	var assets: Dictionary = metadata.get("assets", {})
	for kind in ["cover", "header"]:
		var path := str(assets.get(kind, {}).get("path", ""))
		if FileAccess.file_exists(path):
			result["cover"] = path
			break
	return result


func request(action: String, game_id: String, extra: Dictionary = {}) -> bool:
	var folder := _folder.path_join("requests")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return false
	var path := folder.path_join("%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	var data := extra.duplicate()
	data.merge({"action": action, "game_id": game_id}, true)
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
