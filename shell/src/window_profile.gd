extends Node

## ============================================================================
## THE WINDOW PROFILE SEAM: what the compositor thinks Steam's windows are.
##
## display.gd's shape, a second time, for a second axis. That one is about the
## PANEL -- refresh, composition, hardware planes -- and it exists because the
## whole screen flickered at idle. This one is about the WINDOW STACK, and it
## exists because of a narrower report: "the moment steam runs the screen starts
## flickering" (the owner, 2026-08-11). The screen is calm until a second
## fullscreen client turns up and then it is not, which is a different cause with
## different levers.
##
## Two seams rather than one list of twenty-five combinations, because the two
## axes test different halves of the stack and a switch that moved both would
## stop being an answer to either. See /usr/lib/marwanos/window/profile.
##
## THIS FILE READS TWO DIFFERENT FACTS AND KEEPS THEM APART, which is the one
## thing it does that display.gd does not have to:
##
##   chosen    what /var/marwanos/window.profile says, via the state file --
##             the profile the NEXT session will start with. What the settings
##             row draws.
##   active    MARWANOS_WINDOW_PROFILE, exported by the running session -- what
##             the compositor on screen right now was actually started with.
##             What yields_screen() answers from.
##
## Between pressing A on the row and restarting, those genuinely differ, and
## conflating them would be a live bug rather than a tidiness point: `yield` is a
## word the SHELL acts on, so a shell that keyed its behaviour off the chosen
## profile would begin unmapping its own window the instant the row was pressed
## -- coordinating with a compositor that had not changed and would not until the
## restart. The result is a home button that does nothing, minutes before
## anything was supposed to change.
##
## Phase 1 deletes this file with the rest of them: marwand exposes the session
## configuration over JSON-RPC and this becomes one call.
## ============================================================================

## Emitted when the profile state changes. States: current (this is what is on
## disk), pending (chosen, and it means nothing until the next restart), refused
## (the service did not recognise the word), unknown (nothing written yet -- a
## desk run, or too early in boot).
signal state_changed(state: String, profile: String)

const POLL_SECONDS := 2.0

const STATE_FILE := "/run/marwanos/window.state"
const REQUEST_FILE := "/run/marwanos/window/request"

const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

## What the RUNNING session started gamescope with. Set by marwanos-session; a
## desk run has no session and therefore no variable, which reads as PLAIN --
## the right answer, because a desk run has no gamescope to coordinate with
## either.
const ACTIVE_ENV := "MARWANOS_WINDOW_PROFILE"

## In cycle order, and it is the same order as WINDOW_LIST in marwanos-session
## and PROFILES in /usr/lib/marwanos/window/profile. All three copies exist so
## that no one of them has to start before the others can work; the Containerfile
## greps the two shell-script copies against each other at build time, and this
## one is checked by the root side at runtime -- a word this list invented would
## simply be refused rather than written.
##
## The order IS the diagnosis. The first two address the symptom actually
## reported -- a WINDOWLESS background client blacking the screen for a second,
## which is a modeset and not a focus fight -- so they are the only two that can
## explain it and they come first. The four after them are about window
## arrangement, kept for the case where something still flickers once a game is
## on screen. Today's behaviour is last, and the ring wraps, so somebody cycling
## from the couch meets the likeliest answer first and can always get back to
## where they started.
const PROFILES := ["no-bg-steam", "no-wsi", "steam-split", "loose", "steam-aware",
	"yield", "plain"]

## What each one is called on a television. Deliberately not the profile word and
## deliberately not the flag: "steam-split" is a name for a configuration and
## "-e" is a name for nothing at all. What these say is the part a person can
## actually perceive or reason about from a sofa, because they will be comparing
## it against a flickering screen rather than against this repository.
## Worded for somebody watching a flickering television, not for somebody
## reading this repository. The first two say what the machine will NOT do,
## because that is the part a person can check against the screen in front of
## them -- and because both of them cost something ("no warm Steam" is a slower
## first launch), which a label that only said "Fix A" would hide.
const LABELS := {
	"no-bg-steam": "No warm Steam (slower first launch)",
	"no-wsi": "Warm Steam, no compositor hand-off",
	"steam-split": "Steam gets its own screen",
	"loose": "Apps size themselves",
	"steam-aware": "Compositor knows Steam",
	"yield": "Shell steps aside",
	"plain": "Warm Steam on boot",
}

## Matches WINDOW_DEFAULT in marwanos-session and DEFAULT in the root service.
## `no-bg-steam` since 2026-08-12: the owner ordered Valve's client out of the
## boot path -- this appliance draws its own Steam client, and a warm signed-out
## Valve client puts its login window on the television. `plain` (a warm client
## on every boot) stays selectable for the faster first launch.
const DEFAULT_PROFILE := "no-bg-steam"

var state: String = "unknown"
var profile: String = ""

var _state_path := STATE_FILE
var _request_path := REQUEST_FILE
var _loaded := false

