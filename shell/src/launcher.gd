extends Node

## ============================================================================
## THE LAUNCH SEAM.
##
## This is the file Phase 1 replaces. Everything the shell knows about running
## something other than itself passes through launch() and the two signals below,
## and nothing else in this project reaches into the launch path. That is the
## whole point of the file existing: the plan's Phase 1 hook is "the shell's
## placeholder launch-a-scene seam becomes Launch over JSON-RPC", and this is
## where that bolts in.
##
## When it does, TWO FUNCTIONS AND A STATE MACHINE go:
##
##   _run(entry)    -> send `Launch { target_id }` to marwand over the WebSocket
##                     and return; do not wait.
##   _on_closed()   -> becomes the handler for marwand's `AppExited` event.
##
## and the HANDOFF machinery below (_check_window_handoff and everything it
## reads) is deleted rather than ported. That paragraph used to say "exactly two
## functions change", and keeping it that way would now be a lie: a Steam game's
## life is not its wrapper's life -- the wrapper hands a steam:// URL to a client
## that is already running and exits in under a second -- so the shell had to
## learn to watch the WINDOW instead of the pid to know when a game ends. marwand
## is the right owner of that question (it supervises processes and knows what
## Steam started), which is precisely why none of it survives the port: the
## daemon's AppExited already means what four states and two deadlines mean here.
##
## Nothing else moves. The home rail, the cards, the focus handling and the hint
## row only ever see launch_started and launch_finished, so they do not care
## whether the thing that started was a placeholder scene, a Flatpak, or a game
## some other process is running on this one's behalf.
##
## Deliberately single-purpose. No process management, no queue, no retry, no
## state machine beyond "one thing at a time". Phase 1 puts all of that in the
## daemon, where it belongs: the shell is a renderer. If something wants to grow
## here, that is the signal it belongs in marwand instead.
## ============================================================================

## Emitted the moment a launch is requested, before anything is on screen. The
## home rail uses it to save focus and get out of the way.
signal launch_started(entry: Dictionary)

## Emitted when the launched thing is done and the home rail should come back. In
## Phase 1 this fires on marwand's AppExited rather than on a keypress; the
## consumer side is identical.
signal launch_finished(entry: Dictionary)

## Emitted when the overlay asks for the running app to be backgrounded rather
## than stopped. The rail comes back; the process does not go away, and
## launch_finished still fires later when it eventually exits.
signal minimized(entry: Dictionary)
signal blocked(detail: String)

const LaunchPlaceholder = preload("res://src/launch_placeholder.gd")
const LaunchSplash = preload("res://src/launch_splash.gd")
const PadKeys = preload("res://src/pad_keys.gd")
## Which launched applications get the pad-to-keyboard bridge, by entry id.
##
## Legacy per-ID overrides. Managed Windows manifests instead carry input_mode
## from the image-owned installation recipe. The first recipe uses pointer mode;
## the bridge pauses whenever the PC1 overlay owns input.
const PAD_KEY_APPS := {}

var _current: Dictionary = {}
var _minimized := false
var _embedded_steam_game := false


func _ready() -> void:
	var history_timer := Timer.new()
	history_timer.wait_time = 1.0
	history_timer.autostart = true
	history_timer.timeout.connect(_sample_history)
	add_child(history_timer)


func _sample_history() -> void:
	if _current.is_empty():
		return
	var foreground := _app_on_screen and not _minimized and not _pad_keys_paused and not _closing and not _terminating
	if foreground:
		foreground = Kiosk.focused_window(_pid, str(_current.get("prefix", ""))) == Kiosk.Focus.ELSEWHERE
	if foreground:
		var window := _history_foreground_window()
		if _handoff:
			var output: Array = []
			foreground = window > 0 and OS.execute("xprop", ["-id", str(window), "-notype", "STEAM_GAME"], output, true) == 0 and not output.is_empty() and _history_steam_matches(str(output[0]), str(_current.get("id", "")).trim_prefix(HANDOFF_PREFIX))
		else:
			foreground = _pid > 0 and OS.is_process_running(_pid) and window > 0 and Kiosk._window_belongs_to_app(window, _pid)
	PlayHistory.sample(Metadata.enrich(_current), foreground)


func _history_foreground_window() -> int:
	var output: Array = []
	if OS.execute("xprop", ["-root", "-notype", Kiosk._focus_property()], output, true) != 0 or output.is_empty():
		return 0
	var text := str(output[0])
	var value := text.get_slice("=", 1) if text.contains("=") else text.get_slice(":", 1)
	for word in value.replace(",", " ").split(" ", false):
		var token := word.strip_edges()
		var id := token.hex_to_int() if token.begins_with("0x") else token.to_int()
		if id > 0:
			return id
	return 0


func _history_steam_matches(property_text: String, app_id: String) -> bool:
	if not app_id.is_valid_int() or not property_text.contains("="):
		return false
	var value := property_text.get_slice("=", 1).strip_edges()
	return value.is_valid_int() and value.to_int() == app_id.to_int()

# Typed as the script rather than as Control so `entry` and `closed` resolve
# statically -- GDScript treats a missing member on a typed variable as an error,
# which is the point.
var _placeholder: LaunchPlaceholder = null

# The splash over the gap between spawn and the app's first frame. Owned here
# rather than by shell_root because only this file knows which branch _run
# took: the placeholder branch draws its own screen and must not get a second
# one. Removed on launch_finished like everything else the seam puts up.
var _splash: LaunchSplash = null

# The pad-to-keyboard bridge, alive only while a PAD_KEY_APPS application is
# confirmed on screen. Created by the watchdog's ELSEWHERE branch -- never
# earlier, so nothing types into an application that has not drawn -- and
# freed wherever the launch ends. See pad_keys.gd for what it is.
var _pad_keys: PadKeys = null

