extends Control

## Shared controller keyboard. Draft inputs stay local until Done; browser inputs
## emit edits immediately into the focused field beneath this floating panel.
signal submitted(text: String)
signal cancelled()
signal text_inserted(text: String)
signal editing_key(key: String)
signal panel_moved(rect: Rect2)
signal window_move_requested(amount: Vector2)

const TvTheme = preload("res://src/tv_theme.gd")
const PANEL_WIDTH := 568
const PANEL_GAP := 24
const KEY_SIZE := 48
const KEY_GAP := 4
const POSITION_FILE := "user://controller_keyboard.cfg"
const MOVE_SPEED := 560.0
const MOVE_DEADZONE := 0.24

const ROWS_LOWER := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "-"],
	["z", "x", "c", "v", "b", "n", "m", ".", "_", "@"],
]

const ROWS_UPPER := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
	["A", "S", "D", "F", "G", "H", "J", "K", "L", "-"],
	["Z", "X", "C", "V", "B", "N", "M", ".", "_", "@"],
]

const ROWS_SYMBOLS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"],
	["-", "_", "+", "=", "[", "]", "{", "}", ":", ";"],
	["/", "\\", "|", "~", "`", "<", ">", "\"", "'", "?"],
]


var title_text := "Enter password"
var masked := true
var initial_text := ""
var background_alpha := 0.0
var input_context := "text"
var live_input := false
var done_label := "Done"
var floating_window := false
var _text := ""
var _caret := 0
var _shift := false
var _symbols := false
var _keys: Array = []
var _flat: Array = []
var _entry: Label
var _panel: PanelContainer
var _left_trigger := false
var _right_trigger := false
var _move_axis := Vector2.ZERO
var _saved_position := Vector2(0.5, 1.0)
var _dragging := false
var _shift_key: Button
var _symbols_key: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if PlayerOne.device >= 0:
		_left_trigger = PlayerOne.axis(JOY_AXIS_TRIGGER_LEFT) > 0.6
		_right_trigger = PlayerOne.axis(JOY_AXIS_TRIGGER_RIGHT) > 0.6
	PlayerOne.player_one_absent.connect(func(): _move_axis = Vector2.ZERO)
	var background := ColorRect.new()
	background.color = Color(TvTheme.BACKGROUND, minf(background_alpha, 0.15))
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.custom_minimum_size.x = 384 if input_context in ["numeric", "decimal", "tel", "number"] else PANEL_WIDTH
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var surface := TvTheme.card_idle_box()
	surface.bg_color = TvTheme.BACKGROUND
	surface.set_corner_radius_all(8)
	surface.set_border_width_all(1)
	surface.border_color = Color(TvTheme.TEXT_SECONDARY, 0.35)
	surface.shadow_color = Color(0, 0, 0, 0.28)
	surface.shadow_size = 18
	surface.shadow_offset = Vector2(0, 6)
	_panel.add_theme_stylebox_override("panel", surface)
	var pad := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + edge, 16)
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	pad.add_child(column)
	var header := HBoxContainer.new()
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.gui_input.connect(_drag_panel)
	column.add_child(header)
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 22)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title)
	var close := _make_key("×")
	close.custom_minimum_size = Vector2(44, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close keyboard" if live_input else "Cancel"
	close.pressed.connect(func(): cancelled.emit())
	header.add_child(close)
	_entry = Label.new()
	_entry.add_theme_font_size_override("font_size", 24)
	_entry.custom_minimum_size.y = 42
	_entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_entry.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_entry)
	_entry.visible = not live_input
	var entry_box := TvTheme.card_idle_box()
	entry_box.bg_color = TvTheme.SURFACE
	entry_box.content_margin_left = 12
	entry_box.content_margin_right = 12
	_entry.add_theme_stylebox_override("normal", entry_box)
	column.add_child(_build_grid())
	var hints := Label.new()
	hints.text = "□ Delete   △ Space   R Move   ○ " + ("Close" if live_input else "Cancel")
	hints.add_theme_font_size_override("font_size", 16)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	if input_context in ["numeric", "decimal", "tel", "number"]:
		hints.text = "□ Delete   R Move   ○ " + ("Close" if live_input else "Cancel")
	column.add_child(hints)
	_wire_focus_neighbours()
	_text = initial_text
	_caret = _text.length()
	_refresh_entry()
	var first_row := 0 if input_context in ["numeric", "decimal", "tel", "number"] else 1
	if not floating_window:
		_keys[first_row][0].grab_focus()
	var config := ConfigFile.new()
	if config.load(POSITION_FILE) == OK:
		var saved: Variant = config.get_value("panel", "position", _saved_position)
		if saved is Vector2 and saved.is_finite():
			_saved_position = saved
	get_viewport().size_changed.connect(_restore_position)
	_restore_position.call_deferred()
	ShellLog.info("compact keyboard up (%s)" % input_context)

