extends "res://src/rest_screen.gd"

var commands: Array = []
var query := "Standby: 120    Suspend: 240    Off: 600\n  DPMS is Disabled"
var fail_off := false

func _display_supported() -> bool:
	return true

func _xset(arguments: Array) -> Dictionary:
	commands.append(arguments.duplicate())
	return {"code": 1 if fail_off and arguments == ["dpms", "force", "off"] else 0, "output": query}