# REMEMBERED, not just forwarded. The overlay can be open before the bridge
# exists -- press home during a slow desktop-Steam start, and the watchdog
# births the bridge minutes later, under a menu or keyboard that owns the pad.
# A bridge that starts life unpaused in that state left-clicks in Steam for
# every A meant for the on-screen keyboard (found in review); the stored flag
# is applied to the bridge at creation, so pause state is a property of the
# SESSION, not of whichever object happened to exist when it was set.
var _pad_keys_paused := false


func is_busy() -> bool:
	return not _current.is_empty() and not _minimized


func is_minimized() -> bool:
	return _minimized and not _current.is_empty()


## Is something other than the shell provably drawing? shell_root asks when the
## app menu closes: giving the screen back up is only safe if there is somebody
## to give it to. See _app_on_screen.
func app_on_screen() -> bool:
	return _app_on_screen


## What is running, for anything that needs to name it on screen. A copy, so a
## consumer cannot write back into the seam's own record of the launch.
func current_entry() -> Dictionary:
	return _current.duplicate()


## Steam's own library can start a game without a shell launch request.
## Adopt that observed game into the ordinary Home/minimize/close lifecycle.
func adopt_steam_game(entry: Dictionary) -> void:
	if not _current.is_empty():
		return
	_current = entry.duplicate()
	_embedded_steam_game = true
	_pid = -1
	_handoff = true
	_handoff_seen = true
	_handoff_shell_ticks = 0
	_gamescope_answered = true
	launch_started.emit(_current)
	_start_watchdog()
	_app_is_up()


## The only way anything gets launched.
func launch(entry: Dictionary) -> void:
	if Profiles.is_open() or not Profiles.available:
		blocked.emit(Profiles.error if not Profiles.available else "Choose a user before playing.")
		return
	var profile_error := Profiles.launch_error(entry)
	if not profile_error.is_empty():
		blocked.emit(profile_error)
		return
	if entry.has("executable") and not FileAccess.file_exists(str(entry.get("executable", ""))):
		blocked.emit("%s is unavailable. Reconnect its drive or remove the app." % str(entry.get("title", "App")))
		return
	if not _current.is_empty():
		if _minimized and str(entry.get("id", "")) == str(_current.get("id", "")):
			resume_current()
		elif _minimized:
			blocked.emit("Close or resume %s in Processes before opening another app." % str(_current.get("title", "the running app")))
		return
	if is_busy():
		# One at a time. A second press while something is up is a bounced button
		# or an impatient person, not a request to launch twice.
		return

	_current = entry
	ShellLog.info("launch requested: %s" % _label(entry))
	launch_started.emit(entry)
	_run(entry)


## Phase 0's stand-in for running something else: a fullscreen scene that covers
## the home rail until it is dismissed. It exists to prove the seam and the focus
## handoff, not to look like anything.
##
## An entry carrying an "exec" array takes the other branch and starts a REAL
## process -- see _spawn. That branch is a spike, not the architecture.
func _run(entry: Dictionary) -> void:
	var exec: Array = entry.get("exec", [])
	if not exec.is_empty():
		_spawn(exec)
		return

	_placeholder = LaunchPlaceholder.new()
	_placeholder.entry = entry
	_placeholder.closed.connect(_on_closed, CONNECT_ONE_SHOT)
	get_tree().root.add_child(_placeholder)


## ============================================================================
## THE SPIKE, AND IT IS MARKED AS ONE.
##
## This answers exactly one question -- can this stack run a real application on
## the appliance's compositor at all -- and it answers it the cheapest way that
## is not a lie: spawn the process, watch the pid, put the rail back when it
## dies. Steam is the first thing pointed at it.
##
## IT VIOLATES THE RULE THIS FILE'S HEADER STATES, deliberately and visibly. The
## shell is a renderer; process supervision belongs in marwand, which is Phase 1
## M1 and does not exist yet. Writing marwand to answer a feasibility question
## would be building the answer before knowing whether the question has one. So
## this stays until marwand lands and then it goes -- _run() sends `Launch` over
## the WebSocket and this function is deleted whole, along with the poll timer
## and the window watchdog below it. The launch splash survives the deletion:
## every marwand launch is a real process, so it goes up when the Launch is
## sent, and marwand's events replace the watchdog as what clears it.
##
## WHY IT SHOULD WORK. The shell is an X client on gamescope's XWayland, and a
## child process inherits DISPLAY, so the app lands on the same compositor with
## gamescope's --force-windows-fullscreen already pointed at it. That is the
## same path Steam takes on a Deck. If it does not work, the journal says which
## half failed rather than leaving a black screen to interpret.
##
## No stdout capture: the child inherits this process's descriptors, which
## marwanos-session has already pointed at systemd-cat, so the app's own output
## lands in the journal under the session's tag for free.
## ============================================================================

## How often to ask whether the launched process is still alive. Half a second
## is far below the threshold where a person notices the rail coming back late,
## and far above the cost of the check.
const EXIT_POLL_SECONDS := 0.5

var _pid: int = -1
var _poll: Timer = null

## Set once a close has been asked for, so the exit poll stops interrogating a
## pid it knows is on its way out. See _check_exit.
var _terminating := false
var _steam_stop_pid := -1
var _closing := false


