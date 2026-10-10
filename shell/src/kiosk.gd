extends Node

## Fullscreen, borderless, no cursor -- asserted by the client rather than left to
## the compositor -- and an honest report of the geometry it was actually handed.
##
## Under plan A gamescope covers most of the first half: --force-windows-fullscreen
## sizes the window to the nested display and --hide-cursor-delay 1 takes the
## pointer away. Under plan B none of it exists -- cage 0.2.0's entire CLI is
## `-d -h -m -s -v` and there is no cursor flag at all (ADR 0004 finding 9). D4
## says the shell code is identical either way, so the shell has to be the thing
## that makes it true.
##
## Doing it here as well as in project.godot is not belt and braces. The project
## settings apply once, at window creation, before the compositor has necessarily
## finished sizing anything; these run after the tree is up and again whenever the
## window regains focus, which is when a compositor is most likely to have handed
## the pointer back.
##
## What this file deliberately does NOT do is choose a screen. The single screen is
## delivered below the shell -- `video=<internal>:d` in the kargs,
## marwanos-panel.service, and WLR_DRM_DEVICES under plan B (see ADR 0007) -- and
## it is delivered there because that is the only layer that also covers the boot.
## Every client-side fix leaves the lid panel showing plymouth for the whole of it.
##
## Two things a design pass believed about this file that a VM run on 2026-08-05
## disproved, kept here so they are not re-derived:
##
##   * "The shell runs native Wayland under cage." It does not. cage ships with
##     Xwayland, Godot's linuxbsd default driver order puts x11 first, and the
##     measured run under cage reported server "X11". So the shell is on XWayland
##     under BOTH plans, and the Wayland-backend limitations that were about to be
##     cited as the reason it cannot pick a screen do not even apply.
##   * "DisplayServer.get_name() is therefore an oracle for D4." It is not, for the
##     same reason -- it says X11 either way. The session script's own line is the
##     oracle. get_name() is still logged, because it is the thing that would change
##     if the driver order or cage's Xwayland support ever did.
##
## What remains true regardless: there is no DisplayServer.screen_get_name() in
## Godot 4.7.1 at all, so the shell cannot map "HDMI-A-1" to a screen index even in
## principle, and picking by index would be picking by enumeration order -- the same
## coin flip that makes cage's `-m last` unusable.
##
## So what the shell owes is the measurement. On 2026-08-05 the only evidence of the
## spanning defect was a phone camera pointed at a laptop; one boot with the lines
## below in it settles the geometry permanently.


var _native_pointer_visible := false

func set_native_pointer_visible(value: bool) -> void:
	_native_pointer_visible = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value or _windowed_for_desk() else Input.MOUSE_MODE_HIDDEN

func _ready() -> void:
	_assert_display_policy()
	if _windowed_for_desk():
		# Said once, here, rather than from _assert_display_policy: that runs again
		# on every focus-in, and a warning repeated three times in the first second
		# reads like something going wrong repeatedly instead of a mode being set.
		ShellLog.warn("%s is set: windowed with a cursor, at %dx%d. Kiosk policy NOT applied."
			% [WINDOWED_ENV, DESK_WINDOW_SIZE.x, DESK_WINDOW_SIZE.y])
		ShellLog.warn("this is a desk run; the appliance never sets that variable")
	else:
		ShellLog.info("kiosk display policy applied (fullscreen, borderless, cursor hidden)")
	_log_display_geometry("at startup")

	# A Wayland compositor's first xdg_toplevel configure can arrive after _ready,
	# so the numbers above may be what Godot guessed rather than what it was
	# handed. Trust the second pass.
	#
	# A one-shot signal connection rather than `await get_tree().process_frame`,
	# deliberately: awaiting turns _ready into a coroutine that returns early, and
	# autoload order is load-bearing here (see project.godot's [autoload] note).
	get_tree().process_frame.connect(_log_after_first_frame, CONNECT_ONE_SHOT)


