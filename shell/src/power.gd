extends Node

## ============================================================================
## THE POWER SEAM. Fourth fullscreen surface, same pattern as settings and
## stores: one entry point, two signals, one thing at a time, mutual guards.
## System power actions use the update seam. Display-only rest stays in the
## player session so Bluetooth input remains available to wake the screen.
## ============================================================================

signal power_opened()
signal power_closed()

const PowerScreen = preload("res://src/power_screen.gd")
const RestScreen = preload("res://src/rest_screen.gd")

var _screen: PowerScreen = null
var _rest: CanvasLayer = null


func _ready() -> void:
	RestScreen.recover_display()


func start_rest() -> bool:
	if is_instance_valid(_rest):
		return false
	var screen := RestScreen.new()
	get_tree().root.add_child(screen)
	if not screen.begin():
		screen.queue_free()
		return false
	_rest = screen
	screen.woke.connect(func(): _rest = null, CONNECT_ONE_SHOT)
	return true


func _on_rest_requested() -> void:
	if start_rest():
		_screen.closed.emit()
	else:
		_screen.show_rest_error()
		ShellLog.warn("rest mode unavailable: display power control failed")


func is_open() -> bool:
	return _screen != null


func open() -> void:
	if is_open():
		return
	if Launcher.is_busy():
		return
	if Settings.is_open() or Info.is_open() or Files.is_open() or Browser.is_open() or WindowsInstall.is_open() or Downloads.is_open():
		# Peers, not layers -- same rule the other two enforce against each
		# other and now against this one.
		return

	ShellLog.info("power menu opened")

	_screen = PowerScreen.new()
	_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)
	_screen.rest_requested.connect(_on_rest_requested)

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