func _spawn(exec: Array) -> void:
	# {W}/{H} become the primary screen's real pixels, at launch time rather
	# than at catalogue-write time, because the catalogue is a constant and
	# the screen is whatever panel this stick was plugged into. Today's one
	# consumer is Steam's nested gamescope; the tokens are generic because a
	# second nested client will want exactly the same two numbers.
	#
	# Guarded, because headless reports zero screens and screen_get_size(0)
	# answers (0, 0) there (measured on the pinned engine) -- and a
	# `gamescope -W 0` is an instant argument error dressed as a launch. The
	# window size is the next-best truth, and the design surface is the floor.
	var screen := DisplayServer.screen_get_size(DisplayServer.get_primary_screen())
	if screen.x <= 0 or screen.y <= 0:
		screen = DisplayServer.window_get_size()
	if screen.x <= 0 or screen.y <= 0:
		screen = Vector2i(1920, 1080)
	var program := str(exec[0])
	var args := PackedStringArray()
	for i in range(1, exec.size()):
		var word := str(exec[i])
		word = word.replace("{W}", str(screen.x)).replace("{H}", str(screen.y))
		args.append(word)
	# Windows helpers scope their saves; Steam keeps the shared console session. Ordinary
	# Linux games receive a private HOME while their installed binaries stay put.
	if PlayHistory.is_game(Metadata.enrich(_current)) and not str(_current.get("id", "")).begins_with(HANDOFF_PREFIX) and not program in ["/usr/lib/marwanos/steamctl", "/usr/lib/marwanos/windows/manager.py", "/usr/lib/marwanos/winrun"] and OS.has_feature("linux"):
		args = PackedStringArray([Profiles.helper_path(), "run", Profiles.active, "--", program]) + args
		program = "/usr/bin/python3"

	ShellLog.info("spawning %s %s" % [program, " ".join(args)])
	_close_escalate_ticks = 0
	# Decided once, here, from the entry that is being started -- not asked again
	# per tick. Everything downstream reads this flag, so "is this launch a
	# handoff" has exactly one answer for the whole life of the launch even if
	# the entry changes underneath it.
	_handoff = str(_current.get("id", "")).begins_with(HANDOFF_PREFIX)
	_handoff_seen = false
	_handoff_shell_ticks = 0
	_gamescope_answered = false
	if _handoff:
		ShellLog.info("handoff launch: %s is Steam's to run; watching the window, not the pid"
			% _label(_current))
	_pid = OS.create_process(program, args)

	if _pid <= 0:
		# The launch failed before anything drew. Handing the screen straight
		# back is the honest response: the alternative is a hidden rail behind
		# an application that never started, which on this machine is a black
		# TV with no way out.
		ShellLog.error("could not start %s -- returning to the rail" % program)
		_on_closed()
		return

	ShellLog.info("started pid %d; watching for exit" % _pid)

	_poll = Timer.new()
	_poll.wait_time = EXIT_POLL_SECONDS
	_poll.timeout.connect(_check_exit)
	add_child(_poll)
	_poll.start()

	# The splash and its watchdog exist only on this branch: a real process
	# takes real seconds to put a frame up, and the placeholder is its own
	# screen already. Both are torn down in _finish with everything else.
	_splash = LaunchSplash.new()
	_splash.entry = _current
	get_tree().root.add_child(_splash)
	_start_watchdog()


## ============================================================================
## THE WINDOW WATCHDOG -- part of the spike, deleted with it.
##
## The exit poll above answers "is the process alive"; this answers the
## question that actually matters on a TV: "did anything appear". They are
## different questions, and the desktop Steam client is the proof -- a wrapper
## pid that lives for hours in front of a screen showing nothing. gamescope
## publishes GAMESCOPE_FOCUSED_WINDOW on the X root, Kiosk reads it (see the
## focus question there), and this compares the answer to the shell's own
## window: the moment focus belongs to anyone else, the app is on screen and
## the splash has done its job.
##
## If the deadline passes with the shell STILL focused and the pid still
## alive, the splash swaps to its honest failure state instead of promising
## forever. UNKNOWN -- no gamescope, so a desk run or the Xvfb harness --
## never fails and never clears: the plain splash simply holds until
## launch_finished, which keeps this safe headless.
##
## In Phase 1 marwand supervises the window question along with the process
## and this whole block goes with _spawn: the splash stays, driven by launch
## events instead of a poll.
## ============================================================================

## One ask per second: a person waits whole seconds for a client to draw, so
## finer polling buys nothing, and each ask is an xprop round trip.
const WINDOW_POLL_SECONDS := 1.0

## How long a spawned process gets to put a window up before the splash stops
## promising. Steam's cold start -- sandbox, update check, CEF -- is the
## slowest thing this machine launches and lands well inside 25 s; a launch
## still windowless past it has taken the desktop-client failure shape.
const WINDOW_DEADLINE_SECONDS := 25.0

var _watch: Timer = null
var _watched_seconds := 0.0

## ============================================================================
## HANDOFF -- when the wrapper's exit is not the app's exit.
##
## `flatpak run com.valvesoftware.Steam -gamepadui steam://rungameid/<appid>`
## does not start a game. The Steam client is already running -- the session
## starts it as furniture with no window -- so the flatpak wrapper hands the URL
## to that instance and exits, in about a second, having succeeded completely.
## The exit poll sees a dead pid, declares the launch over, and the rail snaps
## back over a game that is at that moment showing its first splash. That was the
## whole bug, and it is not fixable by waiting longer: the wrapper is genuinely,
## correctly gone.
##
## So for these entries the pid stops being the lifecycle and the WINDOW becomes
## it. The watchdog that already runs during every launch answers exactly the
## right question once a second, and gains two more jobs:
##
##   ELSEWHERE                        the game is up. Splash goes, as always.
##   SHELL, for RETURN_TICKS in a row, the game is gone. Finish the launch.
##
## The run of consecutive ticks is what makes the second one safe. A game's
## window flickers off the compositor's focus for a frame or two at loading
## screens, mode changes and its own splash teardown, and finishing on the first
## SHELL answer would put the rail back over a game that had merely blinked. Five
## seconds of the shell provably owning the screen is not a blink; it is someone
## looking at the home screen.
##
## AND IT ALWAYS TERMINATES. Two ways out exist for the case where nothing ever
## appears: an environment that cannot answer the window question at all (no
## gamescope -- a desk run or the Xvfb harness) falls straight back to the
## wrapper's exit, and an environment that can answer but never says ELSEWHERE
## gives up at HANDOFF_DEADLINE_SECONDS. A launch that hangs forever would be the
## worst failure this seam has: a black TV with the rail hidden behind it and no
## button that comes back.
## ============================================================================