func _log_after_first_frame() -> void:
	_log_display_geometry("after the first frame")
	# The overlay property is written to zero before it is ever needed, not
	# because a fresh window could carry a stale one -- it cannot -- but
	# because this proves ON EVERY BOOT that the xprop path works, in the
	# journal, before the first time an overlay actually depends on it. The
	# 2026-08-10 bench videos showed the shell composited twice, which is
	# what a lingering =1 produces; after this line, "was the property set"
	# is a question one boot's journal can answer.
	_write_overlay_property(false)


func _notification(what: int) -> void:
	# A compositor that takes focus away and gives it back can restore the
	# pointer. Cheap to re-apply, and a cursor on screen is a failed acceptance
	# criterion, not a cosmetic issue.
	#
	# Both notifications, because which one a display server actually delivers
	# varies and neither is guaranteed under a kiosk compositor with one client.
	# _ready is what covers the normal case; these are for the ones it does not.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_assert_display_policy()


## Set to anything non-empty to run windowed with a visible cursor, for testing
## the UI on a desk instead of on the appliance.
##
## This exists because the policy below is otherwise inescapable: fullscreen,
## borderless and no cursor is correct on a machine whose only input is a
## gamepad, and hostile on a developer's desktop, where it covers the screen with
## no pointer and no window furniture to close. scripts/run-shell-wsl.sh sets it.
##
## Nothing in the appliance sets it. The session script does not export it, so on
## the target this branch is unreachable -- it is not a runtime switch that a
## misconfigured machine could trip into, it is a variable that only exists if a
## human typed it. That is the same shape as D5's devmode flag and deliberately
## not the same shape as the compositor lever ADR 0005 removed.
const WINDOWED_ENV := "MARWANOS_SHELL_WINDOWED"

## 16:9, because the design surface is 1920x1080 and a desk window that is not
## 16:9 pillarboxes itself -- which would make every judgement about margins and
## focus visibility a judgement about the wrong rectangle. Small enough to leave
## the rest of the screen usable: MODE_WINDOWED alone kept the 3440x1440 size
## Godot had already picked, so it was a window covering the whole display, which
## is most of what was wrong with fullscreen in the first place.
const DESK_WINDOW_SIZE := Vector2i(1600, 900)


func _windowed_for_desk() -> bool:
	return not OS.get_environment(WINDOWED_ENV).is_empty()


func _assert_display_policy() -> void:
	var window := get_window()

	if _windowed_for_desk():
		if window != null:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			window.size = DESK_WINDOW_SIZE
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if window != null:
		window.mode = Window.MODE_FULLSCREEN
		window.borderless = true

	# MOUSE_MODE_HIDDEN rather than MOUSE_MODE_CAPTURED. Captured confines the
	# pointer and feeds relative motion, which is what a first-person game wants
	# and would make a stray mouse generate a stream of events into a UI that has
	# no use for them. Hidden is exactly the requirement: no cursor.
	# Native browser panels use the X pointer instead of the shell's drawn one.
	# Preserve that pointer through focus changes to the panel toolbar/keyboard.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _native_pointer_visible else Input.MOUSE_MODE_HIDDEN


