extends Node

## ============================================================================
## THE SETTINGS SEAM.
##
## The same shape as the launch seam -- one entry point, two signals, one thing
## at a time -- and deliberately a SEPARATE one. The launch seam is the file
## Phase 1 rewires to marwand over the WebSocket, and a shell-internal screen
## swap must not be sitting inside it when that happens: settings is not an app,
## and opening it must not become an RPC by accident. Launcher.launch stays the
## only call into the launch path; Settings.open is the only call into this one.
##
## Sharing the shape is the point of the shape. shell_root hands the screen over
## and takes it back identically for both seams, so a third fullscreen surface
## (Phase 1's store, a guide overlay) has a pattern to copy rather than a
## precedent to untangle.
##
## Phase 0's settings screen is read-only -- see settings_screen.gd for why.
## When Phase 1's daemon exists, a row that changes something sends the change
## to marwand and this file still only opens and closes the screen. The shell
## is a renderer; that rule does not bend for its own furniture.
## ============================================================================

## Emitted the moment the screen is requested, before anything is on screen.
## The home rail uses it to save focus and get out of the way.
signal settings_opened()

## Emitted when the screen is gone and the home rail should come back.
signal settings_closed()

const SettingsScreen = preload("res://src/settings_screen.gd")

# Typed as the script rather than as Control so `closed` resolves statically --
# the same argument as Launcher's _placeholder.
var _screen: SettingsScreen = null


func is_open() -> bool:
	return _screen != null


## The only way the settings screen gets opened.
func open() -> void:
	if is_open():
		# One at a time, same as the launcher: a second press while the screen
		# is up is a bounced button, not a request for two.
		return
	if Launcher.is_busy():
		# The home rail is already hidden behind a launch. Opening settings on
		# top would stack two surfaces that both restore the rail on close, and
		# whichever closed second would restore it twice.
		return
	if Power.is_open() or Info.is_open() or Files.is_open() or Browser.is_open() or WindowsInstall.is_open():
		# The shell surfaces are peers, not layers: whichever is up owns the
		# screen until it closes. (The others hold the mirror guards.)
		return

	ShellLog.info("settings opened")

	# Assigned BEFORE the emit, so is_open() is already true for every handler
	# of settings_opened -- the same ordering that makes the launcher safe
	# against a handler calling back in (_current is set before launch_started
	# fires). The screen only joins the tree AFTER the emit, because its _ready
	# grabs focus and the home rail's handler must capture the old focus owner
	# first.
	_screen = SettingsScreen.new()
	_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)

	settings_opened.emit()
	get_tree().root.add_child(_screen)


func _on_closed() -> void:
	# Deferred for the same reason Launcher defers: the signal arrives from
	# inside the screen's own input handling, and removing a node from the tree
	# part-way through input propagation is asking for trouble.
	_finish.call_deferred()


func _finish() -> void:
	var screen := _screen
	_screen = null
	if is_instance_valid(screen):
		# remove_child first, queue_free second: queue_free is deferred to the
		# end of the frame, so on its own it would leave the screen drawn over
		# the home rail for the frame in which focus is being restored.
		screen.get_parent().remove_child(screen)
		screen.queue_free()

	ShellLog.info("settings closed")
	settings_closed.emit()
