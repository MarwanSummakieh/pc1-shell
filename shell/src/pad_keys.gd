extends Node

## The pad bridge: how a gamepad drives an application that has never heard
## of one. Two dialects, chosen per application by Catalogue.PAD_KEY_APPS.
##
## "keys" -- arrows, open, back, context menu: the verbs a keyboard-navigable
## UI can honour from a stick. Built for the Dolphin flatpak before the shell
## grew its own Files screen; no application uses it today, and it stays
## because the next keyboard-driven desktop app is one catalogue line away
## from needing exactly this again.
##
## "pointer" -- the Steam desktop client's dialect. That client is a
## mouse-first UI; arrows land nowhere useful, so the stick moves a real X
## cursor instead (relative moves at a fixed cadence), A clicks, Y
## right-clicks, B sends Escape, and the shoulders scroll. The same trick
## every console's built-in browser plays, done here with xdotool because the
## X server is already there and XTEST aims at whatever holds focus -- which
## under gamescope is the running application.
##
## WHAT MAKES INJECTION SAFE HERE: the shell KEEPS RECEIVING PAD INPUT while
## another client owns the screen (both read evdev; see stores_screen's
## deafness note, which exists because of exactly this), so no focus, grab or
## protocol needs negotiating. The bridge listens where the shell already
## hears, and xdotool delivers where gamescope already points.
##
## WHO STARTS AND STOPS THIS IS THE SEAM'S BUSINESS, NOT OURS. Launcher
## creates the bridge only once the window watchdog has SEEN the application
## take the screen (Focus.ELSEWHERE) -- injecting into an app that has not
## drawn yet queues phantom input behind a splash -- and frees it when the
## launch finishes or is minimized. While the home menu is over the
## application, shell_root pauses it: the same press must not both move the
## menu and reach the app behind it. The pause is explicit rather than
## inferred from focus, because a launch from the stores screen leaves a deaf
## store tab holding GUI focus the whole time and any focus-based inference
## reads that as "shell UI active" forever.
##
## Per-event process spawn is the cost, and it is priced per dialect: keys
## fire at human browsing speed, and pointer moves are batched to
## POINTER_FLUSH_SECONDS so a held stick costs twenty tiny processes a
## second, not sixty. If a future bridge needs gaming-rate input it needs
## uinput and a daemon, not a faster xdotool.

const REPEAT_DELAY := 0.4
const REPEAT_INTERVAL := 0.12

## Keys dialect: action -> X keysym. Only the arrows repeat; Return,
## BackSpace and Menu on hold would be a machine gun pointed at a file tree.
const KEY_FOR_ACTION := {
	"ui_up": "Up",
	"ui_down": "Down",
	"ui_left": "Left",
	"ui_right": "Right",
	"ui_accept": "Return",
	"ui_cancel": "BackSpace",
	"ui_shell_y": "Menu",
}

const REPEATING := ["ui_up", "ui_down", "ui_left", "ui_right"]

## Pointer dialect: button actions -> what they inject. Movement is not in
## this table -- it is read as axis strength in _process, so the stick's
## whole range matters and the dpad (bound to the same actions) nudges.
const POINTER_FOR_ACTION := {
	"ui_accept": ["click", "1"],
	"ui_shell_y": ["click", "3"],
	"ui_cancel": ["key", "--clearmodifiers", "Escape"],
}

## Full-tilt cursor speed, in pixels per second of the DESIGN surface. Brisk
## enough to cross 1920 in about two seconds, slow enough to land on a row in
## a library list. The response curve below is what makes both true at once.
const POINTER_SPEED := 900.0

## Squaring the deflection gives the stick a slow edge without costing the
## fast middle -- the same curve every console pointer uses.
const POINTER_CURVE := 2.0

## How often accumulated movement becomes one xdotool call. Twenty a second
## reads as continuous on a TV and keeps the spawn cost trivial.
const POINTER_FLUSH_SECONDS := 0.05

## Scroll clicks (X buttons 4/5) repeat at this interval while a shoulder is
## held. Joypad shoulder buttons arrive as raw button events because the
## shell's nine actions deliberately do not cover them.
const SCROLL_INTERVAL := 0.1

## "keys" or "pointer"; set by Launcher before the node enters the tree.
var mode := "keys"

var paused := false
var _await_neutral := true

var _held := ""
var _repeat: Timer = null

var _pointer_acc := Vector2.ZERO
var _flush_clock := 0.0
var _scroll_button := 0
var _scroll: Timer = null

## Said once if xdotool cannot be run, not once per press: the bridge failing
## is one fact, and the journal needs it exactly one time to name the missing
## binary.
var _spawn_warned := false