## Everything the shell can see about the displays, in the journal.
func _log_display_geometry(when: String) -> void:
	# get_name() was expected to name the compositor -- "X11" for gamescope's
	# XWayland, "Wayland" for cage -- and the 2026-08-05 VM run measured "X11"
	# while cage was demonstrably the compositor. cage ships Xwayland and Godot
	# prefers x11, so this says X11 under both plans. Logged anyway: it is exactly
	# the line that would change if the driver order or cage's Xwayland support
	# moved, and a shell that is suddenly on native Wayland is a different program
	# from the one these notes describe.
	ShellLog.info("display %s: server %s, adapter %s" % [
		when, DisplayServer.get_name(), RenderingServer.get_video_adapter_name(),
	])

	var count := DisplayServer.get_screen_count()
	ShellLog.info("screens: %d, primary %d, keyboard focus %d" % [
		count, DisplayServer.get_primary_screen(), DisplayServer.get_keyboard_focus_screen(),
	])

	for index in count:
		# No name is logged because there is none to log -- see the class comment.
		# Position and size are the identification: on a side-by-side layout the
		# second screen's position.x equals the first one's width, and that is the
		# fingerprint of the bug this logging exists for.
		#
		# One Wayland caveat worth knowing before trusting these numbers:
		# screen_get_size comes from wl_output::mode and is in physical pixels,
		# while screen_get_position comes from wl_output::geometry and is logical.
		# They agree only while scale is 1, which it is under both plans.
		ShellLog.info("screen %d: size %s pos %s scale %.2f dpi %d refresh %.2f" % [
			index,
			DisplayServer.screen_get_size(index),
			DisplayServer.screen_get_position(index),
			DisplayServer.screen_get_scale(index),
			DisplayServer.screen_get_dpi(index),
			DisplayServer.screen_get_refresh_rate(index),
		])

	var window := get_window()
	if window == null:
		ShellLog.error("no window; nothing else can be measured")
		return

	# window_get_position is deliberately absent: DisplayServerWayland returns a
	# constant zero for it, so logging it would be logging a zero and inviting
	# someone to draw a conclusion from it.
	var window_size := DisplayServer.window_get_size()
	ShellLog.info("window: mode %d size %s" % [DisplayServer.window_get_mode(), window_size])
	ShellLog.info("viewport: canvas %s design %s stretch mode %d aspect %d" % [
		window.get_visible_rect().size,
		window.content_scale_size,
		window.content_scale_mode,
		window.content_scale_aspect,
	])

	# What the stretch actually does with the space, which depends on the aspect
	# mode and must not be assumed. Under EXPAND there are no bars at all -- the
	# viewport grows into the extra width instead -- so the bar arithmetic below
	# would report a letterbox that is not on the screen. On a machine whose only
	# surface is the journal, a confidently wrong line is worse than no line.
	if window.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND:
		var surface := window.get_visible_rect().size
		ShellLog.info("stretch: expand -- no bars; design surface is %dx%d (%d px wider than the %d base)" % [
			int(surface.x), int(surface.y),
			int(surface.x) - window.content_scale_size.x, window.content_scale_size.x,
		])
	elif window.content_scale_size.y > 0 and window_size.y > 0:
		# The pillarbox aspect "keep" produces: with a window wider than the
		# design surface the content is scaled to the window's HEIGHT and
		# centred, leaving an equal black bar each side. On one display that is
		# a harmless letterbox. Across two it is the UI cut in half -- one bar
		# landing invisibly on the lid panel and the other showing up as the
		# black band on the right of the TV.
		var design_aspect := float(window.content_scale_size.x) / float(window.content_scale_size.y)
		var window_aspect := float(window_size.x) / float(window_size.y)
		if window_aspect > design_aspect:
			var drawn_width := int(round(window_size.y * design_aspect))
			ShellLog.info("stretch: drawing %dx%d with a %d px black bar each side" % [
				drawn_width, window_size.y, (window_size.x - drawn_width) / 2,
			])
		elif window_aspect < design_aspect:
			# The other half of the same arithmetic. Logged rather than left to
			# be inferred from its absence: a missing line reads as "the check
			# did not run", and on a machine whose only surface is the journal
			# that is indistinguishable from a bug.
			var drawn_height := int(round(window_size.x / design_aspect))
			ShellLog.info("stretch: drawing %dx%d with a %d px black bar top and bottom" % [
				window_size.x, drawn_height, (window_size.y - drawn_height) / 2,
			])
		else:
			ShellLog.info("stretch: window matches the design aspect exactly; no bars")

	# The one line that names the bug outright if it ever happens again.
	var matches_a_screen := false
	for index in count:
		if DisplayServer.screen_get_size(index) == window_size:
			matches_a_screen = true
	if count > 1 and not matches_a_screen:
		ShellLog.error("window %s matches no single screen of %d -- the compositor handed the shell a surface spanning outputs" % [window_size, count])


