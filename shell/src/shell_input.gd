extends Node

## The twelve actions the shell is allowed to use, defined here rather than in
## project.godot.
##
## The tenth is ui_shell_options, on the pad's OPTIONS button -- see its
## _define below for why the options menu moved off Triangle and onto the
## button that says what it does. The last two are the shoulders, and they
## belong to the file manager's split view alone.
##
## It was six until the on-screen keyboard landed (ADR 0006, fifth amendment).
## Six was never a cap for its own sake -- it was the count that fell out of
## "define exactly what is used, explicitly, at device -1". The two the keyboard
## added are shortcuts rather than load-bearing: Shift and Delete are on-screen
## keys as well, so a pad missing Square or Triangle loses a shortcut rather
## than the feature. The home button and OPTIONS are not shortcuts -- each is
## the only route to something (leaving a running application, and the options
## menu), which is why both are checked at startup.
##
## Why here. Godot serialises an InputMap override into project.godot as a
## one-line `Object(InputEventJoypadButton,"resource_name":"","device":0,...)`
## blob per event. Those are unreviewable in a diff and easy to corrupt by hand,
## in a repo whose entire discipline is hand-authored, LF-normalised, reviewable
## text. A dozen calls in a file anyone can read is the better trade, and each
## can carry the comment explaining why that binding exists.
##
## Why redefine at all -- two things about the built-in map are not safe to
## inherit on this machine:
##
## 1. DEVICE SCOPING. The built-in events are built with create_reference(),
##    which never calls set_device(), so they inherit InputEvent's default
##    `device = 0`. InputMap::action_match only fires when the action's event is
##    ALL_DEVICES (-1) or its device equals the incoming event's. So the stock
##    d-pad and stick bindings answer to joypad index 0 and nothing else. Godot's
##    joypad index allocation has open bugs (godot#97539, godot#76879, godot#17566)
##    and a hotplug race can leave the only pad on index 1 -- at which point the
##    home rail renders perfectly and ignores the controller, which on an
##    appliance with no terminal is indistinguishable from a hung shell. Every
##    event added here is device -1.
##
## 2. THE ACTION BUTTONS. Sources disagree about whether 4.x binds A to
##    `ui_accept` and B to `ui_cancel` at all, and the answer has to be right on a
##    machine that has no keyboard to fall back to. Binding them explicitly makes
##    the question moot on every engine version, which is cheaper than being sure.
##
## DEADZONE. ProjectSettings registers the built-in directional actions with
##    InputMap::DEFAULT_TOGGLE_DEADZONE (0.5), not the 0.2 that
##    InputMap.add_action() uses. 0.5 is kept: a card rail wants a deliberate
##    push, and a worn stick that drifts past 0.2 would walk the focus on its own.
##    It is a number to tune from the couch, which is why it is named.
##
## `ui_select` (Triangle) is deliberately left alone. Nothing in this shell reads
## it, and adding A to it would give the appliance a second, undocumented activate.

const ALL_DEVICES := -1

## Deliberate push, not a nudge. See the header.
const STICK_DEADZONE := 0.5

## Actions the shell will not function without. Checked at startup because the
## symptom of getting this wrong is silence, and silence on this machine looks
## exactly like a crash.
const REQUIRED_JOYPAD_ACTIONS := [
	"ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel",
	# The keyboard's two. They are shortcuts rather than load-bearing, but the
	# check exists to notice a binding that quietly vanished, and a pad that
	# lost Square/Triangle should say so rather than boot silently.
	"ui_shell_x", "ui_shell_y",
	# Not merely a shortcut, unlike the two above: without a home button there
	# is no way to leave a launched application from a controller at all.
	"ui_shell_home",
	# Nor is this one: OPTIONS is the only way to reach the options menu on the
	# rail, in the file manager and on a store page -- which is to say the only
	# way to uninstall an application, or to copy, rename or delete a file, on a
	# machine with no terminal.
	"ui_shell_options",
	# Shortcuts again, like the keyboard's two: the file manager's panes can be
	# crossed with left and right, so a pad with no shoulders loses a
	# convenience rather than the split view. Listed for the same reason -- a
	# binding that quietly vanished should be noticed by the startup check
	# rather than by someone pressing L1 at the television.
	"ui_shell_l1", "ui_shell_r1",
]