## The id prefix marwanos-appscan gives a Steam library game. The same string
## tile.gd and shell_root test, and the same reason it is a prefix rather than a
## column: the id IS the fact.
const HANDOFF_PREFIX := "steam."

## Steam's flatpak id, for the close path. Stated rather than dug out of the
## exec, because close_current has to work after the wrapper is long gone and
## `flatpak kill` is what reaches the sandbox the game is actually inside.
const HANDOFF_APP_ID := "com.valvesoftware.Steam"

## Consecutive one-second polls of the shell owning the screen before a handed-off
## game is declared over. Five: below three and a loading screen's focus blink
## ends the launch; much above five and the rail takes a visible age to come back
## after quitting a game, which reads as the machine having hung on the way home.
const HANDOFF_RETURN_TICKS := 5

## How long a handoff launch waits for a window before giving the screen back.
## Generous against WINDOW_DEADLINE_SECONDS because there is a whole extra
## machine in the path -- the client has to receive the URL, resolve the appid,
## possibly verify files, and start a process this shell never sees -- and the
## cost of being wrong here is a rail that came back while a game was still
## loading. Past a minute, nothing is coming.
const HANDOFF_DEADLINE_SECONDS := 60.0

## Whether this launch's lifecycle belongs to the window rather than to the pid.
var _handoff := false

## Whether SOMETHING OTHER THAN THE SHELL is provably drawing right now -- set
## when the watchdog first answers ELSEWHERE, cleared when the launch ends.
## Separate from _handoff_seen, which is only about games: this one is asked by
## shell_root when the app menu closes, to decide whether it is safe to give
## the screen back up again. Yielding on a launch that never drew would leave
## the TV showing nothing at all.
var _app_on_screen := false

## Whether the game has ever provably been on screen. Until it has, there is
## nothing to watch for the END of, and the deadline above is what applies.
var _handoff_seen := false

## The current run of consecutive SHELL answers since the game was last up.
var _handoff_shell_ticks := 0

## Whether anything in this environment has ever answered the window question at
## all. UNKNOWN is not an answer (see Kiosk.focused_window's third value), and
## the difference between "gamescope says the shell has focus" and "there is no
## gamescope to ask" is what decides whether a dead wrapper ends the launch.
var _gamescope_answered := false


func _start_watchdog() -> void:
	_watched_seconds = 0.0
	_watch = Timer.new()
	_watch.wait_time = WINDOW_POLL_SECONDS
	_watch.timeout.connect(_check_window)
	add_child(_watch)
	_watch.start()


func _check_window() -> void:
	_watched_seconds += WINDOW_POLL_SECONDS
	if _handoff and not _embedded_steam_game and int(SteamEmbed.snapshot.get("client", 0)) > 0 \
			and int(SteamEmbed.snapshot.get("game_id", 0)) == str(_current.get("id", "")).trim_prefix(HANDOFF_PREFIX).to_int() \
			and Time.get_unix_time_from_system() - float(SteamEmbed.snapshot.get("heartbeat", 0)) < 3:
		_embedded_steam_game = true
		_handoff_seen = true
		_app_is_up()
	if _embedded_steam_game:
		# Steam can reclaim focus as a game closes. Observe the verified game
		# window itself; the lifetime of the client is independent of this game.
		var state: Dictionary = SteamEmbed.snapshot
		if Time.get_unix_time_from_system() - float(state.get("heartbeat", 0)) > 3:
			return
		if int(state.get("game_id", 0)) == str(_current.get("id", "")).trim_prefix(HANDOFF_PREFIX).to_int():
			_handoff_shell_ticks = 0
			return
		_handoff_shell_ticks += 1
		if _handoff_shell_ticks >= HANDOFF_RETURN_TICKS:
			_on_closed()
		return

	var focus := Kiosk.focused_window(_pid, str(_current.get("prefix", "")))
	# Recorded on every answer that IS one, whichever branch consumes it: this is
	# the flag that tells a dead wrapper whether there is a window question worth
	# waiting for. See _handoff_hands_over.
	if focus != Kiosk.Focus.UNKNOWN:
		_gamescope_answered = true

	if _handoff:
		_check_window_handoff(focus)
		return

	match focus:
		Kiosk.Focus.ELSEWHERE:
			_app_is_up()
		Kiosk.Focus.SHELL:
			if _watched_seconds >= float(_current.get("window_deadline", WINDOW_DEADLINE_SECONDS)) \
					and _pid > 0 and is_instance_valid(_splash):
				ShellLog.warn("%s alive as pid %d but no window after %.0f s; offering Close"
					% [_label(_current), _pid, _watched_seconds])
				_splash.show_failure()
				# Nothing left to decide: the splash now holds until the app
				# exits or the person closes it, both of which reach _finish.
				_stop_watchdog()
		_:
			# A managed app still needs a controller-accessible escape when
			# gamescope's focus property is unavailable. Do not claim it mapped.
			if str(_current.get("id", "")).begins_with("managed.") \
					and _watched_seconds >= float(_current.get("window_deadline", WINDOW_DEADLINE_SECONDS)) and is_instance_valid(_splash):
				_splash.show_failure()
				_stop_watchdog()