func _ready() -> void:
	_repeat = Timer.new()
	_repeat.one_shot = true
	_repeat.timeout.connect(_on_repeat)
	add_child(_repeat)

	_scroll = Timer.new()
	_scroll.wait_time = SCROLL_INTERVAL
	_scroll.timeout.connect(_on_scroll_tick)
	add_child(_scroll)

	set_process(true)
	ShellLog.info("pad bridge up in %s mode" % mode)


func _input(event: InputEvent) -> void:
	if paused:
		return
	if _await_neutral:
		if not event.is_action("ui_shell_home"):
			get_viewport().set_input_as_handled()
		return
	if mode == "pointer":
		_pointer_input(event)
		return

	for action in KEY_FOR_ACTION:
		if event.is_action_pressed(action):
			# Consumed so the deaf-but-listening shell surfaces underneath
			# never act on the same press the application just received.
			get_viewport().set_input_as_handled()
			_run(["key", "--clearmodifiers", str(KEY_FOR_ACTION[action])])
			if REPEATING.has(action):
				_held = action
				_repeat.start(REPEAT_DELAY)
			return
		if event.is_action_released(action):
			if action == _held:
				_held = ""
				_repeat.stop()
			return


func _pointer_input(event: InputEvent) -> void:
	for action in POINTER_FOR_ACTION:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			_run(POINTER_FOR_ACTION[action].duplicate())
			return

	# The shoulders scroll, and they arrive as raw buttons because no action
	# covers them -- the input map's nine are the shell's own vocabulary and
	# scrolling is not in it. First press scrolls immediately; the timer
	# carries the hold.
	if event is InputEventJoypadButton:
		var button := 0
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			button = 4
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			button = 5
		if button == 0:
			return
		if event.pressed and _scroll_button != button:
			_scroll_button = button
			_run(["click", str(button)])
			_scroll.start()
		elif not event.pressed and _scroll_button == button:
			_scroll_button = 0
			_scroll.stop()


## Movement is polled, not event-driven: an analogue stick held at half tilt
## produces no further events, and a cursor that only moves on wiggle is a
## broken mouse. Accumulated in floats so slow deflections still add up to
## whole pixels instead of rounding to zero forever.
func _process(delta: float) -> void:
	if paused:
		return
	if _await_neutral:
		if _controls_neutral():
			_await_neutral = false
		return
	if mode != "pointer":
		return
	var dx := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	var dy := Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	var tilt := Vector2(dx, dy)
	if tilt.length() > 1.0:
		tilt = tilt.normalized()
	_pointer_acc += tilt * tilt.length() ** (POINTER_CURVE - 1.0) * POINTER_SPEED * delta

	_flush_clock += delta
	if _flush_clock < POINTER_FLUSH_SECONDS:
		return
	_flush_clock = 0.0
	var step := Vector2i(_pointer_acc)
	if step == Vector2i.ZERO:
		return
	_pointer_acc -= Vector2(step)
	# `--` so a leftward move's negative number is not read as an option.
	_run(["mousemove_relative", "--", str(step.x), str(step.y)])


## Releasing the pause mid-hold must not resurrect a repeat armed before the
## menu opened; the person's thumb has long since moved on.
func set_paused(value: bool) -> void:
	paused = value
	_await_neutral = true
	if paused:
		_held = ""
		_repeat.stop()
		_scroll_button = 0
		_scroll.stop()
		_pointer_acc = Vector2.ZERO


func _controls_neutral() -> bool:
	for index in 15:
		if index not in [JOY_BUTTON_BACK, JOY_BUTTON_GUIDE] and PlayerOne.button(index):
			return false
	for index in 6:
		if absf(PlayerOne.axis(index)) > 0.2:
			return false
	for action in KEY_FOR_ACTION:
		if Input.is_action_pressed(action):
			return false
	return true


func _on_repeat() -> void:
	if _held.is_empty() or paused:
		return
	_run(["key", "--clearmodifiers", str(KEY_FOR_ACTION[_held])])
	_repeat.start(REPEAT_INTERVAL)


func _on_scroll_tick() -> void:
	if _scroll_button == 0 or paused:
		return
	_run(["click", str(_scroll_button)])


func _run(args: Array) -> void:
	var packed := PackedStringArray()
	for arg in args:
		packed.append(str(arg))
	var pid := OS.create_process("xdotool", packed)
	if pid <= 0 and not _spawn_warned:
		_spawn_warned = true
		ShellLog.warn("cannot run xdotool; the pad bridge is gesturing into a void")
