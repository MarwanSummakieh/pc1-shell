extends Node

## Which controller is driving the shell, and what happens when it is unplugged.
##
## M3 asks for an explicit player-1 notion and for unplug/replug mid-session to
## keep working. Those are the same problem: "player one" has to be an identity
## that survives the index changing underneath it.
##
## IDENTITY IS THE GUID, NOT THE INDEX. Godot hands out joypad slots from
## Input::get_unused_joy_id(), which returns the lowest free index, so a pad
## normally comes back on the index it left. Normally is not always, and the index
## is a slot number rather than a name. The claim is therefore keyed on
## Input.get_joy_guid() and re-attaches to whatever index the same controller
## turns up on.
##
## THE HOTPLUG SIGNAL IS NOT TRUSTWORTHY ON ITS OWN. Godot has open, unfixed bugs
## where a removal emits nothing (godot#97539, godot#76879, godot#17566). A
## player-1 implementation that only listens to joy_connection_changed wedges: the
## shell believes it still has a controller, the person on the couch has one that
## does nothing, and the appliance has no other way to say so. So the signal is the
## fast path and a once-a-second reconcile against Input.get_connected_joypads()
## is the backstop.
##
## GATING OTHER PADS HAPPENS IN _input, NOT BY DEVICE-SCOPING THE ACTIONS.
## Viewport::push_input dispatches _input before the GUI pass, and
## set_input_as_handled() from there stops the event reaching focus navigation.
## Doing it this way keeps every action bound at device -1, so no index change can
## brick the shell, and keeps the policy in one readable function instead of
## spread across serialised event objects.
##
## Gamepad input never touches the compositor: Godot reads /dev/input/event*
## directly (SDL3 since 4.5, evdev before that), and neither gamescope nor cage
## grabs those devices. So everything in this file behaves identically under plan
## A and plan B. The only precondition is read access to /dev/input, which the
## Containerfile secures by putting `player` in the `input` group.

signal player_one_present(device: int, pad_name: String)
signal player_one_absent()

## The backstop poll interval. Fast enough that a silent disconnect shows on the
## screen while the person is still holding the cable, cheap enough to ignore.
const RECONCILE_SECONDS := 1.0

## Slot the claim currently sits on, or -1 when the claimed controller is gone.
var device: int = -1

## Durable identity, kept across a disconnect so a replug is recognised as the
## same controller rather than as a new one.
var guid: String = ""
var pad_name: String = ""


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	var timer := Timer.new()
	timer.wait_time = RECONCILE_SECONDS
	timer.autostart = true
	timer.timeout.connect(_reconcile)
	add_child(timer)

	# Pads plugged in before the shell started may or may not have produced a
	# connection signal by now, depending on where in engine startup they were
	# enumerated. Reconciling once here removes the question.
	_reconcile()


func has_controller() -> bool:
	return device >= 0


func axis(index: int) -> float:
	if ControllerRouter.is_active():
		return float(ControllerRouter._axes[index]) if device >= 0 else 0.0
	return Input.get_joy_axis(device, index) if device >= 0 else 0.0


func button(index: int) -> bool:
	if ControllerRouter.is_active():
		return bool(ControllerRouter._buttons[index]) if device >= 0 else false
	return Input.is_joy_button_pressed(device, index) if device >= 0 else false


func _on_joy_connection_changed(joy_device: int, connected: bool) -> void:
	if ControllerRouter.is_active():
		return
	if connected:
		_consider(joy_device)
	elif joy_device == device:
		_release("disconnected")