## What the running session applied, read once. Once, and not polled, because it
## cannot change while this process lives: it is an environment variable set by
## the parent before exec. A restart is the only thing that changes it, and a
## restart is a new process.
var _active := ""

## The last profile asked for that root has not confirmed yet. See
## display.gd's _requested for the measured reason this exists -- two presses
## inside one poll interval would otherwise both compute the same next value and
## the second would do nothing.
var _requested := ""


func _ready() -> void:
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_state_path = override.path_join(STATE_FILE.get_file())
		_request_path = override.path_join("window.request")

	var found := OS.get_environment(ACTIVE_ENV).strip_edges()
	if PROFILES.has(found):
		_active = found
	else:
		# Absent is the ordinary case on a desk, so it is logged at info and the
		# fallback is the one that changes nothing. A NON-EMPTY word this shell
		# does not know is different -- it means the session and the shell ship
		# different lists, which is the drift the Containerfile's cross-check
		# exists to prevent -- so it says so.
		_active = DEFAULT_PROFILE
		if not found.is_empty():
			ShellLog.warn("window: the session applied \"%s\", which this shell does not know; behaving as \"%s\""
				% [found, DEFAULT_PROFILE])
	ShellLog.info("window profile in force this session: %s" % _active)

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


## What the compositor on screen was actually started with. THE ONLY THING
## BEHAVIOUR MAY KEY OFF -- see the header.
func active_profile() -> String:
	return _active


## Should the shell unmap its own window while another client is drawing? True
## only under the `yield` profile, which is what makes that behaviour a thing
## somebody chose rather than a thing that happens.
func yields_screen() -> bool:
	return _active == "yield"


## The profile the row should name. Falls back to the default rather than to an
## empty string, because "unknown" is not what the session will do.
func current_profile() -> String:
	if profile.is_empty() or not PROFILES.has(profile):
		return DEFAULT_PROFILE
	return profile


## What the person has CHOSEN, which is not always what is on disk yet, and is
## not what is running either. This is what the row draws and what the next press
## steps from -- both have to agree, or a fast sequence of presses would make the
## row jump backwards as each earlier answer lands.
func chosen_profile() -> String:
	if not _requested.is_empty() and PROFILES.has(_requested):
		return _requested
	return current_profile()


## Is there a choice that has not reached gamescope yet? True from the moment A
## is pressed until the machine is restarted -- and ALSO true when the state file
## and the running session simply disagree, which is the case a person who
## pressed A yesterday and never restarted is in. Both are the same sentence on
## the row ("restart to apply") because they are the same situation: what is on
## screen is not what was asked for.
func is_pending() -> bool:
	if not _requested.is_empty() or state == "pending":
		return true
	return current_profile() != _active


## The next one round the ring. Wraps deliberately: a cycle with an end would
## strand somebody on the last profile with no way back to the one that worked
## except a terminal, which is the thing this machine does not have.
func next_profile() -> String:
	var index := PROFILES.find(chosen_profile())
	if index < 0:
		return DEFAULT_PROFILE
	return PROFILES[(index + 1) % PROFILES.size()]


## `name` is deliberately not the parameter name: this script extends Node, and
## a local called `name` shadows Node.name.
func label_for(profile_name: String) -> String:
	return str(LABELS.get(profile_name, profile_name))


## Ask for the next profile in the cycle, and report what was asked for. The row
## is updated optimistically by its caller -- see display.gd's request_next for
## why a two-and-a-half second round trip on this screen in particular reads as
## the machine being broken in a second way.
func request_next() -> String:
	var want := next_profile()
	ShellLog.info("window: requesting profile \"%s\" (stepping from \"%s\"); it applies on the next restart"
		% [want, chosen_profile()])
	_requested = want
	_write_request(want)
	return want


## Temp-then-rename and 0600, for the wifi seam's reasons: the service polls
## twice a second and deletes what it finds, so an in-place write can be read
## half-formed and destroyed, and Godot's FileAccess does not chmod.
func _write_request(want: String) -> void:
	if not PROFILES.has(want):
		ShellLog.error("window: refusing to request an unknown profile \"%s\"" % want)
		return

	var temp_path := _request_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("window: cannot write a request to %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return
	file.store_line(want)
	file.close()
	FileAccess.set_unix_permissions(temp_path, 384)  # 0600; GDScript has no octal literal

	var error := DirAccess.rename_absolute(temp_path, _request_path)
	if error != OK:
		ShellLog.error("window: cannot place the request at %s (error %d)"
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

	if _loaded and word == state and rest == profile:
		return
	_loaded = true
	state = word
	profile = rest

	# Root has spoken, so the optimistic guess stands down -- whether it was
	# confirmed or refused. A refusal reverts the row to the truth rather than
	# leaving it stuck on a guess nothing will ever honour.
	_requested = ""

	ShellLog.info("window profile state: %s%s"
		% [state, (" (%s)" % profile) if not profile.is_empty() else ""])
	state_changed.emit(state, profile)


func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line()
