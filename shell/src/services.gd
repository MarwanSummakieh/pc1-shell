extends Node

## ============================================================================
## THE SERVICE SEAM: what is running in the background, and asking it to stop.
##
## The top bar's left corner is a pill that carries a dot when something needs
## attention, and the menu behind it lists one row per background process and
## can start and stop them. Steam is the only one today; Discord and whatever
## follows are a row in SERVICES.
##
## THE SEAM SAYS "SERVICE", THE UI SAYS "PROCESS", and the split is deliberate
## rather than sloppy. This file is about supervised units and wish files, which
## is what the session's supervisor calls them; what a person sees on the
## television is Steam quietly running while they are on the home screen. See
## process_menu.gd's heading.
##
## THIS SEAM HAS NO PRIVILEGED HALF, and it is the only one here that does not.
## wifi, update, appctl, steam, display and window all cross a uid boundary:
## the shell asks, root acts. This one does not cross anything. The background
## Steam client runs as `player`, marwanos-session runs as `player`, this shell
## runs as `player` -- three processes, one uid, arguing about a flatpak that uid
## owns. So there is no allow-list to enforce and no hostile writer to defend
## against, and inventing a root service to carry the request would be ceremony
## around a file the same user writes and reads.
##
## The files live under XDG_RUNTIME_DIR, which logind made for this user and
## nothing else can write:
##
##   the session writes  <runtime>/marwanos/services/<id>.state    running|stopped|crashed
##   this writes         <runtime>/marwanos/services/<id>.wanted   1|0
##
## `crashed` is stopped-with-a-diagnosis: the supervisor hit its fast-failure
## limit and is retrying on a slow backoff. A on the row still means "start",
## and the supervisor treats the rewritten wish as permission to retry
## immediately -- the mtime bump is the signal, which is why set_wanted always
## writes even when the file already says 1.
##
## A WISH, NOT AN ACTION, and that distinction is the whole design. The session's
## supervisor restarts the client when it exits -- that is its job -- so a shell
## that killed Steam itself would watch it come back thirty seconds later and
## read as a switch that does not switch. Writing `wanted` puts the decision
## where the lifecycle already lives. See supervise_steam.
##
## ABSENT MEANS RUNNING. A machine nobody has touched has no `.wanted` file and
## starts its services exactly as it did before this seam existed; the file
## appears only once somebody has chosen otherwise.
## ============================================================================

## Emitted when any service's state changes. Both consumers -- the pill's badge
## and the menu's rows -- redraw everything they own from it, and a per-service
## signal would be plumbing for nothing on a list this short.
signal services_changed()

const POLL_SECONDS := 2.0

## The services this shell knows how to show, in the order they appear in the
## menu. `app_id` is the desktop-entry id the installed seam reports, and it is
## what decides whether the row exists at all: a machine without Discord should
## show no Discord row rather than a permanently stopped one for something
## nobody installed. It is also what hides the whole pill on a machine that has
## none of them -- see process_pill.refresh.
const SERVICES := [
	{
		"id": "steam",
		"label": "Steam",
		"app_id": "steam",
		"detail": "Keeps your library ready and games launching fast",
	},
]

## Where the session put them. XDG_RUNTIME_DIR is set by pam_systemd for the
## session user; a desk run without one falls back to the same path the session
## script falls back to, so the two agree about where nothing is.
var _dir := ""

## id -> "running" | "stopped" | "unknown"
var _states: Dictionary = {}

## What this shell last asked for, so a row can say "stopping" while the
## supervisor is still noticing. Cleared once the state file agrees.
var _pending: Dictionary = {}


func _ready() -> void:
	var runtime := OS.get_environment("XDG_RUNTIME_DIR")
	if runtime.is_empty():
		runtime = "/run/user/%d" % _uid()
	_dir = runtime.path_join("marwanos/services")

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()
	ShellLog.info("services seam watching %s" % _dir)


## The session runs as the one user this appliance has; asking the OS is still
## better than baking 1000 into a second file.
func _uid() -> int:
	var out: Array = []
	if OS.execute("id", PackedStringArray(["-u"]), out, true) == 0 and not out.is_empty():
		return int(str(out[0]).strip_edges())
	return 1000


