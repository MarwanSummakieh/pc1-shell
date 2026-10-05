extends Node

## ============================================================================
## THE INFO SEAM. Fifth fullscreen surface, same pattern as settings, stores,
## power and files: one entry point, two signals, one thing at a time, mutual
## guards. The screen it opens changes nothing at all -- it is every fact the
## machine can state about itself, on one page -- so this seam owns nothing but
## the screen swap.
##
## WHY IT BECAME A SEAM. Info used to be a CHILD of the settings screen, reached
## by a row at the top of it. That made settings the only door, and settings is
## a list of things you can DO -- so the one page that does nothing was filed
## behind the page for acting. The menu rewrite of 2026-08-12 moved the door: the
## bar's status corner (the wifi glyph and the clock) opens this directly, which
## is the honest arrangement -- the control that SHOWS the machine's state is the
## control that opens everything else the machine knows about itself. Being a
## peer of settings rather than a child of it is what lets the corner open it
## without settings being on screen underneath.
##
## ONE DOOR, NOT TWO. The settings screen's Info row went with the move rather
## than staying as a shortcut. ADR 0006's one thing, one home: a surface with two
## doors is two implementations of opening it, and this whole rewrite exists
## because a second door had been quietly growing a second copy of everything
## behind it.
## ============================================================================

signal info_opened()
signal info_closed()

const InfoScreen = preload("res://src/info_screen.gd")

# Typed as the script rather than as Control so `closed` resolves statically --
# the same argument the other four seams make.
var _screen: InfoScreen = null


func is_open() -> bool:
	return _screen != null


func open() -> void:
	if is_open():
		# One at a time: a second press while the screen is up is a bounced
		# button, not a request for two.
		return
	if Launcher.is_busy():
		# The home rail is already hidden behind a launch. Opening on top would
		# stack two surfaces that both restore the rail on close, and whichever
		# closed second would restore it twice.
		return
	if Settings.is_open() or Power.is_open() or Files.is_open() or Browser.is_open() or WindowsInstall.is_open():
		# The shell surfaces are peers, not layers: whichever is up owns the
		# screen until it closes.
		return

	ShellLog.info("info opened")

	# Assigned BEFORE the emit, so is_open() is already true for every handler
	# of info_opened. The screen only joins the tree AFTER the emit, because its
	# _ready grabs focus and the home rail's handler must capture the old focus
	# owner first -- which is what puts focus back on the status corner when this
	# closes.
	_screen = InfoScreen.new()
	_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)

	info_opened.emit()
	get_tree().root.add_child(_screen)


func _on_closed() -> void:
	# Deferred for the reason every seam here defers: the signal arrives from
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

	ShellLog.info("info closed")
	info_closed.emit()