## Something other than the shell owns the screen: the application arrived.
##
## Shared by both watchdogs because it is one event with one response -- the
## splash's job is done and the pad bridge may start -- and the only difference
## is what happens to the WATCHDOG afterwards. An ordinary launch has had its
## question answered and stops polling; a handoff launch keeps polling, because
## the same answer coming back the other way is how it will learn the game ended.
func _app_is_up() -> void:
	# The splash goes now rather than at launch_finished, so the frame the app
	# exits on shows the rail and not a stale "Starting".
	ShellLog.info("focus moved off the shell after %.0f s; %s is on screen"
		% [_watched_seconds, _label(_current)])
	if not _handoff:
		_stop_watchdog()
	_remove_splash()
	# THE SHELL GETS OUT OF THE WAY, and this is the only place it may: the
	# watchdog has just proved somebody else owns the screen, so unmapping this
	# window cannot leave the TV with nothing on it. Whether it actually does is
	# the `yield` window profile's decision, not this line's -- the call is
	# unconditional and Kiosk is where the choice lives, so that every route into
	# and out of a launch goes through one gate rather than five copies of a
	# condition. See Kiosk.yield_screen for what a second fullscreen window costs
	# while Steam is mapping its own.
	_app_on_screen = true
	_sample_history()
	ControllerRouter.set_app_input(not _pad_keys_paused and not _uses_pad_bridge())
	Kiosk.remember_app_window(str(_current.get("input_mode", "")) == "pointer")
	Kiosk.yield_screen(true)
	# The one moment the bridge may start: there is now provably an application
	# on screen to type into. Which is also why a desk run never gets one -- the
	# watchdog only answers ELSEWHERE where gamescope exists, and that is the only
	# place XTEST injection lands where a person can see what it did.
	var mode := str(_current.get("input_mode", PAD_KEY_APPS.get(str(_current.get("id", "")), "")))
	if _pad_keys == null and not mode.is_empty():
		_pad_keys = PadKeys.new()
		_pad_keys.mode = mode
		# Born already respecting whatever surface owns the pad right now -- see
		# _pad_keys_paused for the overlay-first race.
		_pad_keys.paused = _pad_keys_paused
		get_tree().root.add_child(_pad_keys)


## The handoff state machine, one tick of it. See the block above HANDOFF_PREFIX
## for what it is for; this is the whole of what it does.
##
##   not seen + ELSEWHERE  -> the game is up. Splash goes, start watching for the
##                            way back.
##   not seen + SHELL      -> still waiting. Past WINDOW_DEADLINE_SECONDS the
##                            splash stops promising; past HANDOFF_DEADLINE_
##                            SECONDS the launch is given up on.
##   seen + ELSEWHERE      -> still playing. Any run of SHELL ticks is reset.
##   seen + SHELL          -> maybe over. HANDOFF_RETURN_TICKS of these in a row
##                            and it is.
##   UNKNOWN               -> no claim, no action, and the run is NOT reset: a
##                            failed xprop is not evidence a game came back.
func _check_window_handoff(focus: int) -> void:
	match focus:
		Kiosk.Focus.ELSEWHERE:
			_handoff_shell_ticks = 0
			if _handoff_seen:
				return
			_handoff_seen = true
			_app_is_up()
		Kiosk.Focus.SHELL:
			if not _handoff_seen:
				_handoff_still_waiting()
				return
			_handoff_shell_ticks += 1
			if _handoff_shell_ticks < HANDOFF_RETURN_TICKS:
				return
			ShellLog.info("handoff: the shell has owned the screen for %d s; %s has ended"
				% [_handoff_shell_ticks, _label(_current)])
			_stop_watchdog()
			_forget_wrapper()
			_on_closed()
		_:
			pass


## A handed-off game that has not appeared yet, one tick older.
##
## The failure splash arrives on the ordinary deadline, because the sentence it
## shows -- running, nothing on screen -- is exactly as true here, and B on it
## reaches close_current, which for a handoff kills the client and everything it
## started. The GIVING UP is a minute later and is this branch's own: unlike an
## ordinary launch there is no pid left to keep the poll honest, so nothing else
## would ever end this.
func _handoff_still_waiting() -> void:
	if _watched_seconds >= WINDOW_DEADLINE_SECONDS and is_instance_valid(_splash):
		# show_failure is idempotent, so this may be said every tick and is said
		# in the journal only once.
		_splash.show_failure()

	if _watched_seconds < HANDOFF_DEADLINE_SECONDS:
		return

	ShellLog.warn("handoff: nothing took the screen within %.0f s; giving %s back to the rail"
		% [_watched_seconds, _label(_current)])
	_stop_watchdog()
	_forget_wrapper()
	_on_closed()


## Stop watching the wrapper without stopping it. Every handoff path that ends a
## launch goes through this, because any of them can arrive while the process is
## still alive.
##
## KILLING IT WOULD BE WRONG IN ALL OF THEM. When `flatpak run` finds no client
## to hand the URL to, it BECOMES the client -- and the client is session
## furniture whose life is longer than any one game, so the pid this seam happens
## to be holding is Steam itself rather than the thing that just ended. (The one
## place the client IS meant to die is close_current, and `flatpak kill` has
## already done it by the time this is called.) Dropping the pid and stopping the
## poll is what keeps an unrelated client exit an hour later from arriving as a
## second launch_finished for a launch that is long over.
func _forget_wrapper() -> void:
	if _pid <= 0:
		return
	ShellLog.info("handoff: pid %d is the client's, not this launch's; stopping the exit poll"
		% _pid)
	_pid = -1
	_stop_poll()


func _stop_watchdog() -> void:
	if is_instance_valid(_watch):
		_watch.stop()
		_watch.queue_free()
		_watch = null


func _remove_splash() -> void:
	var splash := _splash
	_splash = null
	if is_instance_valid(splash):
		# Same two-step as the placeholder in _finish: queue_free alone leaves
		# the node drawn for the rest of the frame.
		splash.get_parent().remove_child(splash)
		splash.queue_free()


func _remove_pad_keys() -> void:
	var bridge := _pad_keys
	_pad_keys = null
	if is_instance_valid(bridge):
		bridge.queue_free()


