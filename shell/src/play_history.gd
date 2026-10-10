extends Node

## Confirmed foreground time only. Wall time labels sessions; elapsed time uses
## the monotonic clock. A delayed observation never fills in unobserved time.
signal changed()

const CHECKPOINT_SECONDS := 15.0
const MAX_OBSERVATION_GAP := 5.0
var games: Dictionary = {}
var _folder := ""
var _active_id := ""
var _foreground := false
var _last_tick := 0
var _last_wall := 0.0
var _dirty_seconds := 0.0
var _save_failed := false


func _ready() -> void:
	set_profile()


func set_profile() -> void:
	_folder = OS.get_environment("MARWANOS_HISTORY_HOME")
	if _folder.is_empty():
		_folder = OS.get_environment("HOME").path_join(".local/share/marwanos/play-history")
	_folder = Profiles.personal_path("play-history", _folder)
	_dirty_seconds = 0.0
	reload()
	changed.emit()


func reload() -> void:
	games = {}
	for name in ["state.json", "state.backup.json"]:
		var parser := JSON.new()
		if not FileAccess.file_exists(_folder.path_join(name)) or parser.parse(FileAccess.get_file_as_string(_folder.path_join(name))) != OK:
			continue
		var value: Variant = parser.data
		if not value is Dictionary or value.get("schema_version") != 1 or not value.get("games") is Dictionary:
			continue
		var valid := true
		for record in value.games.values():
			if not record is Dictionary or not record.get("sessions") is Array or not _valid_number(record.get("total_seconds")) or not _valid_number(record.get("last_played_at")):
				valid = false
				break
			for session in record.sessions:
				if not session is Dictionary or not _valid_number(session.get("seconds")) or not _valid_number(session.get("started_at")) or not _valid_number(session.get("last_seen_at")):
					valid = false
		if valid:
			games = value.games
			break
	_active_id = ""
	_foreground = false
	# Recovery never claims the application continued while this observer was down.
	var recovered := false
	for record in games.values():
		for session in record.sessions:
			if str(session.get("end_reason", "")).is_empty():
				session["ended_at"] = session.get("last_seen_at", session.get("started_at", 0))
				session["end_reason"] = "observer-restarted"
				recovered = true
	if recovered:
		_save()


func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0


func is_game(entry: Dictionary) -> bool:
	if entry.get("state", "") != "installed" or entry.get("exec", []).is_empty():
		return false
	if str(entry.get("kind", "")) in ["installer", "tool", "application"]:
		return false
	var executable := str(entry.get("executable", "")).get_file().to_lower()
	if executable in ["setup.exe", "install.exe", "uninstall.exe", "unins000.exe"]:
		return false
	if entry.get("kind", "") == "game" or str(entry.get("id", "")).begins_with("rom."):
		return true
	# The metadata provider rejects Steam products whose type is not game.
	var metadata: Dictionary = entry.get("metadata", {})
	return metadata.get("provider", "") == "Steam Store" and not str(metadata.get("provider_id", "")).is_empty() and not str(metadata.get("description", "")).is_empty()


func sample(entry: Dictionary, foreground_confirmed: bool, monotonic_ms: int = -1, unix_seconds: float = -1.0) -> void:
	var tick := Time.get_ticks_msec() if monotonic_ms < 0 else monotonic_ms
	var wall := Time.get_unix_time_from_system() if unix_seconds < 0 else unix_seconds
	var id := str(entry.get("id", ""))
	if not _active_id.is_empty() and id != _active_id:
		finish("replaced", tick, wall)
	var active := foreground_confirmed and not id.is_empty() and is_game(entry)
	if _active_id.is_empty():
		if not active:
			return
		_active_id = id
		if not games.has(id):
			games[id] = {"total_seconds": 0.0, "last_played_at": 0.0, "sessions": []}
		games[id].sessions.append({"started_at": wall, "last_seen_at": wall, "seconds": 0.0, "end_reason": ""})
		games[id]["last_played_at"] = wall
		games[id]["title"] = str(entry.get("title", id))
		_last_tick = tick
		_last_wall = wall
		_foreground = true
		_save()
		changed.emit()
		return
	if active and _foreground:
		_account(tick, wall)
	var transition := active != _foreground
	_foreground = active
	_last_tick = tick
	_last_wall = wall
	if active:
		games[_active_id]["last_played_at"] = wall
		games[_active_id].sessions.back()["last_seen_at"] = wall
	if transition or _dirty_seconds >= CHECKPOINT_SECONDS:
		_save()
		changed.emit()


