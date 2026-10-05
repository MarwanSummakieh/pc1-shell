extends Node

## ============================================================================
## THE DISPLAY PROFILE SEAM: asking for a different display configuration.
##
## The wifi, update and appctl seams' shape, reused a fourth time: the shell
## writes a one-line request file into a player-owned directory under /run and
## marwanos-display-profile (root) consumes it. The word it carries is one of
## PROFILES and nothing else, and the ROOT side checks that again against its own
## copy of the list -- nothing there needs to trust this file.
##
## THE SHELL DOES NOT WRITE /var. The profile lives in
## /var/marwanos/display.profile because it has to survive image upgrades, and
## /var is root's. The shell has no permission there and no business there: that
## file decides whether the machine can put a picture on the screen at all.
##
## WHY THIS EXISTS. The owner reported the screen as "so flickery it's giving me
## a headache" on 2026-08-10, and the bench was unreachable over SSH, so nobody
## could test a fix against the hardware that had the problem. The person who CAN
## see the flicker is the person on the couch with a pad, so the experiment ships
## to them: A cycles through named display configurations, each of which rules a
## different cause in or out. See /usr/lib/marwanos/session/marwanos-session for
## what each one actually asks gamescope for.
##
## NOTHING HERE RESTARTS ANYTHING. A profile only takes effect when gamescope is
## started again, and doing that automatically would take the screen away from
## somebody who might be mid-something. The row says "restart to apply" and
## Power -> Restart is two rows away; the person decides when.
##
## Phase 1 deletes this file with the rest of them: marwand exposes the display
## configuration over JSON-RPC and this becomes one call.
## ============================================================================

## Emitted when the profile state changes. States: current (this is what is on
## disk and what the running session started with), pending (chosen, and it means
## nothing until the next restart), refused (the service did not recognise the
## word), unknown (nothing written yet -- a desk run, or too early in boot).
signal state_changed(state: String, profile: String)

const POLL_SECONDS := 2.0

const STATE_FILE := "/run/marwanos/display.state"
const REQUEST_FILE := "/run/marwanos/display/request"

const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

## In cycle order, and it is the same order as PROFILE_LIST in marwanos-session
## and PROFILES in marwanos-display-profile. All three copies exist so that no
## one of them has to start before the others can work; the Containerfile greps
## the two shell-script copies against each other at build time, and this one is
## checked by the root side at runtime -- a word this list invented would simply
## be refused rather than written.
##
## The order walks from the likeliest fix, through the two configurations that
## tell the remaining causes apart, to today's behaviour and the bare baseline.
## Somebody cycling from the couch therefore meets the good answer first and can
## always keep going round to where they started.
const PROFILES := ["hundred", "steady", "sixty-raw", "flat", "native", "raw"]

## What each one is called on a television. Deliberately not the profile word:
## "sixty-raw" is a name for a configuration, and the row has to be readable at
## three metres by somebody who has never read a line of this repository. What
## these say is the part a person can actually perceive -- a refresh rate, and
## whether anything is being forced -- because that is what they will be
## comparing against the flicker in front of them.
const LABELS := {
	# First in the ring since 2026-08-11: the panel is a 240 Hz OLED that every
	# other profile drives at 60, and an OLED at the bottom of its range is the
	# standing flicker suspect. The parenthetical is the honest part -- whether
	# gamescope's -r actually moves the mode is exactly what choosing this
	# measures, and Settings > Display server shows the number that answers it.
	"hundred": "Fast 100 Hz (this panel's own mode)",
	"steady": "Steady 60 Hz",
	"sixty-raw": "60 Hz, direct",
	"flat": "60 Hz, flat",
	"native": "Panel default",
	"raw": "Panel default, direct",
}

## Matches PROFILE_DEFAULT in marwanos-session. What the session uses when the
## file is absent, which on a machine nobody has touched is the true answer.
const DEFAULT_PROFILE := "steady"

var state: String = "unknown"
var profile: String = ""

var _state_path := STATE_FILE
var _request_path := REQUEST_FILE
var _loaded := false

