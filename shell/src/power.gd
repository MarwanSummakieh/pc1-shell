extends Node

## ============================================================================
## THE POWER SEAM. Fourth fullscreen surface, same pattern as settings and
## stores: one entry point, two signals, one thing at a time, mutual guards.
## The screen it opens offers exactly three verbs -- off, restart, sleep --
## and every one of them acts through the update seam's request file, so this
## seam owns nothing but the screen swap.
## ============================================================================

signal power_opened()
signal power_closed()

const PowerScreen = preload("res://src/power_screen.gd")

var _screen: PowerScreen = null


func is_open() -> bool:
	return _screen != null


func open() -> void:
	if is_open():
		return
	if Launcher.is_busy():
		return
	if Settings.is_open() or Info.is_open() or Files.is_open() or Browser.is_open() or WindowsInstall.is_open():
		# Peers, not layers -- same rule the other two enforce against each
		# other and now against this one.
		return

	ShellLog.info("power menu opened")

	_screen = PowerScreen.new()
	_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)

	power_opened.emit()
	get_tree().root.add_child(_screen)


func _on_closed() -> void:
	_finish.call_deferred()


func _finish() -> void:
	var screen := _screen
	_screen = null
	if is_instance_valid(screen):
		screen.get_parent().remove_child(screen)
		screen.queue_free()

	ShellLog.info("power menu closed")
	power_closed.emit()