func _ready() -> void:
	# Focus navigation. Both the d-pad and the left stick, because a couch does
	# not care which one the person reached for.
	_define("ui_up", [
		_key(KEY_UP),
		_button(JOY_BUTTON_DPAD_UP),
		_axis(JOY_AXIS_LEFT_Y, -1.0),
	], STICK_DEADZONE)

	_define("ui_down", [
		_key(KEY_DOWN),
		_button(JOY_BUTTON_DPAD_DOWN),
		_axis(JOY_AXIS_LEFT_Y, 1.0),
	], STICK_DEADZONE)

	_define("ui_left", [
		_key(KEY_LEFT),
		_button(JOY_BUTTON_DPAD_LEFT),
		_axis(JOY_AXIS_LEFT_X, -1.0),
	], STICK_DEADZONE)

	_define("ui_right", [
		_key(KEY_RIGHT),
		_button(JOY_BUTTON_DPAD_RIGHT),
		_axis(JOY_AXIS_LEFT_X, 1.0),
	], STICK_DEADZONE)

	# JOY_BUTTON_A is the bottom face button: Cross on a DualSense, A on an Xbox
	# pad. JOY_BUTTON_B is the right one: Circle / B. Godot's mapping database
	# normalises both layouts to these names, so this is correct for either pad
	# without asking which is plugged in.
	_define("ui_accept", [
		_key(KEY_ENTER),
		_key(KEY_KP_ENTER),
		_key(KEY_SPACE),
		_button(JOY_BUTTON_A),
	], STICK_DEADZONE)

	_define("ui_cancel", [
		_key(KEY_ESCAPE),
		_button(JOY_BUTTON_B),
	], STICK_DEADZONE)

	# The keyboard's two shortcuts. JOY_BUTTON_X is the left face button (Square
	# on a DualSense), JOY_BUTTON_Y the top one (Triangle) -- Godot's mapping
	# database normalises both pad layouts to these names. The keyboard bindings
	# are what make the desk harness able to drive the screen at all.
	#
	# `ui_select` is still deliberately left alone: it is a built-in action on
	# the same physical button as ui_shell_y, and nothing here reads it, so the
	# appliance does not gain a second undocumented activate.
	_define("ui_shell_x", [
		_key(KEY_SHIFT),
		_button(JOY_BUTTON_X),
	], STICK_DEADZONE)

	_define("ui_shell_y", [
		_key(KEY_BACKSPACE),
		_button(JOY_BUTTON_Y),
	], STICK_DEADZONE)

	# THE OPTIONS BUTTON, and it is the pad's own, not a face button standing in
	# for one. Options lived on Triangle until the owner pointed out the obvious:
	# the controller has a button with OPTIONS written next to it, and a console
	# UI that puts its options menu somewhere else is asking a person to learn a
	# mapping the hardware already told them.
	#
	# JOY_BUTTON_START is that button on every pad Godot's mapping database
	# normalises: Options on a DualSense, Menu on an Xbox pad, + on a Switch
	# controller. The kernel's hid-playstation driver reports it as BTN_START,
	# which SDL maps to start.
	#
	# TRIANGLE IS NOT ALSO BOUND HERE, deliberately. ui_shell_y survives as the
	# on-screen keyboard's backspace shortcut and nothing else; leaving it as a
	# second door into the options menu would mean the one button whose label
	# says what it does shares the job with one whose label says nothing, and the
	# hint row could only advertise one of them.
	#
	# KEY_MENU is the desk equivalent -- the context-menu key, which is what the
	# Xvfb harness drives it with (`xdotool key Menu`). It is not KEY_TAB on
	# purpose: Godot's built-in ui_focus_next is still bound to Tab, and an
	# action that also walks focus is an action that does two things per press.
	_define("ui_shell_options", [
		_key(KEY_MENU),
		_button(JOY_BUTTON_START),
	], STICK_DEADZONE)

	# THE SHOULDERS, and they exist for exactly one screen: the file manager's
	# split view, where L1 and R1 jump between the two panes.
	#
	# Crossing at the panes' inner edges with left and right already works and is
	# what a person discovers first. The shoulders are there because the gesture
	# split view exists FOR is copy-from-one-side-to-the-other, which means
	# crossing constantly -- and from the middle of a forty-row listing, "left
	# until you fall out of this pane" is a dozen presses that also lose your
	# place in the column. L1/R1 is one press and keeps both cursors.
	#
	# JOY_BUTTON_LEFT_SHOULDER / RIGHT_SHOULDER are L1/R1 on a DualSense and
	# LB/RB on an Xbox pad; Godot's mapping database normalises both. The
	# brackets are the desk equivalents and what the Xvfb harness drives them
	# with -- chosen over Page_Up/Page_Down because a scroll container is
	# entitled to those and a shortcut that also scrolls is two things per press.
	_define("ui_shell_l1", [
		_key(KEY_BRACKETLEFT),
		_button(JOY_BUTTON_LEFT_SHOULDER),
	], STICK_DEADZONE)

	_define("ui_shell_r1", [
		_key(KEY_BRACKETRIGHT),
		_button(JOY_BUTTON_RIGHT_SHOULDER),
	], STICK_DEADZONE)

	# THE HOME BUTTON, ON TWO PADS' WORTH OF BUTTONS, because the obvious one is
	# not always ours to have.
	#
	# JOY_BUTTON_GUIDE is the PS button on a DualSense and the Xbox button on an
	# Xbox pad; hid-playstation reports it as BTN_MODE and SDL maps it to guide.
	# It is the button a console user already knows means "get me out of this",
	# and it stays first here for exactly that reason.
	#
	# BUT STEAM TAKES IT. In Big Picture, Steam Input binds Guide for its own
	# menu and reads the device directly -- gamescope has no gamepad handling at
	# all, so nothing in the compositor can arbitrate. On 2026-08-13 the owner
	# launched Steam and could not get out of it: Guide went to Steam, Steam's
	# own Shut Down did nothing (it wants SteamOS's session manager), there is no
	# console login on this image, and sshd was down. The only exit from an
	# application was the physical power button.
	#
	# So SHARE is a home button too. JOY_BUTTON_BACK is Share on a DualShock 4,
	# Create on a DualSense and View on an Xbox pad -- BTN_SELECT to the kernel.
	# Steam does not bind it, which is the whole point: an escape that depends on
	# the cooperation of the program you are escaping is not an escape.
	#
	# ALWAYS BOUND, NOT ONLY WHILE STEAM RUNS, and that is deliberate rather than
	# lazy. A binding that changes depending on what is running is one nobody can
	# learn, and the shell would have to know Steam is up -- which is exactly the
	# kind of state this shell keeps getting wrong. It costs nothing when idle:
	# shell_root only acts on this action while Launcher.is_busy(), so at the
	# rail Share does nothing at all.
	#
	# The cost is real and worth stating: a game that uses Share for its own
	# purpose will also open this menu. That is the trade for having a way out
	# that cannot be taken away.
	#
	# KEY_HOME is the desk equivalent, which is also what the Xvfb harness
	# drives it with.
	_define("ui_shell_home", [
		_key(KEY_HOME),
		_button(JOY_BUTTON_GUIDE),
		_button(JOY_BUTTON_BACK),
	], STICK_DEADZONE)

	_verify()


