extends RefCounted

## Home trash uses freedesktop metadata, so Files and desktop recovery agree.
## Renames are atomic; a failed trash never falls back to permanent deletion.
const Transfer = preload("res://src/file_transfer.gd")

static func trash_root() -> String:
	var data := OS.get_environment("XDG_DATA_HOME")
	if data.is_empty():
		data = OS.get_environment("HOME").path_join(".local/share")
	return data.path_join("Trash")

static func trash(path: String) -> int:
	var directory := trash_root()
	if Transfer.has_link_parent(directory):
		return ERR_INVALID_PARAMETER
	for folder in ["files", "info"]:
		var error := DirAccess.make_dir_recursive_absolute(directory.path_join(folder))
		if error != OK:
			return error
	var id := path.get_file() + ".%s.%s" % [Time.get_ticks_usec(), randi()]
	var destination := directory.path_join("files").path_join(id)
	var metadata := directory.path_join("info").path_join(id + ".trashinfo")
	var file := FileAccess.open(metadata, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("[Trash Info]\nPath=%s\nDeletionDate=%s\n" % [path.uri_encode(), Time.get_datetime_string_from_system()])
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(metadata)
		return error
	if not Transfer.atomic_move(path, destination):
		DirAccess.remove_absolute(metadata)
		# Removable filesystems have their own trash. Godot follows that policy;
		# those files remain recoverable on that drive through a desktop.
		return OS.move_to_trash(path)
	return OK

static func entries() -> Array:
	var result: Array = []
	var directory := trash_root().path_join("info")
	var dir := DirAccess.open(directory)
	if dir == null or Transfer.has_link_parent(directory):
		return result
	for name in dir.get_files():
		if not name.ends_with(".trashinfo") or dir.is_link(name):
			continue
		var id := name.trim_suffix(".trashinfo")
		var original := _original_path(id)
		if not original.is_absolute_path():
			continue
		if not Transfer.exists(trash_root().path_join("files").path_join(id)):
			continue
		result.append({"id": id, "name": original.get_file(), "path": original})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return result

static func _original_path(id: String) -> String:
	if id.is_empty() or id.contains("/") or id.contains("\\") or id in [".", ".."]:
		return ""
	var metadata := trash_root().path_join("info").path_join(id + ".trashinfo")
	if Transfer.is_link(metadata):
		return ""
	for line in FileAccess.get_file_as_string(metadata).split("\n"):
		if line.begins_with("Path="):
			return line.trim_prefix("Path=").uri_decode()
	return ""

static func restore(id: String) -> Dictionary:
	var original := _original_path(id)
	if not original.is_absolute_path() or original.simplify_path() != original:
		return {"ok": false, "message": "Wastebasket entry has no valid original path"}
	var source := trash_root().path_join("files").path_join(id)
	if not Transfer.exists(source) or Transfer.has_link_parent(source.get_base_dir()):
		return {"ok": false, "message": "Wastebasket file is unavailable"}
	if not DirAccess.dir_exists_absolute(original.get_base_dir()) or Transfer.has_link_parent(original.get_base_dir()):
		return {"ok": false, "message": "Original folder is unavailable; reconnect its drive"}
	var destination := Transfer.unique_destination(original.get_base_dir(), original.get_file(), DirAccess.dir_exists_absolute(source))
	if not Transfer.atomic_move(source, destination):
		return {"ok": false, "message": "Could not restore %s; its original folder must be on the same drive" % original.get_file()}
	DirAccess.remove_absolute(trash_root().path_join("info").path_join(id + ".trashinfo"))
	return {"ok": true, "message": "Restored %s" % destination.get_file(), "path": destination}