## shell_root's lever for the home menu: the same press must not both move
## the menu and type into the application behind it. The value is remembered
## even while no bridge exists, so one created later starts in the right
## state -- see _pad_keys_paused.
func set_pad_keys_paused(value: bool) -> void:
	if value:
		PlayHistory.pause()
	ControllerRouter.set_app_input(_app_on_screen and not _minimized and not value and not _uses_pad_bridge())
	_pad_keys_paused = value
	if is_instance_valid(_pad_keys):
		_pad_keys.set_paused(value)


func _uses_pad_bridge() -> bool:
	return not str(_current.get("input_mode", PAD_KEY_APPS.get(str(_current.get("id", "")), ""))).is_empty()


## The second lever, for the same two moments and the same reason: the splash
## consumes the stick and the face buttons so a hidden rail cannot be driven
## blind behind it, and while the app menu is up that consumption is what stops
## A from choosing anything on the menu. A no-op once the splash is gone, which
## is every launch that actually put a window on screen.
func set_splash_paused(value: bool) -> void:
	if is_instance_valid(_splash):
		_splash.set_paused(value)


## Whether there is a running application this seam could stop. False for the
## placeholder branch, which has no pid and is dismissed with B.
##
## TRUE FOR A HANDOFF WITH NO PID AT ALL, which is the shape this question was
## not written for. A handed-off game outlives its wrapper by design, so `_pid >
## 0` alone would answer "nothing to close" for the entire time a game is on
## screen -- and this is the gate on the home button's app menu (shell_root's
## _input), so the one button that gets a person out of a game would do nothing.
## close_current knows how to end a handoff without a pid; this has to agree with
## it.
func can_close() -> bool:
	return _pid > 0 or _handoff


## Ask the running application to go away.
##
## THE PID IS NOT ENOUGH FOR A FLATPAK, and that is the whole reason this is
## not a one-line OS.kill. `flatpak run` is a wrapper: it sets up the sandbox
## and the real application runs inside it, frequently under a different pid
## that is not this process's child. Killing the wrapper can leave the
## application on screen with the shell believing it has exited -- which is a
## worse state than not offering to close it at all, because the rail comes
## back underneath a window that is still there.
##
## So a flatpak entry is closed with `flatpak kill <app-id>`, which is the
## documented way to stop a sandbox. Other Linux launches close their isolated
## process group so wrapper children cannot outlive the Close action.
##
## THE RAIL COMES BACK ON EVIDENCE, NOT ON HOPE. An earlier version armed the
## quiet-poll flag here and declared the process "terminated on request" on
## the very next tick, without checking -- so a `flatpak kill` that achieved
## nothing (a sandbox instance not yet registered, which is plausible in
## exactly the hung-startup state the failure splash sends people here from)
## returned the rail underneath an application that was still alive and could
## still map a window minutes later. Now the flatpak path stays on the normal
## exit poll -- the wrapper is unreaped until it actually dies, so asking
## is_process_running about it is safe and honest -- and only escalates to
## the wrapper SIGKILL if the sandbox has ignored the request for 10 s. The
## quiet flag is armed solely by _kill_pid, whose OS.kill is the thing that
## makes a later is_process_running an engine ERROR in the journal.
func close_current() -> void:
	if _current.is_empty() or _closing:
		return
	if _embedded_steam_game:
		SteamEmbed.close_game()
		return
	if _steam_stop_pid > 0:
		return
	var stop_exec: Array = _current.get("stop_exec", [])
	if not stop_exec.is_empty():
		var stop_args := PackedStringArray()
		for index in range(1, stop_exec.size()):
			stop_args.append(str(stop_exec[index]))
		if OS.create_process(str(stop_exec[0]), stop_args) <= 0:
			ShellLog.error("could not close the managed application; keeping its process tracked")
		else:
			_closing = true
		return

	# A HANDOFF CLOSES STEAM ITSELF, and there is no gentler option. The game is
	# a process inside the client's sandbox that this shell never started, never
	# saw and cannot name; `flatpak kill com.valvesoftware.Steam` is the one call
	# that reaches into that sandbox, and it takes the client down with the game.
	# That is a real cost stated rather than hidden: the session respawns the
	# client about thirty seconds later (it is started as furniture, with no
	# window), so for half a minute after quitting a game this way, starting
	# another one is slower than usual. The alternative -- leaving the game
	# running and hoping -- is the failure this whole seam exists to avoid, a rail
	# back on screen underneath something that is still there.
	#
	# The native/legacy Steam helper owns shutdown. The exit poll watches that
	# helper even when the handoff wrapper has already exited.
	if _handoff:
		_close_steam()
		return

	var exec: Array = _current.get("exec", [])
	if not exec.is_empty() and (str(exec[0]).ends_with("steamctl") or str(exec[0]).get_file() == "steam"):
		_close_steam()
		return
	var app_id := _flatpak_app_id(exec)

	if not app_id.is_empty():
		ShellLog.info("closing flatpak %s" % app_id)
		# Fire and forget: the poll below is what decides the app is gone, and
		# blocking the UI on flatpak's own exit would freeze the overlay.
		var pid := OS.create_process("flatpak", ["kill", app_id])
		if pid <= 0:
			ShellLog.warn("could not run `flatpak kill %s`; falling back to the pid" % app_id)
			_kill_pid()
			return
		_close_escalate_ticks = CLOSE_ESCALATE_TICKS
		return

	_kill_pid()


func _close_steam() -> void:
	_steam_stop_pid = OS.create_process("/usr/lib/marwanos/steamctl", ["stop"])
	if _steam_stop_pid <= 0:
		ShellLog.error("Steam could not close; keeping its launch tracked")
		return
	_closing = true
	_stop_watchdog()
	_remove_splash()
	_splash = LaunchSplash.new()
	_splash.entry = _current
	get_tree().root.add_child(_splash)
	_splash._dots.stop()
	_splash._status.text = "Closing Steam…"
	_splash.set_paused(true)
	if not is_instance_valid(_poll):
		_poll = Timer.new()
		_poll.wait_time = EXIT_POLL_SECONDS
		_poll.timeout.connect(_check_exit)
		add_child(_poll)
		_poll.start()


