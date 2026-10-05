extends Control

## The power menu: three rows, three verbs, nothing else to learn.
##
## Each row acts IMMEDIATELY on A, which is what every console's power menu
## does -- the deliberate act is opening this screen and moving to the row; a
## second "are you sure" would be protecting someone from a menu they pressed
## two buttons to reach. The costliest mistake here is a restart, and this
## machine boots in well under a minute.
##
## Sleep is offered with Phase 0's caveat carried in the row itself: whether
## resume survives the NVIDIA driver and gamescope is a bench question, and
## until a boot answers it the row says "untested" rather than implying a
## promise nobody has kept yet.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")

var _rows: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	add_child(safe)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)

	var heading := Label.new()
	heading.text = "Power"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	column.add_child(list)

	_add(list, "Turn off", "", "power", _on_poweroff)
	_add(list, "Restart", "", "restart", _on_restart)
	_add(list, "Sleep", "Untested on this hardware", "sleep", _on_suspend)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)

	_wire_focus_neighbours()
	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("power menu up with %d rows" % _rows.size())


func _add(list: Control, name_text: String, value_text: String,
		icon_name: String, handler: Callable) -> void:
	var row := ActionRow.new()
	row.setup(name_text, value_text, icon_name)
	row.activated.connect(handler)
	list.add_child(row)
	_rows.append(row)


## The shared one-axis table -- see TvTheme.wire_column.
func _wire_focus_neighbours() -> void:
	TvTheme.wire_column(_rows)


func _on_poweroff() -> void:
	ShellLog.info("power menu: turn off")
	Updates.request_poweroff()
	# The screen stays up; the machine going dark is the acknowledgement, and
	# closing first would flash the rail for the two seconds the service
	# defers by.


func _on_restart() -> void:
	ShellLog.info("power menu: restart")
	Updates.request_restart()


func _on_suspend() -> void:
	ShellLog.info("power menu: sleep")
	Updates.request_suspend()
	# Sleep, unlike the other two, comes BACK -- and it should come back to
	# the rail, not to a stale power menu.
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