## Every service that should be drawn, in bar order, as
## {"id", "label", "detail", "state", "installed"}.
##
## A service whose application is NOT installed is left out entirely -- see
## SERVICES. The rail already tells somebody what this machine has; a grey icon
## for something never installed would be the bar inventing an absence.
func visible_services() -> Array:
	var result: Array = []
	for service in SERVICES:
		var app_id := str(service.get("app_id", ""))
		if not _installed(app_id):
			continue
		result.append({
			"id": str(service["id"]),
			"label": str(service["label"]),
			"detail": str(service.get("detail", "")),
			"app_id": app_id,
			"state": state_of(str(service["id"])),
		})
	return result


func _installed(app_id: String) -> bool:
	if app_id.is_empty():
		return false
	for app in Installed.apps:
		var id := str(app.get("id", ""))
		var matches := id == app_id or (app_id == "steam" and id == "com.valvesoftware.Steam")
		if matches and str(app.get("state", "")) == "installed":
			return true
	return false


## "running", "stopped", "crashed", or "unknown" when nothing has been written
## yet -- a desk run, or a boot too early for the supervisor to have said
## anything. Unknown is drawn as grey but worded differently; see process_menu.
func state_of(id: String) -> String:
	return str(_states.get(id, "unknown"))


## What this shell last asked for and has not seen honoured: "start", "stop", or
## empty. The supervisor polls every two seconds, so there is a real window in
## which the icon must say something other than the truth it can see.
func pending_of(id: String) -> String:
	return str(_pending.get(id, ""))


func is_running(id: String) -> bool:
	return state_of(id) == "running"


## Ask for a service to run, or to stop. Takes effect within a couple of seconds;
## see the header for why this writes a wish rather than killing anything.
func set_wanted(id: String, wanted: bool) -> void:
	var known := false
	for service in SERVICES:
		if str(service["id"]) == id:
			known = true
			break
	if not known:
		ShellLog.error("services: refusing to write a wish for unknown service \"%s\"" % id)
		return

	if not DirAccess.dir_exists_absolute(_dir):
		# The session makes this; a desk run has no session. Created here too so
		# the request is not silently dropped on a machine where the supervisor
		# has not started yet.
		DirAccess.make_dir_recursive_absolute(_dir)

	var path := _dir.path_join("%s.wanted" % id)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("services: cannot write %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return
	file.store_line("1" if wanted else "0")
	file.close()
	var error := DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		ShellLog.error("services: cannot place %s (error %d)" % [path, error])
		DirAccess.remove_absolute(temp_path)
		return

	_pending[id] = "start" if wanted else "stop"
	ShellLog.info("services: asked for %s to %s" % [id, "start" if wanted else "stop"])
	services_changed.emit()


func _poll() -> void:
	var changed := false
	for service in SERVICES:
		var id := str(service["id"])
		var word := _read_line(_dir.path_join("%s.state" % id))
		if word.is_empty():
			word = "unknown"
		if str(_states.get(id, "")) != word:
			_states[id] = word
			changed = true
		# The wish has landed once the state agrees with it. Cleared on the
		# state rather than on a timer, so a supervisor that never acts leaves
		# the row saying so instead of quietly reverting to a lie.
		#
		# `crashed` clears a pending start too: it IS the supervisor's answer
		# -- "I tried, it died again". Without this the row would say
		# "Starting" forever after a failed retry, and _on_row's pending guard
		# would swallow every further press. Measured on 2026-08-11: a start
		# wish written against a dead supervisor left the row stuck exactly
		# that way.
		#
		# THE PRICE, chosen deliberately: the supervisor wakes on a two-second
		# slice, so for a moment after a press the row says "Crashed" again
		# rather than "Starting", and only then flips to "Running". Gating this
		# on the state file being newer than the wish would word those two
		# seconds better and would also restore the swallow -- a supervisor
		# that never answers never updates its mtime either. A row that briefly
		# understates is better than a row a person cannot press.
		var pending := str(_pending.get(id, ""))
		if pending == "start" and (word == "running" or word == "crashed"):
			_pending.erase(id)
			changed = true
		elif pending == "stop" and word == "stopped":
			_pending.erase(id)
			changed = true
	if changed:
		services_changed.emit()


func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line().strip_edges()