# ---------------------------------------------------------------------------
# THE OVERLAY SWITCH
#
# gamescope composites a window over the focused application -- rather than
# instead of it -- when that window carries the X property
# GAMESCOPE_EXTERNAL_OVERLAY. It is the mechanism Steam's overlay uses on a
# Deck, and it is what makes app_overlay.gd able to show the RUNNING
# application through its own transparent middle instead of a screenshot of it.
#
# WHY xprop AND NOT GODOT. Godot has no API for setting an arbitrary X property
# on its own window; it exposes the window handle and nothing else. xprop is in
# the image already, it is the documented way to set one, and this is window
# configuration -- which is the job this autoload already exists to do. It is
# not the shell growing a process-management habit: one property, set on its own
# window, twice per overlay.
#
# IF IT DOES NOT TAKE, the overlay still draws -- it simply replaces the
# application on screen instead of floating over it, which is survivable and
# obvious rather than silent. The journal says which happened.

const OVERLAY_PROPERTY := "GAMESCOPE_EXTERNAL_OVERLAY"

var _overlay_active := false


# ---------------------------------------------------------------------------
# YIELDING THE SCREEN
#
# The shell hides its UI while an application runs -- shell_root's
# _hand_screen_over hides the Control -- but the WINDOW stays exactly where it
# was: mapped, fullscreen, and as far as the compositor is concerned still a
# candidate for the screen. gamescope with --force-windows-fullscreen then has
# two fullscreen clients and a heuristic for choosing between them, and every
# window Steam maps or unmaps (notifications, tooltips, CEF helpers, the
# overlay) is another chance for that choice to come back to us for a frame.
# The owner's words for what that looks like from a sofa: "the moment steam
# runs the screen starts flickering".
#
# So under the `yield` window profile the shell gets out of the way for real
# once something else is PROVABLY drawing: minimised, which unmaps it and leaves
# the compositor exactly one fullscreen candidate. Nothing about the shell's own
# life changes -- the process runs, the scene tree ticks, the pad still arrives,
# because input on this machine comes from evdev through SDL rather than from X
# focus.
#
# BEHIND A PROFILE, AND THAT IS THE LESSON OF 58cc0e3. This shipped once before,
# welded to a gamescope flag, unconditionally, with no way back from the couch --
# and it was reverted within the hour. Not because it was the wrong thing to try
# but because an appliance with no terminal cannot afford an experiment it cannot
# undo from a sofa. WindowProfile.yields_screen() is that undo: `plain` is the
# default and does none of this.
#
# NEVER ON THE DESK. The Xvfb harness drives this window with `xdotool key`,
# which needs a mapped window to send to, and a developer's desk run that
# minimised itself mid-test would look like a crash. Same guard as every other
# kiosk policy: the appliance never sets WINDOWED_ENV, so the branch below is
# unreachable there. (The profile check would catch a desk run anyway -- no
# session means no MARWANOS_WINDOW_PROFILE means `plain` -- but the two guards
# answer different questions and neither is the other's excuse.)
#
# THE ORDER MATTERS AT BOTH ENDS. Yielded only after the watchdog reports
# ELSEWHERE (see Launcher._app_is_up), never at launch time -- the splash is
# drawn by THIS window, and minimising while it is the only thing on screen is
# a black TV. Taken back before the overlay is composited and on every path
# that ends a launch, because a menu drawn into an unmapped window is a menu
# nobody can see.
var _yielded := false