## The last profile asked for that root has not confirmed yet.
##
## WHY THE CYCLE CANNOT BE COMPUTED FROM THE STATE FILE ALONE. The consumer polls
## twice a second and this script polls every two, so "what is it now" lags a
## press by up to two and a half seconds. Without this, two presses inside that
## window both compute their next value from the same stale answer and ask for
## the SAME profile twice -- the second press does nothing at all. Measured under
## the Xvfb harness on 2026-08-10, where two A presses both requested sixty-raw.
##
## That is not a corner case on this screen. Five profiles behind one button
## means somebody who wants the third one presses A three times as fast as they
## can, and this is a row that exists because a person has a headache and wants
## it to stop. Cleared as soon as root's answer arrives, whatever that answer is,
## so a refusal or a dead consumer reverts the row to the truth rather than
## leaving it stuck on an optimistic guess.
var _requested := ""


func _ready() -> void:
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_state_path = override.path_join(STATE_FILE.get_file())
		_request_path = override.path_join("display.request")

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


## The profile the row should name. Falls back to the default rather than to an
## empty string, because "unknown" is not what the session will do -- on a
## machine where nothing has been written the session uses the default, and a row
## whose whole job is naming the configuration on screen must not say otherwise.
func current_profile() -> String:
	if profile.is_empty() or not PROFILES.has(profile):
		return DEFAULT_PROFILE
	return profile


## What the person has CHOSEN, which is not always what is on disk yet: the last
## thing asked for if root has not answered, and otherwise the truth. This is
## what the row draws and what the next press steps from -- both have to agree,
## or a fast sequence of presses would make the row jump backwards through
## profiles as each earlier answer lands. See _requested.
func chosen_profile() -> String:
	if not _requested.is_empty() and PROFILES.has(_requested):
		return _requested
	return current_profile()


## Is there a choice that has not reached gamescope yet? True from the moment A
## is pressed until the machine is restarted, which is exactly the span over
## which the row has to keep saying so.
func is_pending() -> bool:
	return not _requested.is_empty() or state == "pending"


## The next one round the ring. Wraps deliberately: a cycle with an end would
## strand somebody on the last profile with no way back to the one that worked
## except a terminal, which is the thing this machine does not have.
func next_profile() -> String:
	var index := PROFILES.find(chosen_profile())
	if index < 0:
		return DEFAULT_PROFILE
	return PROFILES[(index + 1) % PROFILES.size()]


## `name` is deliberately not the parameter name here or anywhere else in this
## tree: this script extends Node, and a local called `name` shadows Node.name.
func label_for(profile_name: String) -> String:
	return str(LABELS.get(profile_name, profile_name))


## Ask for the next profile in the cycle, and report what was asked for.
##
## THE ROW IS UPDATED OPTIMISTICALLY BY ITS CALLER rather than waiting for the
## state file to come back, and that is a considered choice on this screen in
## particular. The consumer polls twice a second, so the round trip is up to two
## and a half seconds -- and a button that appears to do nothing for two seconds,
## on the screen somebody opened BECAUSE the display is misbehaving, reads as the
## machine being broken in a second way. The poll corrects the row if the request
## was refused.
func request_next() -> String:
	var want := next_profile()
	ShellLog.info("display: requesting profile \"%s\" (stepping from \"%s\"); it applies on the next restart"
		% [want, chosen_profile()])
	_requested = want
	_write_request(want)
	return want


## Temp-then-rename and 0600, for the wifi seam's reasons: the service polls
## twice a second and deletes what it finds, so an in-place write can be read
## half-formed and destroyed, and Godot's FileAccess does not chmod.
func _write_request(want: String) -> void:
	if not PROFILES.has(want):
		ShellLog.error("display: refusing to request an unknown profile \"%s\"" % want)
		return

	var temp_path := _request_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("display: cannot write a request to %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return
	file.store_line(want)
	file.close()
	FileAccess.set_unix_permissions(temp_path, 384)  # 0600; GDScript has no octal literal

	var error := DirAccess.rename_absolute(temp_path, _request_path)
	if error != OK:
		ShellLog.error("display: cannot place the request at %s (error %d)"
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
	# confirmed or refused. Only an answer that names the profile just asked for
	# clears it on a match; anything else means an earlier request in a fast
	# sequence is still working its way through, and dropping the guess there
	# would make the next press repeat a profile.
	if state == "refused" or profile == _requested:
		_requested = ""

	ShellLog.info("display profile state: %s%s"
		% [state, (" (%s)" % profile) if not profile.is_empty() else ""])
	state_changed.emit(state, profile)


func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line()
