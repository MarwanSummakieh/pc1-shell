extends Node

## ============================================================================
## THE WIFI SEAM -- and the first one in this project that goes BOTH ways.
##
## Every other seam here is read-only: the system writes a file, the shell
## renders it. This one also lets the shell ASK for something, because an
## appliance that cannot join a network cannot be fixed from the couch, and
## ADR 0006's second amendment ("mutable settings wait for marwand") turned out
## to mean "this machine is unusable until someone brings a second computer".
## The fifth amendment records the reversal and its limits.
##
## THE SHELL STILL DOES NOT TOUCH NETWORKMANAGER. It writes one small file with
## a verb and at most two arguments; marwanos-wifi owns every nmcli call, every
## profile, and the passphrase's whole lifetime. What crosses the boundary is
## data, never a command -- there is no verb that means "run this", and an SSID
## from the air is passed by the service as an argv element rather than
## interpolated into a shell string.
##
## Requests are FIRE AND FORGET. There is no reply channel and no correlation
## id: the answer to "did it work" is the state file changing, which the screen
## is already watching. A request/response protocol would need matching,
## timeouts and retries -- all of which are marwand's job, and none of which
## three verbs justify.
## ============================================================================

## Emitted when the service's state word changes. States: "no-device",
## "rf-killed", "idle", "scanning", "connecting", "connected", "failed",
## "unknown" (nothing has been written yet -- a desk run, or too early in boot).
signal state_changed(state: String, detail: String)

## Emitted when the visible network list changes.
signal networks_changed(networks: Array)

## Matches the status seam. The service answers in well under a second for
## scan, and a connect takes as long as it takes; two seconds is the latency of
## the screen noticing either.
const POLL_SECONDS := 2.0

const STATE_FILE := "/run/marwanos/wifi.state"
const NETWORKS_FILE := "/run/marwanos/wifi.networks"
const REQUEST_FILE := "/run/marwanos/wifi/request"

## Shared with the other seams so one fixture directory drives every file the
## shell reads. Nothing on the appliance sets it.
const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

var state: String = "unknown"
var detail: String = ""
var networks: Array = []

var _state_path := STATE_FILE
var _networks_path := NETWORKS_FILE
var _request_path := REQUEST_FILE

var _last_networks_raw := ""
var _loaded := false


func _ready() -> void:
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_state_path = override.path_join(STATE_FILE.get_file())
		_networks_path = override.path_join(NETWORKS_FILE.get_file())
		# The request file keeps its own name but lands in the fixture
		# directory, so a desk run can show what the shell asked for without a
		# service to answer it.
		_request_path = override.path_join("wifi.request")

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


func is_usable() -> bool:
	return state != "no-device" and state != "rf-killed" and state != "unknown"


# ---------------------------------------------------------------------------
# Asking
# ---------------------------------------------------------------------------

## Ask the service to look for networks again.
func request_scan() -> void:
	_write_request(["scan"])


## Ask to join. An empty passphrase is correct for an open network; the service
## picks the right nmcli form.
func request_connect(ssid: String, password: String) -> void:
	ShellLog.info("wifi: requesting connection to \"%s\"" % ssid)
	_write_request(["connect", ssid, password])


## Ask to delete a saved profile. The recovery path for a network saved with
## the wrong passphrase, which otherwise fails on every boot with no way to
## clear it from the couch.
func request_forget(ssid: String) -> void:
	ShellLog.info("wifi: requesting forget of \"%s\"" % ssid)
	_write_request(["forget", ssid])


## One line per field, because a passphrase may contain any character a person
## can type -- including every separator a single-line format could use. Line
## breaks are the one thing a passphrase cannot contain here, and the service
## reads exactly three lines.
##
## NEVER LOGS THE ARGUMENTS. request_connect logs the SSID before calling in;
## this function stays silent so no future caller can accidentally log a
## secret by adding one here.
## WRITTEN TO A TEMP FILE AND RENAMED, like every other file in this project's
## seams -- and here it is not merely tidiness. The service polls twice a
## second and DELETES whatever it finds, so a poll landing between Godot's
## open() (which truncates in place) and close() would read an empty file,
## discard it, and leave the real write going to an unlinked inode. Requests
## are fire-and-forget with no reply channel, so the person would press A and
## nothing would ever happen, with nothing anywhere to say why.
##
## The temp file is chmod'ed BEFORE the rename: Godot's FileAccess uses fopen()
## and does not chmod, so a request would otherwise land 0644 under systemd's
## default umask -- readable by every other process running as `player`,
## which on this machine includes Steam and the browser. The directory mode
## alone was never the whole protection the comments claimed it was.
func _write_request(fields: Array) -> void:
	var temp_path := _request_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("wifi: cannot write a request to %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return
	for field in fields:
		# Belt and braces against the format being restructured from outside.
		# The service already refuses to list a network whose name contains
		# control characters, so a newline should never reach here -- but this
		# is the function that turns values into LINES, and a newline arriving
		# in one would silently shift every later field into the wrong slot.
		# Stripping is safe: a field that needed a newline would already be
		# unusable to nmcli.
		file.store_line(str(field).replace("\n", "").replace("\r", ""))
	# Closed explicitly rather than left to the GC: the service polls for this
	# file and would otherwise be racing Godot's finalisation to read a
	# complete one.
	file.close()

	# 384 is 0600. Spelled in decimal because GDSCRIPT HAS NO OCTAL LITERAL --
	# it takes decimal, 0x hex and 0b binary, and `0o600` is a parse error that
	# takes this entire autoload down with it, which in turn silently disables
	# every Wi-Fi feature while the shell still starts and looks fine.
	FileAccess.set_unix_permissions(temp_path, 384)

	var error := DirAccess.rename_absolute(temp_path, _request_path)
	if error != OK:
		ShellLog.error("wifi: cannot place the request at %s (error %d)"
			% [_request_path, error])
		DirAccess.remove_absolute(temp_path)


# ---------------------------------------------------------------------------
# Listening
# ---------------------------------------------------------------------------

func _poll() -> void:
	_poll_state()
	_poll_networks()


func _poll_state() -> void:
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
	ShellLog.info("wifi state: %s%s" % [state, (" (%s)" % detail) if not detail.is_empty() else ""])
	state_changed.emit(state, detail)


## Records are `<ssid>TAB<signal>TAB<security>TAB<in-use>`. The SSID is field 0
## and may itself contain anything except a tab, which is why the service puts
## the fixed-shape fields after it rather than before.
func _poll_networks() -> void:
	var raw := _read_file(_networks_path)
	if raw == _last_networks_raw:
		return
	_last_networks_raw = raw

	var found: Array = []
	for line in raw.split("\n", false):
		var fields := line.split("\t", true)
		if fields.size() < 4:
			continue
		var ssid := fields[0]
		if ssid.is_empty():
			continue
		found.append({
			"ssid": ssid,
			"signal": int(fields[1]),
			"security": fields[2],
			"in_use": fields[3] == "yes",
		})

	networks = found
	ShellLog.info("wifi: %d network(s) visible" % networks.size())
	networks_changed.emit(networks)


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line()