## Give the screen to whatever else is drawing, or take it back.
##
## Taking it BACK is deliberately not gated on the profile, and the asymmetry is
## the safety property: if the profile ever changed under a yielded window --
## it cannot today, but this is the function a black screen would come from --
## the shell must still be able to come back. Only the giving-away is a choice.
func yield_screen(yielded: bool) -> void:
	if yielded and not WindowProfile.yields_screen():
		return
	if yielded == _yielded:
		return
	if _windowed_for_desk():
		return
	_yielded = yielded

	var window := get_window()
	if window == null:
		ShellLog.warn("no window; cannot %s the screen"
			% ("yield" if yielded else "take back"))
		return

	if yielded:
		window.mode = Window.MODE_MINIMIZED
		ShellLog.info("screen yielded: the shell's window is minimised")
		return

	# Back to the kiosk policy rather than to MODE_WINDOWED: _assert_display_policy
	# is the one place that knows what fullscreen means here, and duplicating it
	# is how the two drift.
	_assert_display_policy()
	DisplayServer.window_move_to_foreground()
	ShellLog.info("screen taken back: the shell's window is fullscreen again")


## Ask gamescope to composite this window over the running application.
##
## Transparency is toggled alongside the property, and both directions matter:
## a transparent window that is NOT an overlay shows the desktop's clear colour
## rather than an app, and an overlay that is not transparent covers the very
## thing it is framing.
func set_overlay(enabled: bool) -> void:
	if enabled == _overlay_active:
		return
	_overlay_active = enabled

	var window := get_window()
	if window != null:
		window.transparent_bg = enabled
	get_tree().root.transparent_bg = enabled
	if _x11_session():
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enabled)
		if enabled:
			focus_shell()
		return

	_write_overlay_property(enabled)


## Set, then PROVE. A property write that silently failed used to be one
## journal line easily missed, and the failure mode is not subtle to look at:
## an =1 that never cleared has gamescope compositing the shell over itself --
## two shells at two offsets, which is one reading of the 2026-08-10 bench
## videos. So the write is read back, a mismatch is retried once, and a
## mismatch that survives the retry is an ERROR naming the state the
## compositor was left in, not a warning naming an exit code.
func _write_overlay_property(enabled: bool) -> void:
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if handle == 0:
		ShellLog.warn("no native window handle; cannot set %s (overlay will cover the app)"
			% OVERLAY_PROPERTY)
		return

	# xprop wants the id in hex; Godot hands back the XID as an integer.
	var window_id := "0x%x" % handle
	var value := "1" if enabled else "0"

	for attempt in 2:
		var args := PackedStringArray([
			"-id", window_id,
			"-f", OVERLAY_PROPERTY, "32c",
			"-set", OVERLAY_PROPERTY, value,
		])
		var output: Array = []
		var code := OS.execute("xprop", args, output, true)
		if code == 0 and _read_overlay_property(window_id) == value:
			ShellLog.info("%s=%s on window %s (verified)"
				% [OVERLAY_PROPERTY, value, window_id])
			return
		ShellLog.warn("xprop %s=%s on %s did not take (attempt %d, exit %d): %s"
			% [OVERLAY_PROPERTY, value, window_id, attempt + 1, code, " ".join(output)])

	ShellLog.error("%s could not be set to %s; gamescope may composite the shell %s"
		% [OVERLAY_PROPERTY, value,
			"over the running app twice" if value == "0" else "instead of the app"])


## What the property actually reads on the window right now: "0", "1", or ""
## for absent/unreadable. Absent counts as "0" -- a window with no property
## is not an overlay, which is also why the boot-time clear writing an
## explicit 0 is a proof of plumbing rather than a change of state.
func _read_overlay_property(window_id: String) -> String:
	var output: Array = []
	var code := OS.execute("xprop",
		PackedStringArray(["-id", window_id, "-notype", OVERLAY_PROPERTY]), output, true)
	if code != 0 or output.is_empty():
		return ""
	var line := str(output[0]).strip_edges()
	if not line.contains("="):
		return "0" if line.contains("not found") else ""
	return line.get_slice("=", 1).strip_edges()


