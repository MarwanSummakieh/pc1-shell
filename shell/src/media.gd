extends Node

## ============================================================================
## THE REMOVABLE MEDIA SEAM -- one verb, "eject".
##
## Mounting is NOT here and deliberately never will be: a stick is mounted by
## udev the moment it is plugged in (see /usr/lib/marwanos/usbmount), before
## anything in the shell knows it exists, and a file manager that had to ASK for
## a mount would be a file manager that shows nothing until someone finds the
## right button. What the shell does need is the other direction -- taking one
## out safely -- because an unmount needs root and a person on a couch pulling a
## stick mid-write loses the copy they just made.
##
## The update and wifi seams' shape, reused verbatim:
##
##   the shell writes  /run/marwanos/media/request   (0700 player-owned dir)
##   this reads        /run/marwanos/media.state     <state>TAB<mount>TAB<detail>
##
## WHAT CROSSES THE BOUNDARY IS A MOUNT POINT, and the privileged half is what
## narrows it: marwanos-usbmount refuses any path that is not a directory
## directly under /run/media/<user>/ that it is currently the mounter of. The
## shell offering only paths it found by listing that directory is a
## convenience, not the boundary -- see the script.
## ============================================================================

## States: idle, ejecting, done, failed, refused, unknown (nothing written yet).
signal state_changed(state: String, mount: String, detail: String)

const POLL_SECONDS := 1.0

const STATE_FILE := "/run/marwanos/media.state"
const REQUEST_FILE := "/run/marwanos/media/request"

const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

var state: String = "unknown"
var mount: String = ""
var detail: String = ""

var _state_path := STATE_FILE
var _request_path := REQUEST_FILE
var _loaded := false


func _ready() -> void:
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_state_path = override.path_join(STATE_FILE.get_file())
		_request_path = override.path_join("media.request")

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


## True while an eject is in flight. A second press on the same drive while the
## first is still unmounting is a bounced button, and the file manager guards
## on this rather than counting presses.
func is_busy() -> bool:
	return state == "ejecting"


func request_eject(mount_path: String) -> void:
	if mount_path.is_empty():
		return
	ShellLog.info("media: eject requested for %s" % mount_path)
	_write_request("eject\t" + mount_path)


## Temp-then-rename and 0600, for the wifi seam's reasons: the service polls
## twice a second and deletes what it finds, so an in-place write can be read
## half-formed and destroyed, and Godot's FileAccess does not chmod.
func _write_request(line: String) -> void:
	var temp_path := _request_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("media: cannot write a request to %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return
	file.store_line(line)
	file.close()
	FileAccess.set_unix_permissions(temp_path, 384)  # 0600; GDScript has no octal literal

	var error := DirAccess.rename_absolute(temp_path, _request_path)
	if error != OK:
		ShellLog.error("media: cannot place the request at %s (error %d)"
			% [_request_path, error])
		DirAccess.remove_absolute(temp_path)


func _poll() -> void:
	var line := _read_line(_state_path)
	var parts := line.split("\t")
	var word := parts[0].strip_edges() if parts.size() > 0 else ""
	var which := parts[1].strip_edges() if parts.size() > 1 else ""
	var said := parts[2].strip_edges() if parts.size() > 2 else ""
	if word.is_empty():
		word = "unknown"

	if _loaded and word == state and which == mount and said == detail:
		return
	_loaded = true
	state = word
	mount = which
	detail = said
	ShellLog.info("media state: %s%s%s"
		% [state,
			(" for %s" % mount) if not mount.is_empty() else "",
			(" (%s)" % detail) if not detail.is_empty() else ""])
	state_changed.emit(state, mount, detail)


func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line()