## Leave the application running and give the screen back to the rail.
##
## The process and exit poll stay alive. gamescope's explicit base-layer window
## control restores the shell; the saved app window restores the same process.
func minimize_current() -> void:
	if _current.is_empty() or _minimized:
		return
	PlayHistory.pause()
	_minimized = true
	_app_on_screen = false
	set_pad_keys_paused(true)
	ShellLog.info("minimize requested for %s; app stays running"
		% str(_current.get("title", "")))
	# If the splash is somehow still up -- possible only where the watchdog
	# answers UNKNOWN and nothing ever cleared it -- it must not cover the rail
	# this call is bringing back. The app keeps running; only the seam's own
	# furniture goes. The bridge goes with it: a rail the person is driving
	# must not also be typing arrows into a backgrounded file manager.
	_stop_watchdog()
	_remove_splash()
	_remove_pad_keys()
	# The window itself comes back before anything asks the compositor for
	# focus: this call is the rail returning, and a foreground request aimed at
	# a minimised window is a request about nothing. The app keeps running and
	# keeps its own window -- which is exactly the two-fullscreen-clients state
	# Kiosk.yield_screen exists to avoid, and the honest cost of a control that
	# backgrounds an application instead of closing it.
	Kiosk.yield_screen(false)
	Kiosk.minimize_app_window(_pid)
	Kiosk.focus_shell()
	DisplayServer.window_move_to_foreground()
	minimized.emit(_current)


func resume_current() -> void:
	if not is_minimized():
		return
	_minimized = false
	_pad_keys_paused = false
	_handoff_seen = false
	_handoff_shell_ticks = 0
	launch_started.emit(_current)
	_splash = LaunchSplash.new()
	_splash.entry = _current
	get_tree().root.add_child(_splash)
	Kiosk.focus_app()
	_start_watchdog()


## How many exit polls a `flatpak kill` gets to actually end the sandbox
## before the wrapper is killed outright. Ten seconds: Steam takes seconds to
## shut down cleanly and must get them, but the person who pressed Close is
## watching a screen that claims to be closing, and half a minute of that is
## the button reading as broken.
const CLOSE_ESCALATE_TICKS := 20

var _close_escalate_ticks := 0


func _kill_pid() -> void:
	if _pid <= 0:
		return
	ShellLog.info("terminating pid %d" % _pid)
	# Godot starts Linux children in their own session. Wrappers such as flock
	# and AppImage keep the game in that process group, so killing only the
	# wrapper leaves the game alive. Verify ownership before signalling a group:
	# a shared group must never take the shell or an unrelated app down with it.
	if OS.has_feature("linux") and _owns_process_group(_pid):
		var output: Array = []
		if OS.execute("/usr/bin/kill", ["-KILL", "--", "-%d" % _pid], output, true) != 0:
			ShellLog.error("could not terminate process group %d; keeping the application tracked" % _pid)
			return
		ShellLog.info("terminated application process group %d" % _pid)
	# The quiet-poll flag is armed HERE and only here: OS.kill is what makes a
	# later is_process_running an engine ERROR about a reaped pid, so this is
	# the one path that must stop asking. Every other close keeps polling and
	# the rail comes back when the process is actually gone.
	# OS.kill is SIGKILL on Unix. Abrupt, and acceptable here: this is the
	# button someone presses because the thing on screen will not go away, and
	# an application that ignored a polite request is exactly the case it
	# exists for. Anything that wants a graceful shutdown should offer its own
	# quit, as Steam does.
	# Also reap our direct child after signalling its group.
	var error := OS.kill(_pid)
	if error != OK:
		ShellLog.error("could not terminate pid %d (error %d)" % [_pid, error])
	else:
		_terminating = true


func _owns_process_group(pid: int) -> bool:
	if pid <= 1:
		return false
	var file := FileAccess.open("/proc/%d/stat" % pid, FileAccess.READ)
	if file == null:
		return false
	var stat := file.get_line()
	var end := stat.rfind(")")
	if end < 0:
		return false
	var fields := stat.substr(end + 1).strip_edges().split(" ", false)
	# Fields after comm: state, parent PID, process group, session.
	return fields.size() >= 4 and fields[2].to_int() == pid and fields[3].to_int() == pid


## The flatpak application id anywhere in an exec, else empty. Read from the
## entry rather than remembered separately so it cannot drift from what was
## actually launched. Scans for the `flatpak run` pair rather than requiring
## it at position zero, because Steam's exec now wraps it in a nested
## gamescope -- and `flatpak kill` remains the only close that reaches inside
## the sandbox no matter how many wrappers stand in front of it.
func _flatpak_app_id(exec: Array) -> String:
	for i in exec.size() - 1:
		if not str(exec[i]).ends_with("flatpak"):
			continue
		if str(exec[i + 1]) != "run":
			continue
		for j in range(i + 2, exec.size()):
			var word := str(exec[j])
			# Skip flatpak's own options; the first bare word is the id.
			if word.begins_with("-"):
				continue
			return word
	return ""