# ---------------------------------------------------------------------------
# THE FOCUS QUESTION
#
# gamescope publishes what it is doing as root-window X properties, and
# GAMESCOPE_FOCUSED_WINDOW is the one that answers "whose pixels are on the
# TV". The launch seam needs that answer while a spawn is in flight, because a
# pid is not evidence of a window: the desktop Steam client's wrapper stays
# alive whether or not anything ever mapped, and the difference between "the
# app is on screen" and "the shell is still what the TV shows" is exactly this
# property. See Launcher's watchdog for what is done with the answer.
#
# xprop again rather than Godot, for the overlay switch's reason: Godot
# exposes the window handle and no X property API at all. Reading the root
# window lives here, next to the shell's other xprop call, so the launch seam
# stays free of X plumbing that Phase 1 would otherwise have to delete twice.
#
# THE THIRD ANSWER IS LOAD-BEARING. On a desk run and under the Xvfb harness
# there is no gamescope and no property, and "cannot tell" must not collapse
# into either of the other two: reported as SHELL it would declare every desk
# launch failed at the deadline, reported as ELSEWHERE it would clear the
# splash on evidence that does not exist. So UNKNOWN is its own value and the
# caller is expected to do nothing on it.

enum Focus { SHELL, ELSEWHERE, UNKNOWN }

const FOCUSED_WINDOW_PROPERTY := "GAMESCOPE_FOCUSED_WINDOW"

## Set after the first line that had CONTENT but yielded no id, so the journal
## carries exactly one sample of the shape this parser did not expect instead
## of either silence or a line per second. The property's exact print format
## depends on its TYPE (xprop prints `NAME = 123` for a CARDINAL and
## `NAME: window id # 0x2000004` for a WINDOW), and which type gamescope
## declares has not been measured on the bench yet -- this is the line that
## answers it if the answer is "neither of the two handled below".
var _focus_parse_warned := false
var _app_window := 0
var _fit_app_window := false
var _hidden_app_windows: Array[int] = []
var _focus_request := 0


func _x11_session() -> bool:
	return OS.get_environment("MARWANOS_COMPOSITOR") == "x11"


func _focus_property() -> String:
	return "_NET_ACTIVE_WINDOW" if _x11_session() else FOCUSED_WINDOW_PROPERTY


func remember_app_window(fit_to_screen: bool = false) -> void:
	var output: Array = []
	if DisplayServer.get_name() != "X11":
		return
	if OS.execute("xprop", ["-root", "-notype", _focus_property()], output, true) != 0 or output.is_empty():
		return
	var line := str(output[0]).strip_edges()
	var value := line.get_slice("=", 1) if line.contains("=") else line.get_slice(":", 1)
	var own := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	for word in value.replace(",", " ").split(" ", false):
		var id := word.hex_to_int() if word.begins_with("0x") else word.to_int()
		if id > 0 and id != own:
			_app_window = id
			_fit_app_window = fit_to_screen
			if _fit_app_window:
				_fit_app_to_screen()
			return


func _fit_app_to_screen() -> void:
	if DisplayServer.get_name() != "X11" or _x11_session() or _app_window <= 0:
		return
	# gamescope can scale a Wine window without changing its backing pixels.
	# Resize desktop applications themselves; keep dialogs and game fullscreen
	# modes at the dimensions they request.
	var output: Array = []
	if OS.execute("xprop", ["-id", str(_app_window), "_NET_WM_WINDOW_TYPE", "_NET_WM_STATE", "WM_TRANSIENT_FOR"], output, true) != 0:
		return
	var hints := "\n".join(output)
	if not hints.contains("_NET_WM_WINDOW_TYPE_NORMAL") or hints.contains("_NET_WM_WINDOW_TYPE_DIALOG") \
			or hints.contains("_NET_WM_STATE_FULLSCREEN") or hints.contains("WM_TRANSIENT_FOR(WINDOW)"):
		return
	var size := DisplayServer.screen_get_size(DisplayServer.get_primary_screen())
	if size.x <= 0 or size.y <= 0:
		return
	if OS.execute("xdotool", ["windowsize", str(_app_window), str(size.x), str(size.y)]) == 0:
		OS.execute("xdotool", ["windowmove", str(_app_window), "0", "0"])
		ShellLog.info("desktop app window resized to %dx%d" % [size.x, size.y])


