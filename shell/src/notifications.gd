extends Node

signal received(entry: Dictionary)

var entries: Array = []
var _last_id := 0

func _ready() -> void:
	_poll(false)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_poll.bind(true))
	add_child(timer)

func _poll(announce: bool) -> void:
	var base := OS.get_environment("XDG_STATE_HOME")
	if base.is_empty():
		base = OS.get_environment("HOME").path_join(".local/state")
	var file := FileAccess.open(base.path_join("marwanos/notifications.json"), FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("entries") is Array:
		return
	entries = data["entries"]
	for value in entries:
		if not value is Dictionary:
			continue
		var ident := int(value.get("id", 0))
		if announce and ident > _last_id and not value.get("closed", false):
			received.emit(value)
		_last_id = maxi(_last_id, ident)
