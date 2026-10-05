extends Node

## ============================================================================
## THE UPDATE SEAM.
##
## The wifi seam's shape, reused deliberately: the shell writes a one-line
## request file and reads a one-line state file, and marwanos-update owns every
## call to bootc. Three verbs -- check, apply, restart -- and no arguments at
## all, so nothing crosses the boundary except which of the three was asked for.
##
## WHAT "UPDATE" MEANS HERE, because it is narrower than the word suggests and
## the screen has to be honest about it. This machine does not build anything:
## there is no Godot on it, on purpose. An update is a pre-built image pulled
## from the registry and staged as a new deployment, which the machine boots
## into on the next restart. The build happens on the build host, from the git
## repo, and is pushed to GHCR -- so "there is no update" often means "nobody
## has pushed one", which is a different problem from "this is current" and the
## screen says so.
## ============================================================================

## States: idle, checking, available, up-to-date, applying, staged, restarting,
## failed, unknown (nothing written yet -- a desk run, or too early in boot).
signal state_changed(state: String, detail: String)

const POLL_SECONDS := 2.0

const STATE_FILE := "/run/marwanos/update.state"
const REQUEST_FILE := "/run/marwanos/update/request"

const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

var state: String = "unknown"
var detail: String = ""

var _state_path := STATE_FILE
var _request_path := REQUEST_FILE
var _loaded := false


func _ready() -> void:
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_state_path = override.path_join(STATE_FILE.get_file())
		_request_path = override.path_join("update.request")

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


## True while something is in flight and a second press would be a bounced
## button rather than a request.
func is_busy() -> bool:
	return state == "checking" or state == "applying" or state == "restarting"


func request_check() -> void:
	ShellLog.info("update: check requested")
	_write_request("check")


func request_apply() -> void:
	ShellLog.info("update: apply requested")
	_write_request("apply")


func request_restart() -> void:
	ShellLog.info("update: restart requested")
	_write_request("restart")


## The power menu's two other verbs travel this seam too -- see the service's
## power-verbs block for why they are not a fourth daemon and not a polkit
## gamble from the session user. Neither produces a state to watch; the
## machine doing the thing is the feedback.
func request_poweroff() -> void:
	ShellLog.info("power: off requested")
	_write_request("poweroff")


func request_suspend() -> void:
	ShellLog.info("power: sleep requested")
	_write_request("suspend")


## Temp-then-rename and 0600, for the wifi seam's reasons: the service polls
## twice a second and deletes what it finds, so an in-place write can be read
## half-formed and destroyed, and Godot's FileAccess does not chmod.
func _write_request(verb: String) -> void:
	var temp_path := _request_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("update: cannot write a request to %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return
	file.store_line(verb)
	file.close()
	FileAccess.set_unix_permissions(temp_path, 384)  # 0600; GDScript has no octal literal

	var error := DirAccess.rename_absolute(temp_path, _request_path)
	if error != OK:
		ShellLog.error("update: cannot place the request at %s (error %d)"
			% [_request_path, error])
		DirAccess.remove_absolute(temp_path)


func _poll() -> void:
	var line := _read_line(_state_path)
	var word := line.get_slice("\t", 0).strip_edges()
	var rest := ""
	if line.contains("\t"):
		rest = line.substr(line.find("\t") + 1).strip_edges()
	if word.is_empty():
		word = "unknown"

	if _loaded and word == state and rest == detail:
		return
	_loaded = true
	state = word
	detail = rest
	ShellLog.info("update state: %s%s" % [state, (" (%s)" % detail) if not detail.is_empty() else ""])
	state_changed.emit(state, detail)


func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line()
