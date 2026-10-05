extends Control

## The Updates page: what is running, whether anything newer exists, and the
## two presses that change that.
##
## THE ROWS ARE A SEQUENCE, NOT A MENU. Check tells you whether there is
## anything; Install stages it; Restart boots into it. Each becomes meaningful
## only once the one before it has happened, so rather than grey rows out and
## leave someone guessing, each row's VALUE says what it is waiting for. A row
## that cannot act yet still explains itself.
##
## Built as a child of the settings screen, like the Wi-Fi page, so the home
## rail keeps seeing exactly one surface come and go.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const SettingsRow = preload("res://src/settings_row.gd")
const ActionRow = preload("res://src/action_row.gd")

## How each state reads on a television. "unknown" doubles as the fallback so a
## word from a newer service renders as something rather than nothing.
const STATE_TEXT := {
	"idle": "",
	"checking": "Checking the registry",
	"available": "An update is available",
	"up-to-date": "This is the newest build published",
	"applying": "Downloading and staging the update",
	"staged": "Update staged -- restart to finish",
	"restarting": "Restarting",
	"failed": "Update failed",
	"unknown": "Starting up",
}

var _status: Label = null
var _explain: Label = null
var _current_row: SettingsRow = null
var _check_row: ActionRow = null
var _apply_row: ActionRow = null
var _restart_row: ActionRow = null
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
	heading.text = "Updates"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_status)

	# The long-form note. Present for the state that confuses people most:
	# "up to date" on this machine can mean "nobody has pushed a build", which
	# is a different situation from "you have the newest work".
	_explain = Label.new()
	_explain.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_explain.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explain.visible = false
	_explain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_explain)

	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	column.add_child(list)

	_current_row = SettingsRow.new()
	_current_row.setup("Running now", Updates.detail if Updates.state == "idle" else "")
	list.add_child(_current_row)
	_rows.append(_current_row)

	_check_row = _add_action(list, "Check for updates", "")
	_check_row.activated.connect(_on_check)

	_apply_row = _add_action(list, "Install update", "")
	_apply_row.activated.connect(_on_apply)

	_restart_row = _add_action(list, "Restart", "")
	_restart_row.activated.connect(_on_restart)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	column.add_child(_build_hints())

	_wire_focus_neighbours()
	if not _rows.is_empty():
		# Opens on Check, not on the read-only "Running now" row: it is the
		# only thing anyone came here to press first.
		_check_row.grab_focus()

	Updates.state_changed.connect(_on_state_changed)
	_on_state_changed(Updates.state, Updates.detail)

	ShellLog.info("update screen up: state %s" % Updates.state)


func _add_action(list: Control, name_text: String, value_text: String) -> ActionRow:
	var row := ActionRow.new()
	row.setup(name_text, value_text)
	list.add_child(row)
	_rows.append(row)
	return row


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


## The shared one-axis table -- see TvTheme.wire_column.
func _wire_focus_neighbours() -> void:
	TvTheme.wire_column(_rows)


func _on_state_changed(state: String, detail: String) -> void:
	var text := str(STATE_TEXT.get(state, STATE_TEXT["unknown"]))
	if state == "failed" and not detail.is_empty():
		text = "Update failed -- %s" % detail
	_status.text = text
	_status.add_theme_color_override("font_color",
		TvTheme.TEXT_ALERT if state == "failed" else TvTheme.TEXT_SECONDARY)

	# "Running now" tracks the version the service reports while idle or
	# up-to-date; during a check or an install the detail means something else,
	# so the row keeps the last version it was told rather than showing it.
	if (state == "idle" or state == "up-to-date") and not detail.is_empty():
		_current_row.set_value(detail)

	_explain.visible = state == "up-to-date"
	if state == "up-to-date":
		_explain.text = ("Nothing newer is published. On this machine an update is a"
			+ " pre-built image pulled from the registry -- if you have committed"
			+ " changes but not built and pushed them, there is nothing here to find"
			+ " yet.")

	# Each row says what it is waiting for rather than going quietly inert.
	match state:
		"checking":
			_check_row.set_value("Checking")
			_apply_row.set_value("")
			_restart_row.set_value("")
		"available":
			_check_row.set_value("")
			_apply_row.set_value("Ready -- press A")
			_restart_row.set_value("After installing")
		"applying":
			_check_row.set_value("")
			_apply_row.set_value("Downloading")
			_restart_row.set_value("After installing")
		"staged":
			_check_row.set_value("")
			_apply_row.set_value("Installed")
			_restart_row.set_value("Ready -- press A")
		"restarting":
			_restart_row.set_value("Restarting")
		"up-to-date":
			_check_row.set_value("")
			_apply_row.set_value("Nothing to install")
			_restart_row.set_value("")
		_:
			_apply_row.set_value("Check first")
			_restart_row.set_value("")


func _on_check() -> void:
	if Updates.is_busy():
		return
	Updates.request_check()


func _on_apply() -> void:
	if Updates.is_busy():
		return
	if Updates.state != "available":
		ShellLog.info("update: nothing staged to install; checking instead")
		Updates.request_check()
		return
	Updates.request_apply()


func _on_restart() -> void:
	if Updates.state != "staged":
		ShellLog.info("update: restart pressed with nothing staged; ignoring")
		return
	Updates.request_restart()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
