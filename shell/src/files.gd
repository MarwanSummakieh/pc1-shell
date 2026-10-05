extends Node

## ============================================================================
## THE FILES SEAM. Fifth fullscreen surface, same pattern as settings, stores
## and power: one entry point, two signals, one thing at a time, mutual guards.
##
## The screen it opens is the shell's own file manager -- built here rather
## than shipped as the Dolphin flatpak, because Dolphin under the pad bridge is
## a desktop program being puppeted (arrow keys into a UI drawn for a mouse)
## and a file browser is exactly the kind of furniture the shell can draw
## natively: rows, a focus chain, and verbs the pad already has buttons for.
## Everything the screen touches is the local filesystem through DirAccess and
## FileAccess -- no daemon, no RPC -- so this seam owns nothing but the screen
## swap, which is the whole reason it can stay this small.
## ============================================================================

## Emitted the moment the screen is requested, before anything is on screen.
## The home rail uses it to save focus and get out of the way.
signal files_opened()

## Emitted when the screen is gone and the home rail should come back.
signal files_closed()

const FilesScreen = preload("res://src/files_screen.gd")

# Typed as the script rather than as Control so `closed` resolves statically --
# the same argument as Launcher's _placeholder.
var _screen: FilesScreen = null


func is_open() -> bool:
	return _screen != null


## The only way the files screen gets opened.
func open() -> void:
	if is_open():
		# One at a time, same as the launcher: a second press while the screen
		# is up is a bounced button, not a request for two.
		return
	if Launcher.is_busy():
		# The home rail is already hidden behind a launch; stacking a second
		# restoring surface would restore it twice. Same guard as settings.
		return
	if Settings.is_open() or Power.is_open() or Info.is_open() or Browser.is_open() or WindowsInstall.is_open():
		# The shell surfaces are peers, not layers: whichever is up owns the
		# screen until it closes. (The others hold the mirror guards.)
		return

	ShellLog.info("files opened")

	# Assigned BEFORE the emit and added to the tree AFTER it, for the seam's
	# standard ordering: is_open() is true for every handler of files_opened,
	# and the home rail captures its focus owner before the screen's _ready
	# grabs focus.
	_screen = FilesScreen.new()
	_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)

	files_opened.emit()
	get_tree().root.add_child(_screen)


## Programmatic close, for symmetry with open(). Nothing calls it today -- the
## screen closes itself off B -- but a seam whose open has no close is a seam
## someone will eventually reach around.
func close() -> void:
	if not is_open():
		return
	_finish.call_deferred()


func _on_closed() -> void:
	# Deferred for the launcher's reason: the signal arrives from inside the
	# screen's own input handling, and removing a node from the tree part-way
	# through input propagation is asking for trouble.
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

	ShellLog.info("files closed")
	files_closed.emit()