func _build_grid() -> Control:
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", KEY_GAP)
	var rows: Array = _letter_rows()
	if input_context in ["numeric", "decimal", "tel", "number"]:
		rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["+", "0", "."], ["-", "#", "*"]]
	for labels in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", KEY_GAP)
		grid.add_child(row)
		var keys: Array = []
		for label in labels:
			var key := _make_key(str(label))
			row.add_child(key)
			key.pressed.connect(_on_character.bind(key))
			keys.append(key)
			_flat.append(key)
		_keys.append(keys)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", KEY_GAP)
	grid.add_child(actions)
	var action_keys: Array = []
	var action_labels: Array = ["Shift", "?123", "Space", "⌫", done_label]
	if input_context in ["numeric", "decimal", "tel", "number"]:
		action_labels = ["Space", "Delete", done_label]
	for label in action_labels:
		var key := _make_key(label)
		actions.add_child(key)
		action_keys.append(key)
		if label == "Shift":
			_shift_key = key
			key.pressed.connect(_on_shift)
		elif label == "?123":
			_symbols_key = key
			key.pressed.connect(_on_symbols)
		elif label == "Space":
			key.size_flags_stretch_ratio = 3
			key.pressed.connect(_on_space)
		elif label in ["Delete", "⌫"]:
			key.tooltip_text = "Delete"
			key.pressed.connect(_on_backspace)
		else:
			_style_primary(key)
			key.pressed.connect(_on_done)
	_keys.append(action_keys)
	return grid

func _make_key(label: String) -> Button:
	var key := Button.new()
	# Text entry should respond to Cross going down, without waiting for release.
	key.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	key.text = label
	key.custom_minimum_size = Vector2(KEY_SIZE, KEY_SIZE)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.add_theme_font_size_override("font_size", 22)
	key.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	key.add_theme_color_override("font_hover_color", TvTheme.TEXT_ON_PRIMARY)
	key.add_theme_color_override("font_focus_color", TvTheme.TEXT_ON_PRIMARY)
	key.add_theme_color_override("font_pressed_color", TvTheme.TEXT_PRIMARY)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = TvTheme.card_idle_box()
		style.bg_color = TvTheme.SURFACE
		if state in ["hover", "focus"]:
			style.bg_color = TvTheme.PRIMARY
		elif state == "pressed":
			style = TvTheme.row_pressed_box()
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		style.set_corner_radius_all(6)
		key.add_theme_stylebox_override(state, style)
	return key

func _style_primary(key: Button) -> void:
	var style := key.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	style.bg_color = TvTheme.PRIMARY
	key.add_theme_stylebox_override("normal", style)
	key.add_theme_color_override("font_color", TvTheme.TEXT_ON_PRIMARY)

func _wire_focus_neighbours() -> void:
	for row_index in _keys.size():
		var row: Array = _keys[row_index]
		for col_index in row.size():
			var key: Control = row[col_index]

			var left := col_index - 1 if col_index > 0 else col_index
			var right := col_index + 1 if col_index + 1 < row.size() else col_index
			key.focus_neighbor_left = key.get_path_to(row[left])
			key.focus_neighbor_right = key.get_path_to(row[right])

			key.focus_neighbor_top = key.get_path_to(
				_proportional(row_index - 1, col_index, row.size(), key))
			key.focus_neighbor_bottom = key.get_path_to(
				_proportional(row_index + 1, col_index, row.size(), key))


func _proportional(target_row: int, col_index: int, width: int, fallback: Control) -> Control:
	if target_row < 0 or target_row >= _keys.size():
		return fallback
	var row: Array = _keys[target_row]
	if row.is_empty():
		return fallback
	# +0.5 so the mapping picks the column the key's CENTRE sits over rather
	# than the one its left edge does; without it, moving down then up from the
	# action row drifts leftward one column at a time.
	var index := int((float(col_index) + 0.5) / float(width) * float(row.size()))
	index = clampi(index, 0, row.size() - 1)
	return row[index]


func _insert(value: String) -> void:
	if live_input:
		text_inserted.emit(value)
	else:
		_text = _text.insert(_caret, value)
		_caret += value.length()
	_refresh_entry()

func _on_character(key: Button) -> void:
	_insert(key.text)

func _on_space() -> void:
	_insert(" ")

func _on_backspace() -> void:
	if live_input:
		editing_key.emit("BackSpace")
	elif _caret > 0:
		_text = _text.erase(_caret - 1, 1)
		_caret -= 1
	_refresh_entry()

func _move_caret(direction: int) -> void:
	if live_input:
		editing_key.emit("Left" if direction < 0 else "Right")
	else:
		_caret = clampi(_caret + direction, 0, _text.length())
	_refresh_entry()

func _letter_rows() -> Array:
	if _symbols:
		return ROWS_SYMBOLS.duplicate(true)
	var rows: Array = (ROWS_UPPER if _shift else ROWS_LOWER).duplicate(true)
	if input_context == "email":
		rows[3] = ["z", "x", "c", "v", "b", "n", "m", ".", "@", ".com"]
	elif input_context == "url":
		rows[3] = ["z", "x", "c", "v", "b", "n", "m", "/", ":", ".com"]
	if _shift:
		for index in rows[3].size():
			rows[3][index] = str(rows[3][index]).to_upper()
	return rows