## Rebuilds one action from scratch. Erasing first matters: action_add_event
## appends, so without it the built-in device-0 events survive alongside ours and
## the device scoping this file exists to fix would still be half in force.
func _define(action: String, events: Array, deadzone: float) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
		InputMap.action_set_deadzone(action, deadzone)
	else:
		InputMap.add_action(action, deadzone)
	for event in events:
		InputMap.action_add_event(action, event)


func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.device = ALL_DEVICES
	return event


func _button(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.device = ALL_DEVICES
	return event


## `value` is only ever -1.0 or 1.0: InputMap matches on the sign, and the
## magnitude that matters is the action's deadzone, not this.
func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = ALL_DEVICES
	return event


## The regression guard, in the same spirit as the Containerfile's ICD and
## initramfs assertions: a build or an edit that removes the joypad half of an
## action must say so somewhere a human will find it, rather than shipping a shell
## that navigates and cannot be activated.
##
## It logs rather than aborts. A shell that refuses to start is a black TV; a
## shell that starts with a loud journal line is still recoverable over devmode
## ssh. assert() would also be compiled out of the release export, which is the
## only build that ever runs on the appliance.
func _verify() -> void:
	var missing := PackedStringArray()
	for action in REQUIRED_JOYPAD_ACTIONS:
		if not _has_joypad_binding(action):
			missing.append(action)
	if missing.is_empty():
		# Counted, not spelled out: the literal said "six" for a while after the
		# map grew to eight, which is exactly the kind of quiet lie a journal
		# should not contain on a machine where the journal is the only witness.
		ShellLog.info("input map ready; joypad bindings present on all %d required actions"
			% REQUIRED_JOYPAD_ACTIONS.size())
		return
	ShellLog.error(
		"no joypad binding on %s -- the shell will be unusable from a controller"
		% ", ".join(missing)
	)


func _has_joypad_binding(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false