func _focus_override(window_id: int) -> void:
	if DisplayServer.get_name() != "X11":
		return
	if _x11_session():
		if window_id > 0:
			OS.create_process("xdotool", ["windowraise", str(window_id), "windowactivate", str(window_id)])
		return
	# gamescope's explicit base-layer control avoids competing fullscreen clients.
	# https://github.com/ValveSoftware/gamescope/blob/master/src/steamcompmgr.cpp
	OS.create_process("xprop", ["-root", "-f", "GAMESCOPECTRL_BASELAYER_WINDOW", "32c",
		"-set", "GAMESCOPECTRL_BASELAYER_WINDOW", str(window_id)])


func focus_shell() -> void:
	_focus_request += 1
	var request := _focus_request
	if _x11_session():
		# Changing transparent_bg recreates Godot's X window. The next rendered
		# frame can precede Openbox handling its MapRequest under software rendering.
		# Its desktop property proves the WM has adopted the current window.
		for attempt in 20:
			await get_tree().create_timer(0.05).timeout
			if request != _focus_request:
				return
			var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
			var output: Array = []
			if handle > 0 and OS.execute("xprop", ["-id", str(handle), "-notype", "_NET_WM_DESKTOP"], output, true) == 0 \
					and not output.is_empty() and str(output[0]).contains("="):
				break
	_focus_override(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE))


func minimize_app_window(launcher_pid: int = -1) -> void:
	if DisplayServer.get_name() != "X11" or _x11_session() or _app_window <= 0:
		return
	# Without Steam integration, gamescope ignores the base-layer window
	# override. Remove this app's windows from its candidates while the process
	# keeps running; mapping them again restores the same app on Resume.
	var windows: Array[int] = [_app_window]
	var output: Array = []
	if launcher_pid > 0 and OS.execute("xprop", ["-root", "-notype", "GAMESCOPE_FOCUSABLE_WINDOWS"], output, true) == 0 \
			and not output.is_empty():
		var fields := str(output[0]).get_slice("=", 1).split(",", false)
		for index in range(0, fields.size(), 3):
			var window_id := str(fields[index]).strip_edges().to_int()
			if window_id > 0 and not windows.has(window_id) and _window_belongs_to_app(window_id, launcher_pid):
				windows.append(window_id)
	for window_id in windows:
		if OS.execute("xdotool", ["windowunmap", str(window_id)]) == 0:
			_hidden_app_windows.append(window_id)


func focus_app() -> void:
	_focus_request += 1
	for window_id in _hidden_app_windows:
		OS.execute("xdotool", ["windowmap", str(window_id)])
	_hidden_app_windows.clear()
	if _fit_app_window:
		_fit_app_to_screen()
	_focus_override(_app_window)
	# If the saved app window has closed, normal compositor selection can recover.


func clear_focus_override() -> void:
	_focus_request += 1
	_focus_override(0)
	_app_window = 0
	_fit_app_window = false
	_hidden_app_windows.clear()


func focus_app_keyboard() -> bool:
	if DisplayServer.get_name() != "X11" or _app_window <= 0:
		return false
	# Gamepad UI input comes from the broker, independent of X keyboard focus.
	# Restore the app's X focus before XTEST so typing cannot land in this menu.
	var output: Array = []
	if OS.execute("xdotool", ["windowfocus", str(_app_window)], output, true) != 0:
		return false
	output.clear()
	return OS.execute("xdotool", ["getwindowfocus"], output, true) == 0 \
		and not output.is_empty() and str(output[0]).strip_edges().to_int() == _app_window


