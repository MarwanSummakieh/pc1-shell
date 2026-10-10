extends Node

## Local console users. Installs stay in the common library; personal state is scoped.
signal changed()
signal opened()
signal closed()

const UsersScreen = preload("res://src/users_screen.gd")
const COLORS := ["#6e9eae", "#a18bba", "#b78b79", "#829d82", "#b49e69", "#7e95b7"]
const MAX_USERS := 8
var users: Array = []
var active := "owner"
var folder := ""
var error := ""
var available := true
var _screen: UsersScreen
var _switching := false

func _ready() -> void:
	folder = OS.get_environment("MARWANOS_PROFILES_HOME")
	if folder.is_empty():
		var home := OS.get_environment("HOME")
		folder = home.path_join(".local/share/marwanos/profiles") if not home.is_empty() else ProjectSettings.globalize_path("user://profiles")
	OS.set_environment("MARWANOS_PROFILES_HOME", folder)
	reload()

func reload() -> void:
	error = ""
	available = false
	var path := folder.path_join("users.json")
	if FileAccess.file_exists(path):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary or value.get("schema_version") != 1 or not value.get("users") is Array:
			error = "User profiles could not be read. Restore users.json before playing."
			return
		var loaded: Array = value.users
		var ids: Array = []
		for row in loaded:
			if not row is Dictionary or not _valid_id(str(row.get("id", ""))) or str(row.get("name", "")).strip_edges().is_empty() or ids.has(row.id):
				error = "User profiles are invalid. Restore users.json before playing."
				return
			ids.append(row.id)
		if not ids.has("owner") or not ids.has(value.get("active")):
			error = "User profiles are invalid. Restore users.json before playing."
			return
		users = loaded
		active = value.active
	else:
		var legacy := folder.get_base_dir().path_join("profile-name")
		var name := FileAccess.get_file_as_string(legacy).strip_edges() if FileAccess.file_exists(legacy) else OS.get_environment("MARWANOS_DISPLAY_NAME")
		users = [{"id": "owner", "name": name if not name.is_empty() else "Player", "color": COLORS[0]}]
		active = "owner"
		if not _save():
			return
	OS.set_environment("MARWANOS_PROFILE_ID", active)
	available = true

func _valid_id(value: String) -> bool:
	if value == "owner":
		return true
	if not value.begins_with("user-") or value.length() != 37:
		return false
	for character in value.trim_prefix("user-"):
		if not character in "0123456789abcdef":
			return false
	return true

func current() -> Dictionary:
	for user in users:
		if user.id == active:
			return user.duplicate()
	return {"id": "owner", "name": "Player", "color": COLORS[0]}

func personal_path(section: String, legacy: String = "") -> String:
	if active == "owner" and not legacy.is_empty():
		return legacy
	return folder.path_join(active).path_join(section)

func add_user(name: String, color: String) -> String:
	if not available:
		return ""
	var clean := _clean_name(name)
	if clean.is_empty():
		error = "Enter a name."
		return ""
	if users.size() >= MAX_USERS:
		error = "This console supports up to %d users." % MAX_USERS
		return ""
	var key := "user-" + Crypto.new().generate_random_bytes(16).hex_encode()
	users.append({"id": key, "name": clean, "color": color if COLORS.has(color) else COLORS[0]})
	if not _save():
		users.pop_back()
		return ""
	changed.emit()
	return key

func edit_user(name: String, color: String) -> bool:
	if not available:
		return false
	var clean := _clean_name(name)
	if clean.is_empty():
		error = "Enter a name."
		return false
	var previous := users.duplicate(true)
	for user in users:
		if user.id == active:
			user.name = clean
			user.color = color if COLORS.has(color) else COLORS[0]
	if not _save():
		users = previous
		return false
	changed.emit()
	return true

func _clean_name(value: String) -> String:
	return value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ").left(24)

func _save() -> bool:
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		error = "Could not save the user. Check free space and try again."
		return false
	var path := folder.path_join("users.json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "Could not save the user. Check free space and try again."
		return false
	file.store_string(JSON.stringify({"schema_version": 1, "active": active, "users": users}))
	file.flush()
	var failed := file.get_error() != OK
	file.close()
	if failed or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Could not save the user. Check free space and try again."
		return false
	error = ""
	return true

func is_open() -> bool:
	return is_instance_valid(_screen)

func switch_blocker() -> String:
	if not Launcher.current_entry().is_empty() or WindowsInstall.is_busy():
		return "Close the running game or app and finish installation before switching users."
	if int(SteamEmbed.snapshot.get("game_id", 0)) > 0:
		return "Close the Steam game before switching users."
	return ""

func launch_error(entry: Dictionary) -> String:
	if active != "owner" and str(entry.get("executable", "")).replace("\\", "/").contains("/drive_c/users/"):
		return "This app is installed in a user's save folder. Reinstall it to C:\\Games to share it between users."
	return ""

func helper_path() -> String:
	var override := OS.get_environment("MARWANOS_PROFILES_HELPER")
	return override if not override.is_empty() else "/usr/lib/marwanos/profiles.py"

func select_user(key: String) -> bool:
	if _switching or not available:
		return false
	var found := false
	for user in users:
		found = found or user.id == key
	if not found:
		error = "Choose an existing user."
		return false
	error = switch_blocker()
	if not error.is_empty():
		return false
	_switching = true
	SteamEmbed.hide_pane()
	var previous := active
	var helper := helper_path()
	if OS.has_feature("linux") and FileAccess.file_exists(helper):
		var result := folder.path_join("switch-%d.json" % Time.get_ticks_usec())
		var pid := OS.create_process("/usr/bin/python3", [helper, "activate", key, result])
		if pid <= 0:
			error = "Could not switch users. Try again."
			_switching = false
			return false
		while OS.is_process_running(pid):
			await get_tree().process_frame
		var response: Variant = JSON.parse_string(FileAccess.get_file_as_string(result)) if FileAccess.file_exists(result) else null
		DirAccess.remove_absolute(result)
		if not response is Dictionary or not response.get("ok", false):
			error = str(response.get("error", "Could not switch users. Try again.")) if response is Dictionary else "Could not switch users. Try again."
			_switching = false
			return false
	PlayHistory.finish("user-switched")
	active = key
	if not OS.has_feature("linux") or not FileAccess.file_exists(helper):
		if not _save():
			active = previous
			_switching = false
			return false
	OS.set_environment("MARWANOS_PROFILE_ID", active)
	PlayHistory.set_profile()
	Achievements.set_profile()
	Browser.reset_for_user()
	_switching = false
	changed.emit()
	return true

func open(startup: bool = false) -> void:
	if is_open() or _switching:
		return
	if not startup and (Settings.is_open() or Power.is_open() or Info.is_open() or Files.is_open() or Browser.is_open() or Downloads.is_open() or WindowsInstall.is_open()):
		return
	_screen = UsersScreen.new()
	_screen.startup = startup
	_screen.closed.connect(_close, CONNECT_ONE_SHOT)
	opened.emit()
	get_tree().root.add_child(_screen)

func _close() -> void:
	var screen := _screen
	_screen = null
	if is_instance_valid(screen):
		screen.get_parent().remove_child(screen)
		screen.queue_free()
	closed.emit()
