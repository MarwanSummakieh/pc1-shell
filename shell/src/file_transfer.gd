extends RefCounted

## Bounded work on the UI thread: at most one 256 KiB write or 24 directory
## entries per frame. A hidden sibling holds each copy until it is complete.
## Cancellation only removes paths created by this job; originals stay intact.
const CHUNK := 256 * 1024
var running := false
var cancelling := false
var committing := false
var copied_bytes := 0
var completed: Array = []
var errors: Array = []
var skipped_links := 0
var current_name := ""
var _sources: Array = []
var _destination := ""
var _cut := false
var _source := ""
var _target := ""
var _stage := ""
var _tasks: Array = []
var _created: Array = []
var _originals: Array = []
var _remove: Array = []
var _reader: FileAccess
var _writer: FileAccess
var _reading_path := ""
var _writing_path := ""
var _expected_length := 0
var _expected_modified := 0
var _links_before := 0

func begin(sources: Array, destination: String, cut: bool) -> void:
	_sources = sources.duplicate()
	_destination = destination.simplify_path()
	if _destination != "/":
		_destination = _destination.trim_suffix("/")
	_cut = cut
	running = true

func cancel() -> void:
	if committing:
		return
	cancelling = true
	_sources.clear()
	_reader = null
	_writer = null
	_tasks.clear()

static func is_link(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path.get_file())