## Who gamescope says owns the screen, as one of the three answers above.
##
## Blocking, like set_overlay's xprop, and acceptable for the same reason:
## one small X round trip, made at most once a second and only while a launch
## is in flight. The parse is deliberately paranoid -- xprop prints
## "GAMESCOPE_FOCUSED_WINDOW:  not found." at exit 0 when the property does
## not exist, so a missing "=" is the absence signal, not the exit code; and a
## line that parses to no usable ids at all is garbage, which is UNKNOWN
## rather than a claim about focus.
func focused_window(launcher_pid: int = -1, prefix: String = "") -> int:
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if handle == 0:
		return Focus.UNKNOWN

	var output: Array = []
	var code := OS.execute("xprop",
		PackedStringArray(["-root", "-notype", _focus_property()]), output, true)
	if code != 0 or output.is_empty():
		return Focus.UNKNOWN

	var line := str(output[0]).strip_edges()

	# "not found." has neither separator; that is the honest absence signal.
	# PAST the separator, ids are dug out of whatever prose surrounds them:
	# xprop's value formatting depends on the property's declared TYPE --
	# `= 123, 456` for CARDINALs, `: window id # 0x2000004` for WINDOWs -- and
	# betting the whole watchdog on gamescope declaring one rather than the
	# other would fail as a permanent, silent UNKNOWN. Scanning every token
	# for a number swallows both shapes, and the list form gamescope's other
	# properties use, without caring which one this is.
	var value := ""
	if line.contains("="):
		value = line.get_slice("=", 1)
	elif line.contains(":"):
		value = line.get_slice(":", 1)
	if value.is_empty():
		return Focus.UNKNOWN

	var saw_id := false
	for word in value.replace(",", " ").split(" ", false):
		var text := word.strip_edges()
		var id := text.hex_to_int() if text.begins_with("0x") else text.to_int()
		if id == 0:
			continue
		saw_id = true
		if id == handle:
			return Focus.SHELL
		if launcher_pid > 0 and not prefix.is_empty() and not _window_belongs_to_app(id, launcher_pid):
			return Focus.UNKNOWN
	if not saw_id:
		if not _focus_parse_warned:
			_focus_parse_warned = true
			ShellLog.warn("cannot read an id out of xprop's answer: %s" % line)
		return Focus.UNKNOWN
	return Focus.ELSEWHERE


func _window_belongs_to_app(window_id: int, launcher_pid: int) -> bool:
	var output: Array = []
	if OS.execute("xprop", ["-id", str(window_id), "-notype", "_NET_WM_PID"], output, true) != 0 or output.is_empty():
		return false
	var text := str(output[0]).strip_edges()
	var window_pid := text.get_slice("=", 1).strip_edges().to_int()
	if window_pid <= 1:
		return false
	if _descends_from(window_pid, launcher_pid):
		return true
	# Proton may expose a PID from its runtime namespace. Require an actual
	# nested namespace and prove the matching host process belongs to this launch.
	# A shared prefix alone also matches a setup wizard left from an earlier run.
	for name in DirAccess.get_directories_at("/proc"):
		if not name.is_valid_int():
			continue
		var status_file := FileAccess.open("/proc/" + name + "/status", FileAccess.READ)
		if status_file == null:
			continue
		var status_lines := PackedStringArray()
		while not status_file.eof_reached():
			status_lines.append(status_file.get_line())
		var namespace_match := false
		for line in status_lines:
			if line.begins_with("NSpid:"):
				var namespace_pids := line.trim_prefix("NSpid:").strip_edges().replace("\t", " ").split(" ", false)
				namespace_match = namespace_pids.size() >= 2 and namespace_pids[-1].to_int() == window_pid
		if not namespace_match:
			continue
		if _descends_from(name.to_int(), launcher_pid):
			return true
	return false


func _descends_from(pid: int, ancestor: int) -> bool:
	for step in 64:
		if pid == ancestor:
			return true
		var file := FileAccess.open("/proc/%d/stat" % pid, FileAccess.READ)
		if file == null:
			return false
		var stat := file.get_line()
		var end := stat.rfind(")")
		if end < 0:
			return false
		var fields := stat.substr(end + 1).strip_edges().split(" ", false)
		if fields.size() < 2:
			return false
		pid = fields[1].to_int()
		if pid <= 1:
			return false
	return false