## Decides whether a connected pad becomes player one. Called from the signal,
## from the reconcile timer, and from the first joypad event seen -- three routes
## to the same place, because none of the three is reliable alone.
func _consider(candidate: int) -> void:
	if candidate < 0 or candidate == device:
		return

	if device >= 0:
		# Player one is live. A second pad is not an error and is not player two
		# either -- Phase 0 is a single-player appliance and the extra device is
		# simply ignored (see _input).
		ShellLog.info("ignoring extra controller on index %d (%s)"
			% [candidate, Input.get_joy_name(candidate)])
		return

	var candidate_guid := Input.get_joy_guid(candidate)
	var candidate_name := Input.get_joy_name(candidate)

	# An empty GUID is a slot mid-teardown, not a controller. Measured on
	# hardware 2026-08-05: a plain unplug/replug produced a connect event on a
	# slot whose GUID and name both came back "", which the code below then
	# treated as a DIFFERENT controller claiming player one -- overwriting the
	# very identity `guid` exists to preserve across a disconnect. The tell was
	# the replug logging "player one claimed" instead of "player one reconnected".
	#
	# It self-corrected with one pad in the room, so nothing was visible from the
	# couch. With two, _reconcile()'s "prefer the controller we already know" pass
	# has an empty string to match against and claims whichever pad it finds
	# first, which is the wrong one half the time.
	#
	# Returning is safe rather than merely conservative: the reconcile timer comes
	# back within RECONCILE_SECONDS, and by then the slot either has a real GUID or
	# is gone. The cost of being wrong here is at most a one-second delay in
	# claiming; the cost of accepting the empty string is losing the identity.
	if candidate_guid.is_empty():
		ShellLog.warn("ignoring claim from index %d with no GUID (slot is mid-teardown, not a controller)"
			% candidate)
		return

	var previous_guid := guid

	device = candidate
	guid = candidate_guid
	pad_name = candidate_name

	if previous_guid.is_empty():
		ShellLog.info("player one claimed: index %d, %s, guid %s"
			% [candidate, candidate_name, candidate_guid])
	elif previous_guid == candidate_guid:
		ShellLog.info("player one reconnected on index %d (%s)"
			% [candidate, candidate_name])
	else:
		# The reported GUID can move under us. SDL3's HIDAPI driver wants
		# /dev/hidraw*, which is root-only without Steam-style udev rules that
		# this image does not ship, so the DualSense normally arrives through the
		# kernel's hid-playstation evdev path -- and if hidraw ever does become
		# readable, the GUID and mapping change between runs. Re-claiming is the
		# right answer: an appliance that refuses input because an identity moved
		# is worse than one that accepts the only controller in the room.
		ShellLog.warn("player one re-claimed by a different controller: %s -> %s (%s)"
			% [previous_guid, candidate_guid, candidate_name])

	player_one_present.emit(device, pad_name)


func _release(reason: String) -> void:
	if device < 0:
		return
	ShellLog.warn("player one %s: was index %d, %s (guid %s kept for reconnect)"
		% [reason, device, pad_name, guid])
	device = -1
	player_one_absent.emit()


## The backstop for the hotplug signals that do not always arrive.
func _reconcile() -> void:
	if ControllerRouter.is_active():
		return
	var connected := Input.get_connected_joypads()

	if device >= 0 and not connected.has(device):
		_release("vanished without a disconnect signal")

	if device >= 0:
		return

	# Prefer the controller we already know. Only if it is genuinely absent does
	# _consider fall through to claiming whatever else is plugged in.
	for candidate in connected:
		if Input.get_joy_guid(candidate) == guid:
			_consider(candidate)
			return
	for candidate in connected:
		_consider(candidate)
		if device >= 0:
			return


func _input(event: InputEvent) -> void:
	# Only joypad events. An InputEventKey carries device 0 like everything else,
	# so gating on the device number alone would silently kill the keyboard the
	# moment player one landed on index 1 -- and the keyboard is how the shell is
	# driven at a desk.
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if ControllerRouter.is_active():
		if event.device != ControllerRouter.DEVICE or device < 0:
			get_viewport().set_input_as_handled()
		return

	if device < 0:
		# Last route in. If both the signal and the reconcile missed a pad, the
		# first thing the person presses claims it. The event is deliberately not
		# consumed: the press that claims the controller should also do what it
		# was pressed for.
		_consider(event.device)
		return

	if event.device != device:
		get_viewport().set_input_as_handled()


func set_routed_controller(connected: bool, routed_device: int, controller_name: String) -> void:
	if not connected:
		_release("disconnected")
		return
	device = routed_device
	guid = "pc1-controller-router"
	pad_name = controller_name
	player_one_present.emit(device, pad_name)