static func exists(path: String) -> bool:
	return is_link(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

static func has_link_parent(path: String) -> bool:
	var cursor := path.simplify_path()
	while cursor != cursor.get_base_dir():
		if is_link(cursor):
			return true
		cursor = cursor.get_base_dir()
	return false

static func unique_destination(directory: String, name: String, folder: bool) -> String:
	var result := directory.path_join(name)
	var index := 0
	while exists(result):
		index += 1
		var stem := name if folder else name.get_basename()
		var ext := "" if folder else name.get_extension()
		result = directory.path_join(stem + (" (copy)" if index == 1 else " (copy %d)" % index) + ("." + ext if not ext.is_empty() else ""))
	return result

static func atomic_move(source: String, destination: String) -> bool:
	## Godot's Linux rename falls back to a synchronous copy on EXDEV. GNU mv's
	## no-copy mode gives a real atomic rename or failure, including big files.
	if exists(destination):
		return false
	if OS.get_name() == "Linux":
		# create_process passes argv literally. OS.execute uses a shell in this
		# pinned engine and filenames may contain shell metacharacters.
		var pid := OS.create_process("mv", ["--no-copy", "--no-clobber", "--", source, destination])
		if pid <= 0:
			return false
		var deadline := Time.get_ticks_msec() + 500
		while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(1)
		if OS.is_process_running(pid):
			OS.kill(pid)
		return not exists(source) and exists(destination)
	return DirAccess.rename_absolute(source, destination) == OK

func step() -> void:
	if not running:
		return
	if cancelling or (not _created.is_empty() and _tasks.is_empty() and _reader == null and _stage.is_empty()):
		_cleanup_step()
		return
	if committing:
		_remove_step()
		return
	if _reader != null:
		_copy_chunk()
		return
	if not _tasks.is_empty():
		_scan_step()
		return
	if not _stage.is_empty():
		_commit_copy()
		return
	if _sources.is_empty():
		running = false
		return
	_start_source(str(_sources.pop_front()))

func _start_source(source: String) -> void:
	_source = source.simplify_path().trim_suffix("/")
	if not _source.is_absolute_path():
		_fail("Choose an absolute source path")
		return
	current_name = _source.get_file()
	var folder := DirAccess.dir_exists_absolute(_source)
	if not exists(_source):
		_fail("%s is gone" % current_name)
		return
	if has_link_parent(_source) or has_link_parent(_destination):
		_fail("Links are not copied; choose the real folder")
		return
	if folder and (_destination == _source or _destination.begins_with(_source + "/")):
		_fail("Cannot paste %s into itself" % current_name)
		return
	if not DirAccess.dir_exists_absolute(_destination):
		_fail("Destination folder is unavailable")
		return
	if _cut and _source.get_base_dir() == _destination:
		completed.append({"source": _source, "name": current_name})
		return
	_target = unique_destination(_destination, current_name, folder)
	if _cut and atomic_move(_source, _target):
		completed.append({"source": _source, "name": _target.get_file()})
		return
	_stage = _destination.path_join(".marwanos-transfer-%s-%s" % [Time.get_ticks_usec(), randi()])
	_links_before = skipped_links
	_originals.clear()
	_tasks = [{"source": _source, "dest": _stage, "folder": folder}]

func _scan_step() -> void:
	for _budget in 24:
		if _tasks.is_empty() or _reader != null:
			break
		var task: Dictionary = _tasks.pop_back()
		var source := str(task["source"])
		var dest := str(task["dest"])
		if task.has("iterator"):
			var iterator: DirAccess = task["iterator"]
			var name := iterator.get_next()
			if name.is_empty():
				iterator.list_dir_end()
			else:
				_tasks.append(task)
				if name not in [".", ".."]:
					_tasks.append({"source": source.path_join(name), "dest": dest.path_join(name), "folder": iterator.current_is_dir()})
			continue
		if is_link(source):
			skipped_links += 1
			continue
		if has_link_parent(source.get_base_dir()) or has_link_parent(dest.get_base_dir()):
			_fail("Folder changed to a link; original kept")
			return
		if bool(task["folder"]):
			var dir := DirAccess.open(source)
			if dir == null:
				_fail("Cannot read %s" % source.get_file())
				return
			if exists(dest) or DirAccess.make_dir_absolute(dest) != OK:
				_fail("Cannot create copy of %s" % source.get_file())
				return
			_created.append(dest)
			_originals.append({"path": source, "folder": true})
			dir.include_hidden = true
			if dir.list_dir_begin() != OK:
				_fail("Cannot list %s" % source.get_file())
				return
			_tasks.append({"source": source, "dest": dest, "iterator": dir})
		else:
			_reader = FileAccess.open(source, FileAccess.READ)
			if _reader == null or exists(dest):
				_fail("Cannot read %s" % source.get_file())
				return
			_writer = FileAccess.open(dest, FileAccess.WRITE)
			if _writer == null:
				_fail("Cannot write %s" % dest.get_file())
				return
			_created.append(dest)
			_reading_path = source
			_writing_path = dest
			_expected_length = _reader.get_length()
			_expected_modified = FileAccess.get_modified_time(source)
			_originals.append({"path": source, "folder": false, "length": _expected_length, "modified": _expected_modified})

func _copy_chunk() -> void:
	if has_link_parent(_reading_path) or has_link_parent(_writing_path):
		_fail("Folder changed to a link; original kept")
		return
	var remaining := _expected_length - _reader.get_position()
	var amount := mini(CHUNK, remaining)
	var bytes := _reader.get_buffer(amount)
	if bytes.size() != amount:
		_fail("Source changed while copying %s" % current_name)
		return
	_writer.store_buffer(bytes)
	if _writer.get_error() != OK:
		_fail("Could not write %s; check free space" % current_name)
		return
	copied_bytes += bytes.size()
	if _reader.get_position() >= _expected_length:
		_writer.flush()
		if _writer.get_error() != OK:
			_fail("Could not finish writing %s" % current_name)
			return
		if _reader.get_length() != _expected_length or FileAccess.get_modified_time(_reading_path) != _expected_modified or is_link(_reading_path):
			_fail("Source changed while copying %s" % current_name)
			return
		_reader = null
		_writer = null
		if OS.get_name() == "Linux":
			FileAccess.set_unix_permissions(_writing_path, FileAccess.get_unix_permissions(_reading_path))

func _commit_copy() -> void:
	if exists(_target) or has_link_parent(_destination):
		_fail("Destination changed; original kept")
		return
	if not atomic_move(_stage, _target):
		_fail("Could not finish copy of %s" % current_name)
		return
	_stage = ""
	_created.clear()
	if _cut and skipped_links != _links_before:
		errors.append("Copied %s, but kept the original because it contains links" % current_name)
		return
	if _cut:
		for original in _originals:
			var path := str(original["path"])
			if is_link(path) or not exists(path):
				errors.append("Copied %s; original changed and was kept" % current_name)
				return
			if not bool(original["folder"]):
				var file := FileAccess.open(path, FileAccess.READ)
				if file == null or file.get_length() != int(original["length"]) or FileAccess.get_modified_time(path) != int(original["modified"]):
					errors.append("Copied %s; original changed and was kept" % current_name)
					return
		_remove = _originals.duplicate()
		committing = true
	else:
		completed.append({"source": _source, "name": _target.get_file()})

func _remove_step() -> void:
	for _budget in 24:
		if _remove.is_empty():
			committing = false
			completed.append({"source": _source, "name": _target.get_file()})
			return
		var original: Dictionary = _remove.pop_back()
		var path := str(original["path"])
		if has_link_parent(path) or DirAccess.remove_absolute(path) != OK:
			errors.append("Copied %s; some original files could not be removed" % current_name)
			_remove.clear()
			committing = false
			return

func _fail(message: String) -> void:
	errors.append(message)
	_reader = null
	_writer = null
	_tasks.clear()
	_stage = ""

func _cleanup_step() -> void:
	for _budget in 24:
		if _created.is_empty():
			if cancelling:
				running = false
			return
		var path := str(_created.pop_back())
		if has_link_parent(path.get_base_dir()):
			errors.append("Unfinished folder changed to a link; cleanup stopped: %s" % path)
		elif DirAccess.remove_absolute(path) != OK and exists(path):
			errors.append("Could not remove unfinished copy: %s" % path)

func finish_cleanup() -> void:
	## Closing the screen still leaves no open file handle or abandoned stage.
	cancel()
	while running:
		step()
