extends Node

## Held-direction repeat for focus navigation, which Godot does not do for a
## gamepad.
##
## The keyboard path gets repeat for free: the viewport's focus navigation calls
## is_action_pressed(action, allow_echo = true), and a held arrow key produces OS
## key echo. A pad cannot use that. InputEventJoypadButton is only emitted on a
## state change, and the stick branch is gated on "just pressed", so holding the
## d-pad or leaning on the stick moves focus exactly once. Crossing the home
## rail's twelve cards then takes eleven separate presses.
##
## That failure mode is worth naming precisely, because it is invisible to every
## automated check: every line of code works as designed, ADR 0004's step-4 script
## exercises the supervision loop with pkill and never touches navigation, and the
## only test that catches it is a person on a sofa. Hence this file.
##
## HOW THE MOVE IS MADE. An InputEventAction is pushed through
## Input.parse_input_event() rather than calling into the focus machinery
## directly. InputMap has an explicit fast path for InputEventAction, so the
## synthetic press takes exactly the same route through the viewport as a real
## one -- same neighbour resolution, same ScrollContainer.follow_focus handling,
## same behaviour on any screen added later that handles ui_* itself. A matching
## release follows immediately so the global action state does not latch on.
##
## THE PAD IS POLLED DIRECTLY, PER DEVICE. Input.is_action_pressed() would answer
## for any device, which would let a second controller drive the repeat straight
## past PlayerOne's gate. Reading the claimed device's buttons and axes keeps one
## rule about who is in charge. The keyboard is deliberately not polled here --
## OS key echo already repeats it, and doing both would double the rate.

## Long enough that a single deliberate press moves exactly one card.
const INITIAL_DELAY := 0.40

## Roughly eight cards a second once it starts. Fast enough to cross the rail,
## slow enough to stop where you meant to.
const REPEAT_INTERVAL := 0.12

## Matches ShellInput.STICK_DEADZONE. The two have to agree or the stick will
## repeat in a range where it does not navigate, or the reverse.
const STICK_DEADZONE := 0.5

var _direction := Vector2i.ZERO
var _countdown := 0.0


func _process(delta: float) -> void:
	if SteamEmbed.owns_input() and not TextInput.is_open():
		_direction = Vector2i.ZERO
		return
	var direction := _held_direction()

	if direction != _direction:
		# A new direction. The real event that produced it has already moved
		# focus once, so this only arms the timer.
		_direction = direction
		_countdown = INITIAL_DELAY
		return

	if direction == Vector2i.ZERO:
		return

	_countdown -= delta
	if _countdown > 0.0:
		return

	_countdown = REPEAT_INTERVAL
	_repeat(direction)


func _held_direction() -> Vector2i:
	var pad := PlayerOne.device
	if pad < 0:
		return Vector2i.ZERO

	var stick_x := PlayerOne.axis(JOY_AXIS_LEFT_X)
	var stick_y := PlayerOne.axis(JOY_AXIS_LEFT_Y)

	var direction := Vector2i.ZERO
	if PlayerOne.button(JOY_BUTTON_DPAD_LEFT) or stick_x <= -STICK_DEADZONE:
		direction.x -= 1
	if PlayerOne.button(JOY_BUTTON_DPAD_RIGHT) or stick_x >= STICK_DEADZONE:
		direction.x += 1
	if PlayerOne.button(JOY_BUTTON_DPAD_UP) or stick_y <= -STICK_DEADZONE:
		direction.y -= 1
	if PlayerOne.button(JOY_BUTTON_DPAD_DOWN) or stick_y >= STICK_DEADZONE:
		direction.y += 1

	if direction.x != 0 and direction.y != 0:
		# A stick pushed 30 degrees off the horizontal still clears a 0.5 deadzone
		# on both axes, which is most of what "push right" actually looks like.
		# Refusing to repeat on a diagonal would stall on an ordinary push, so the
		# larger deflection wins. On a d-pad diagonal both axes read zero and
		# horizontal takes it, which is the conventional choice.
		if absf(stick_x) >= absf(stick_y):
			direction.y = 0
		else:
			direction.x = 0

	return direction


func _repeat(direction: Vector2i) -> void:
	if direction.x < 0:
		_send("ui_left")
	elif direction.x > 0:
		_send("ui_right")
	elif direction.y < 0:
		_send("ui_up")
	else:
		_send("ui_down")


func _send(action: String) -> void:
	# No focus owner means no home rail on screen -- the launch placeholder is up,
	# or the tree has not finished building. Repeating into that would move focus
	# behind whatever is covering it.
	if TextInput.focus_viewport().gui_get_focus_owner() == null:
		return

	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)

	# Without this the action stays "pressed" in Input's own state forever, since
	# nothing else will ever release a synthetic press.
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
