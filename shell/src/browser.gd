extends Node

signal opened()
signal closed()

const BrowserScreen = preload("res://src/browser_screen.gd")
var _screen: Control = null
var _visible := false


func is_open() -> bool:
	return _visible and is_instance_valid(_screen)

func reset_for_user() -> void:
	if is_instance_valid(_screen):
		_screen.get_parent().remove_child(_screen)
		_screen.queue_free()
	_screen = null
	_visible = false


func open() -> void:
	if is_open() or Launcher.is_busy() or Files.is_open() or Settings.is_open() \
			or Power.is_open() or Info.is_open() or WindowsInstall.is_open() or Downloads.is_open():
		return
	_visible = true
	if is_instance_valid(_screen):
		opened.emit()
		_screen.resume_surface()
		return
	_screen = BrowserScreen.new()
	var scene := get_tree().current_scene
	if scene != null and scene.get_script() != null and scene.get_script().resource_path == "res://src/shell_root.gd":
		var hero: Variant = scene.get("_hero_art")
		if hero is TextureRect: _screen.backdrop = hero.texture
	_screen.return_label = "Return to library"
	_screen.closed.connect(_finish)
	opened.emit()
	get_tree().root.add_child(_screen)
	ShellLog.info("browser opened")


func _finish() -> void:
	_finish_deferred.call_deferred()


func _finish_deferred() -> void:
	_visible = false
	if is_instance_valid(_screen):
		_screen.suspend_surface()
	closed.emit()