func _on_shift() -> void:
	if _flat.size() != 40:
		return
	_shift = not _shift
	_refresh_keys()

func _on_symbols() -> void:
	_symbols = not _symbols
	_refresh_keys()

func _refresh_keys() -> void:
	var rows: Array = _letter_rows()
	for index in _flat.size():
		_flat[index].text = rows[index / 10][index % 10]
	_shift_key.text = "SHIFT" if _shift else "Shift"
	_symbols_key.text = "ABC" if _symbols else "?123"

func _on_done() -> void:
	submitted.emit(_text)

func _refresh_entry() -> void:
	if live_input:
		_entry.text = ""
		return
	var value := "*".repeat(_text.length()) if masked else _text
	var start := maxi(0, _caret - 22)
	_entry.text = ("…" if start > 0 else "") + value.substr(start, _caret - start) + "│" + value.substr(_caret, 22)

## Capture shortcuts before focused buttons consume them. Directional navigation
## and Cross still use Godot's normal focus handling and hold-to-repeat.
func _input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and PlayerOne.device >= 0 and event.device != PlayerOne.device:
		return
	if floating_window:
		# Input.parse_input_event also visits native child windows. Broker input
		# forwarded from the main viewport must navigate this window only once.
		if event.get_meta("marwanos_keyboard_input", false):
			viewport.set_input_as_handled()
			return
		event.set_meta("marwanos_keyboard_input", true)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	if event is InputEventMouseMotion and _dragging:
		move_panel(event.relative)
		viewport.set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_on_done()
			viewport.set_input_as_handled()
			return
		if event.unicode >= 32:
			_insert(String.chr(event.unicode))
			viewport.set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_BACKSPACE, KEY_SHIFT]:
		if event.keycode == KEY_BACKSPACE:
			_on_backspace()
		elif event.keycode == KEY_SHIFT:
			if not event.echo:
				_on_shift()
		else:
			return
		viewport.set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_RIGHT_X or event.axis == JOY_AXIS_RIGHT_Y:
			var value: float = event.axis_value if absf(event.axis_value) > MOVE_DEADZONE else 0.0
			if event.axis == JOY_AXIS_RIGHT_X:
				_move_axis.x = value
			else:
				_move_axis.y = value
			viewport.set_input_as_handled()
			return
		if event.axis == JOY_AXIS_TRIGGER_LEFT:
			if event.axis_value > 0.6 and not _left_trigger:
				_on_shift()
			_left_trigger = event.axis_value > 0.6
		elif event.axis == JOY_AXIS_TRIGGER_RIGHT:
			if event.axis_value > 0.6 and not _right_trigger:
				_on_done()
			_right_trigger = event.axis_value > 0.6
		else:
			return
		viewport.set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
	elif event.is_action_pressed("ui_shell_x"):
		_on_backspace()
	elif event.is_action_pressed("ui_shell_y"):
		_on_space()
	elif event.is_action_pressed("ui_shell_l1"):
		_move_caret(-1)
	elif event.is_action_pressed("ui_shell_r1"):
		_move_caret(1)
	elif event.is_action_pressed("ui_shell_options"):
		_on_done()
	else:
		return
	viewport.set_input_as_handled()


## Browser fields use the actual panel rect as the controller moves it.
func get_panel_rect() -> Rect2:
	return _panel.get_global_rect() if is_instance_valid(_panel) else Rect2()

func _available_position() -> Vector2:
	return (get_viewport_rect().size - _panel.size * _panel.scale - Vector2.ONE * PANEL_GAP * 2).max(Vector2.ZERO)

func _restore_position() -> void:
	if not is_inside_tree() or not is_instance_valid(_panel):
		return
	_panel.size = _panel.get_combined_minimum_size()
	var room := (get_viewport_rect().size - Vector2.ONE * PANEL_GAP * 2).max(Vector2.ONE)
	_panel.scale = Vector2.ONE * minf(1.0, minf(room.x / _panel.size.x, room.y / _panel.size.y))
	_panel.position = Vector2.ONE * PANEL_GAP + _available_position() * _saved_position.clamp(Vector2.ZERO, Vector2.ONE)
	if floating_window:
		_panel.position = Vector2.ONE * PANEL_GAP
	panel_moved.emit(get_panel_rect())

func _drag_panel(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_panel.accept_event()

func move_panel(amount: Vector2) -> void:
	if floating_window:
		window_move_requested.emit(amount)
		return
	var available := _available_position()
	_panel.position = (_panel.position + amount).clamp(Vector2.ONE * PANEL_GAP, available + Vector2.ONE * PANEL_GAP)
	_saved_position = Vector2(
		(_panel.position.x - PANEL_GAP) / available.x if available.x > 0 else 0.0,
		(_panel.position.y - PANEL_GAP) / available.y if available.y > 0 else 0.0)
	panel_moved.emit(get_panel_rect())

func _process(delta: float) -> void:
	if not _move_axis.is_zero_approx():
		move_panel(_move_axis.limit_length() * MOVE_SPEED * delta)

func _exit_tree() -> void:
	var config := ConfigFile.new()
	config.set_value("panel", "position", _saved_position)
	config.save(POSITION_FILE)
