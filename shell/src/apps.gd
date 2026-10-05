extends Node

## ============================================================================
## THE APPLICATION CONTROL SEAM: asking for an application to be installed or
## removed.
##
## The wifi and update seams' shape, reused a third time: the shell writes a
## one-line request file into a player-owned directory and marwanos-appctl
## (root) consumes it. The shell runs no flatpak, holds no privilege, and
## learns what happened from the installed seam next door -- a removed
## application simply stops appearing in apps.tsv within a poll.
##
## WHY THIS SEAM EXISTS AT ALL. Until it did, an application could arrive (on
## the first boot with a network) and could never leave: removing a flatpak
## meant a terminal, and this appliance has no getty on tty1 by design. "You
## can install it but you can never remove it" is not a missing feature on a
## machine with a 15 GiB disk, it is a trap.
##
## THE REQUEST CARRIES AN ARGUMENT, which is what makes it different from the
## update seam's bare verbs, and the argument is checked on the ROOT side
## against a hand-written list of the applications this image ships. Nothing
## here needs to trust the shell; see /usr/lib/marwanos/appctl.
##
## Phase 1 deletes this file with the rest of them: marwand exposes install and
## uninstall over JSON-RPC and this becomes one call.
## ============================================================================

## Emitted when appctl's state file changes. States: idle, installing,
## uninstalling, done, failed, refused, unknown (nothing written yet -- a desk
## run, or too early in boot).
signal state_changed(state: String, app: String, detail: String)

const POLL_SECONDS := 2.0

const STATE_FILE := "/run/marwanos/apps.state"
const REQUEST_FILE := "/run/marwanos/apps/request"

const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

var state: String = "unknown"
var app: String = ""
var detail: String = ""

var _state_path := STATE_FILE
var _request_path := REQUEST_FILE
var _last_raw := ""
var _loaded := false


func _ready() -> void:
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_state_path = override.path_join(STATE_FILE.get_file())
		_request_path = override.path_join("apps.request")

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


## True while something is in flight and a second press would be a bounced
## button rather than a request for two.
func is_busy() -> bool:
	return state == "installing" or state == "uninstalling"


## WHAT THE OPTIONS MENU OFFERS FOR AN APPLICATION, defined once for the two
## screens that offer it: OPTIONS on a rail card (shell_root) and Y on a store
## page (stores_screen). It lived in card_menu.gd as a hard-coded const, which
## is why deleting that file in favour of the shared list_menu needed somewhere
## for it to go -- and this is the honest somewhere, beside request_uninstall,
## which is the thing the one item actually does.
##
## Uninstall is still the only entry, and it is the one that cannot be done any
## other way on a machine with no terminal. Adding a second is a line here and a
## branch in each caller's chosen-handler.
const OPTIONS_ITEMS := [
	{"id": "uninstall", "label": "Uninstall", "icon": "trash"},
]

## The sentence under the rows. NAMED, not "this cannot be undone": uninstalling
## is reversible -- the store page offers it back -- and the honest cost is the
## download, which is what somebody on a domestic line wants warned about.
const OPTIONS_NOTE := \
	"Removing frees the disk space. Installing it again means downloading it again."


func request_uninstall(app_id: String) -> void:
	ShellLog.info("apps: uninstall requested for %s" % app_id)
	_write_request("uninstall", app_id)


func request_install(app_id: String) -> void:
	ShellLog.info("apps: install requested for %s" % app_id)
	_write_request("install", app_id)


## `<verb>TAB<app id>`. Temp-then-rename and 0600, for the wifi seam's reasons:
## the service polls twice a second and deletes what it finds, so an in-place
## write can be read half-formed and destroyed, and Godot's FileAccess does not
## chmod.
func _write_request(verb: String, app_id: String) -> void:
	if app_id.is_empty():
		ShellLog.error("apps: refusing to write a %s request with no application" % verb)
		return

	var temp_path := _request_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("apps: cannot write a request to %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return
	file.store_line("%s\t%s" % [verb, app_id])
	file.close()
	FileAccess.set_unix_permissions(temp_path, 384)  # 0600; GDScript has no octal literal

	var error := DirAccess.rename_absolute(temp_path, _request_path)
	if error != OK:
		ShellLog.error("apps: cannot place the request at %s (error %d)"
			% [_request_path, error])
		DirAccess.remove_absolute(temp_path)


func _poll() -> void:
	var raw := _read_file(_state_path)
	if _loaded and raw == _last_raw:
		return
	_loaded = true
	_last_raw = raw

	var fields := raw.strip_edges().split("\t", true)
	state = fields[0] if fields.size() > 0 and not fields[0].is_empty() else "unknown"
	app = fields[1] if fields.size() > 1 else ""
	detail = fields[2] if fields.size() > 2 else ""

	ShellLog.info("apps state: %s %s %s" % [state, app, detail])
	state_changed.emit(state, app, detail)


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
