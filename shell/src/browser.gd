extends Node

signal opened()
signal closed()

const BrowserScreen = preload("res://src/browser_screen.gd")
var _screen: Control = null
var _visible := false


func is_open() -> bool:
	return _visible and is_instance_valid(_screen)


func open() -> void:
	if is_open() or Launcher.is_busy() or Files.is_open() or Settings.is_open() \
			or Power.is_open() or Info.is_open() or WindowsInstall.is_open():
		return
	_visible = true
	if is_instance_valid(_screen):
		_screen.show()
		_screen.set_process_unhandled_input(true)
		opened.emit()
		return
	_screen = BrowserScreen.new()
	_screen.return_label = "Return to library"
	_screen.closed.connect(_finish)
	opened.emit()
	get_tree().root.add_child(_screen)
	_screen.open_url("https://duckduckgo.com", "Search the web")
	ShellLog.info("browser opened")


func _finish() -> void:
	_finish_deferred.call_deferred()


func _finish_deferred() -> void:
	_visible = false
	if is_instance_valid(_screen):
		_screen.suspend_surface()
	closed.emit()