func _account(tick: int, wall: float) -> void:
	var elapsed := (tick - _last_tick) / 1000.0
	var wall_elapsed := wall - _last_wall
	# Suspend can advance either clock, depending on platform. Check both. A
	# backward wall-clock adjustment also breaks the observation interval.
	if elapsed <= 0 or elapsed > MAX_OBSERVATION_GAP or wall_elapsed < 0 or wall_elapsed > MAX_OBSERVATION_GAP:
		return
	games[_active_id]["total_seconds"] += elapsed
	games[_active_id].sessions.back()["seconds"] += elapsed
	games[_active_id].sessions.back()["last_seen_at"] = wall
	games[_active_id]["last_played_at"] = wall
	_dirty_seconds += elapsed


func pause(monotonic_ms: int = -1, unix_seconds: float = -1.0) -> void:
	if _active_id.is_empty() or not _foreground:
		return
	var tick := Time.get_ticks_msec() if monotonic_ms < 0 else monotonic_ms
	var wall := Time.get_unix_time_from_system() if unix_seconds < 0 else unix_seconds
	_account(tick, wall)
	_foreground = false
	_last_tick = tick
	_last_wall = wall
	_save()
	changed.emit()


func finish(reason: String = "exited", monotonic_ms: int = -1, unix_seconds: float = -1.0) -> void:
	if _active_id.is_empty():
		return
	pause(monotonic_ms, unix_seconds)
	var session: Dictionary = games[_active_id].sessions.back()
	session["ended_at"] = session.last_seen_at
	session["end_reason"] = reason
	_active_id = ""
	_foreground = false
	_save()
	changed.emit()


func stats(id: String) -> Dictionary:
	return games.get(id, {"total_seconds": 0.0, "last_played_at": 0.0, "sessions": []}).duplicate(true)


func enrich(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	if is_game(entry) or games.has(str(entry.get("id", ""))):
		result["play_history"] = stats(str(entry.get("id", "")))
	return result


func recently_played(entries: Array) -> Array:
	var decorated: Array = []
	for index in entries.size():
		var entry: Dictionary = enrich(entries[index])
		decorated.append({"entry": entry, "index": index, "last": float(entry.get("play_history", {}).get("last_played_at", 0))})
	decorated.sort_custom(func(a: Dictionary, b: Dictionary): return a.last > b.last if a.last != b.last else a.index < b.index)
	var result: Array = []
	for item in decorated:
		result.append(item.entry)
	return result


func duration(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	if minutes == 0:
		return "Less than a minute" if seconds > 0 else "Not played yet"
	return "%d h %d min" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d min" % minutes


func last_played(timestamp: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(timestamp), true).left(16) + " UTC" if timestamp > 0 else "Never"


func _atomic_write(path: String, text: String) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


func _save() -> bool:
	if DirAccess.make_dir_recursive_absolute(_folder) != OK:
		return _save_error()
	var path := _folder.path_join("state.json")
	# A second independently atomic snapshot protects against a damaged primary.
	var text := JSON.stringify({"schema_version": 1, "games": games}, "\t") + "\n"
	if not _atomic_write(path, text):
		return _save_error()
	_atomic_write(_folder.path_join("state.backup.json"), text)
	_dirty_seconds = 0.0
	_save_failed = false
	return true


func _save_error() -> bool:
	if not _save_failed:
		ShellLog.warn("Play history could not be saved; check free space and player home permissions.")
	_save_failed = true
	return false
