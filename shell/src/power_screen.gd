extends Control

## Power actions, including display-only rest for controller wake.
##
## Each row acts IMMEDIATELY on A, which is what every console's power menu
## does -- the deliberate act is opening this screen and moving to the row; a
## second "are you sure" would be protecting someone from a menu they pressed
## two buttons to reach. The costliest mistake here is a restart, and this
## machine boots in well under a minute.
##
## Rest switches off the display while the PC and Bluetooth keep running.

signal closed()
signal rest_requested()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")

var _rows: Array = []
var _rest_row: ActionRow = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(TvTheme.BACKGROUND, 0.45)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var panel := preload("res://src/edge_panel.gd").new()
	add_child(panel)
	var safe := MarginContainer.new()
	for edge in ["left", "right"]:
		safe.add_theme_constant_override("margin_" + edge, 32)
	for edge in ["top", "bottom"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_Y)
	panel.add_child(safe)

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
	_add(list, "Rest mode", "", "sleep", _on_rest)
	_rest_row = _rows.back()
	var rest_hint := Label.new()
	rest_hint.text = "Press PS to wake from rest."
	rest_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rest_hint.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	rest_hint.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	column.add_child(rest_hint)

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


func _on_rest() -> void:
	rest_requested.emit()


func show_rest_error() -> void:
	_rest_row.set_value("Display could not turn off")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
