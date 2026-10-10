extends Node

signal changed()

var games: Dictionary = {}
var _folder := ""
var _raw := ""


func _ready() -> void:
	set_profile()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)


func set_profile() -> void:
	_folder = OS.get_environment("MARWANOS_ACHIEVEMENTS_HOME")
	if _folder.is_empty():
		_folder = OS.get_environment("HOME").path_join(".local/share/marwanos/achievements")
	_folder = Profiles.personal_path("achievements", _folder)
	games = {}
	_raw = ""
	changed.emit()
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


func game(game_id: String) -> Dictionary:
	return games.get(game_id, {})


func request_refresh(game_id: String) -> bool:
	var folder := _folder.path_join("requests")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return false
	var path := folder.path_join("%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"action": "refresh", "game_id": game_id}))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