func _check_exit() -> void:
	if _steam_stop_pid > 0:
		if OS.is_process_running(_steam_stop_pid):
			return
		_steam_stop_pid = -1
		_forget_wrapper()
		_on_closed()
		return
	# ONCE WE HAVE KILLED IT, STOP ASKING. Godot's is_process_running() logs an
	# engine-level ERROR when the pid has already been reaped -- "does not exist
	# or is not a child of the calling process" -- and after our own kill that is
	# the normal case, not a fault. It reached the journal at ERROR severity on
	# every single Close press, which on a machine where `journalctl -p err` is
	# the primary diagnostic surface is worse than noise: it is a red line that
	# means nothing, in the place someone looks when something is actually wrong.
	if _terminating:
		ShellLog.info("pid %d terminated on request" % _pid)
		_pid = -1
		_terminating = false
		_stop_poll()
		_on_closed()
		return

	if _pid > 0 and OS.is_process_running(_pid):
		# A close is pending and being ignored: give `flatpak kill` its ten
		# seconds, then stop asking politely. _kill_pid arms the quiet branch,
		# so the tick after the SIGKILL is the one that finishes.
		if _close_escalate_ticks > 0:
			_close_escalate_ticks -= 1
			if _close_escalate_ticks == 0:
				ShellLog.warn("flatpak kill has not ended pid %d after 10 s; killing the wrapper" % _pid)
				_kill_pid()
		return
	ShellLog.info("pid %d exited" % _pid)
	_pid = -1
	_stop_poll()
	# THE ONE PLACE A DEAD PROCESS DOES NOT END A LAUNCH. See _handoff_hands_over
	# -- and note that the ordinary path below is reached unchanged whenever it
	# answers no, which is every launch that is not a handoff and every handoff in
	# an environment that cannot see windows.
	if _handoff and _handoff_hands_over():
		return
	_on_closed()


## The wrapper of a handoff launch has died. Does the window watchdog own the
## rest of this launch, or was that the end of it?
##
## THE ENVIRONMENT IS ASKED HERE, NOT REMEMBERED FROM A TICK. `flatpak run
## <id> steam://rungameid/...` exits in about a second, which is FASTER than the
## watchdog's first poll -- so at this moment the flag may never have been set on
## a machine that has gamescope, and reading it alone would send every real
## launch down the headless path. One extra xprop round trip, once per handoff
## launch, buys a deterministic answer instead of a race.
func _handoff_hands_over() -> bool:
	if not _gamescope_answered and Kiosk.focused_window() != Kiosk.Focus.UNKNOWN:
		_gamescope_answered = true

	if not _gamescope_answered:
		# Nothing here can ever answer the window question -- no gamescope, so a
		# desk run or the Xvfb harness. The wrapper's exit is the only evidence
		# this environment produces, so it is taken, exactly as it was before
		# handoff existed. This is the branch that keeps a headless run from
		# hanging on a game that was never going to appear.
		ShellLog.info("handoff: no window claim available here; the wrapper's exit ends the launch")
		return false

	ShellLog.info("handoff: wrapper exited, %s belongs to the running client now; watching the window"
		% _label(_current))
	return true


func _stop_poll() -> void:
	if is_instance_valid(_poll):
		_poll.stop()
		_poll.queue_free()
		_poll = null


func _on_closed() -> void:
	# Deferred because this arrives from inside the placeholder's own input
	# handling, and removing a node from the tree part-way through input
	# propagation is asking for trouble.
	_finish.call_deferred()


func _finish() -> void:
	if _current.is_empty():
		return
	PlayHistory.finish("exited")
	var entry := _current
	_current = {}
	_closing = false
	_steam_stop_pid = -1
	_minimized = false
	ControllerRouter.set_app_input(false)
	Kiosk.clear_focus_override()

	# Unconditionally, and first: every route out of a launch passes through
	# this function, so this is the one line that guarantees a yielded window
	# always comes back. A rail restored behind an unmapped window is the black
	# TV this project keeps designing against. See Kiosk.yield_screen.
	_app_on_screen = false
	Kiosk.yield_screen(false)

	# THE ORPHAN SWEEP. The watched pid and the application are not the same
	# life when something WRAPS the flatpak: the nested-gamescope evening
	# proved it -- the wrapper aborted, the poll saw an exit, the rail
	# returned, and Steam kept running invisibly behind it. So a launch whose
	# exec put a wrapper in front of `flatpak run` ends with a `flatpak kill`
	# of the id, busting any sandbox that outlived its wrapper. Gated on the
	# wrapper shape rather than fired always: when flatpak IS the watched
	# process, its exit already means the sandbox is being torn down, and an
	# unconditional kill would print one spurious journal error per normal
	# quit. No wrapper exec exists today; this is the trap staying armed for
	# the next one.
	var swept_exec: Array = entry.get("exec", [])
	if not swept_exec.is_empty() and not str(swept_exec[0]).ends_with("flatpak"):
		var app_id := _flatpak_app_id(swept_exec)
		if not app_id.is_empty():
			ShellLog.info("wrapper exited; sweeping flatpak %s" % app_id)
			OS.create_process("flatpak", ["kill", app_id])

	# The watchdog and splash go whatever state they are in: a launch that
	# ended ends the question of whether it drew, and a failure-state splash
	# left up over the returning rail would be the seam lying in the other
	# direction. The escalation counter dies with the launch it was counting
	# for, so a close pending on THIS app can never SIGKILL the next one.
	_close_escalate_ticks = 0
	# The handoff flags die with the launch they described, for the same reason
	# and with one extra consequence: can_close() reads _handoff, so a stale true
	# would have the home button offering to close a machine that is back at the
	# rail with nothing running.
	_handoff = false
	_embedded_steam_game = false
	_handoff_seen = false
	_handoff_shell_ticks = 0
	_gamescope_answered = false
	# The remembered pause dies with the launch it described: the next launch
	# starts with no overlay up, and inheriting a stale true would be a bridge
	# that never speaks.
	_pad_keys_paused = false
	_stop_watchdog()
	_remove_splash()
	_remove_pad_keys()

	var placeholder := _placeholder
	_placeholder = null
	if is_instance_valid(placeholder):
		# remove_child first, queue_free second: queue_free is deferred to the end
		# of the frame, so on its own it would leave the placeholder drawn over
		# the home rail for the frame in which focus is being restored.
		placeholder.get_parent().remove_child(placeholder)
		placeholder.queue_free()

	ShellLog.info("launch finished: %s" % _label(entry))
	launch_finished.emit(entry)


func _label(entry: Dictionary) -> String:
	return str(entry.get("id", "<unknown>"))
