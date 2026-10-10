extends Control

signal closed()
const TvTheme = preload("res://src/tv_theme.gd")
const ConsoleButton = preload("res://src/console_button.gd")
const Keyboard = preload("res://src/keyboard.gd")
var startup := false
var _column: VBoxContainer
var _choices: GridContainer
var _message: Label
var _keyboard: Keyboard
var _buttons: Array = []
var _editing := false
var _edit_current := false
var _name := ""
var _color: String = "#6e9eae"
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		safe.add_theme_constant_override("margin_" + side, TvTheme.SAFE_MARGIN_X)
	for side in ["top", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, TvTheme.SAFE_MARGIN_Y)
	add_child(safe)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 24)
	safe.add_child(_column)
	resized.connect(_fit)
	_show_picker()

func _clear() -> void:
	_buttons = []
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	_choices = null

func _label(text: String, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 44 if heading else 26)
	label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY if heading else TvTheme.TEXT_SECONDARY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(label)
	return label

func _show_picker() -> void:
	_editing = false
	_clear()
	var heading := _label("Who's playing?" if startup else "Switch user", true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_choices = GridContainer.new()
	_choices.add_theme_constant_override("h_separation", 24)
	_choices.add_theme_constant_override("v_separation", 24)
	center.add_child(_choices)
	for user in Profiles.users:
		var button := ConsoleButton.new()
		button.text = ""
		button.accessibility_name = str(user.name)
		button.custom_minimum_size = Vector2(220, 248)
		button.pressed.connect(_select.bind(str(user.id)))
		_choices.add_child(button)
		button.add_theme_font_size_override("font_size", 28)
		var box := TvTheme.card_idle_box()
		box.bg_color = TvTheme.SURFACE
		button.add_theme_stylebox_override("normal", box)
		var avatar_disc := Panel.new()
		var disc := StyleBoxFlat.new()
		disc.bg_color = Color(str(user.get("color", Profiles.COLORS[0]))).darkened(0.5)
		disc.set_corner_radius_all(64)
		disc.corner_detail = 16
		avatar_disc.add_theme_stylebox_override("panel", disc)
		avatar_disc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		avatar_disc.offset_left = -56
		avatar_disc.offset_right = 56
		avatar_disc.offset_top = 24
		avatar_disc.offset_bottom = 136
		avatar_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(avatar_disc)
		var avatar := Label.new()
		avatar.text = str(user.name).left(1).to_upper()
		avatar.add_theme_font_size_override("font_size", 54)
		avatar.add_theme_color_override("font_color", Color(str(user.get("color", Profiles.COLORS[0]))).lightened(0.35))
		avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar_disc.add_child(avatar)
		var caption := Label.new()
		caption.text = str(user.name) + ("\nCurrent user" if user.id == Profiles.active else "")
		caption.add_theme_font_size_override("font_size", 26)
		caption.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		caption.offset_top = -92
		caption.offset_bottom = -12
		caption.offset_left = 16
		caption.offset_right = -16
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(caption)
		_buttons.append(button)
	if Profiles.users.size() < Profiles.MAX_USERS:
		var add := _button("+ Add user", func(): _show_form(false), _choices)
		add.custom_minimum_size = Vector2(220, 248)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_child(actions)
	var edit := _button("", func(): _show_form(true), actions)
	edit.custom_minimum_size = Vector2(340, 64)
	edit.accessibility_name = "Edit current user"
	var edit_label := Label.new()
	edit_label.text = "Edit current user"
	edit_label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	edit_label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	edit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	edit_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edit.add_child(edit_label)
	_message = _label(Profiles.error)
	_message.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	_hints()
	_fit()
	_wire_grid()
	_focus_current.call_deferred()

func _show_form(edit: bool) -> void:
	_editing = true
	_edit_current = edit
	_name = str(Profiles.current().name) if edit else ""
	_color = str(Profiles.current().get("color", Profiles.COLORS[0])) if edit else Profiles.COLORS[Profiles.users.size() % Profiles.COLORS.size()]
	_render_form()

func _render_form() -> void:
	_clear()
	_label("Edit user" if _edit_current else "Add user", true)
	_button("Name: " + (_name if not _name.is_empty() else "Enter name"), _enter_name)
	_label("Avatar color")
	var palette := HBoxContainer.new()
	palette.add_theme_constant_override("separation", 24)
	_column.add_child(palette)
	for index in Profiles.COLORS.size():
		var color: String = Profiles.COLORS[index]
		var button := _button("✓" if color == _color else "", _choose_color.bind(color), palette)
		button.accessibility_name = "Avatar color %d%s" % [index + 1, ", selected" if color == _color else ""]
		button.custom_minimum_size = Vector2(72, 72)
		var box := TvTheme.card_idle_box()
		box.bg_color = Color(color).darkened(0.35)
		button.add_theme_stylebox_override("normal", box)
	var create := _button("Save user" if _edit_current else "Add user", _save_user)
	create.disabled = _name.strip_edges().is_empty()
	_button("Cancel", _show_picker)
	if not _edit_current:
		_label("Games that save in their installation folder or ProgramData still share those saves.")
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(spacer)
	_message = _label("")
	_message.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	_hints()
	TvTheme.wire_column(_buttons)
	for index in Profiles.COLORS.size():
		var button: Control = _buttons[index + 1]
		button.focus_neighbor_left = button.get_path_to(_buttons[index] if index > 0 else button)
		button.focus_neighbor_right = button.get_path_to(_buttons[index + 2] if index + 1 < Profiles.COLORS.size() else button)
		button.focus_neighbor_top = button.get_path_to(_buttons[0])
		button.focus_neighbor_bottom = button.get_path_to(_buttons[Profiles.COLORS.size() + 1])
	_buttons[0].grab_focus.call_deferred()

func _choose_color(color: String) -> void:
	_color = color
	_render_form()
	_buttons[Profiles.COLORS.find(color) + 1].grab_focus.call_deferred()

func _button(text: String, handler: Callable, parent: Control = null) -> Button:
	var button := ConsoleButton.new()
	button.text = text
	button.pressed.connect(handler)
	(parent if parent != null else _column).add_child(button)
	_buttons.append(button)
	return button

func _hints() -> void:
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	if not startup or _editing:
		hints.add_child(TvTheme.hint("B", "Back"))
	_column.add_child(hints)

func _fit() -> void:
	if is_instance_valid(_choices):
		_choices.columns = maxi(1, mini(4, int(maxf(1, size.x - 192 + 24) / 244)))
		_wire_grid()

func _wire_grid() -> void:
	if not is_instance_valid(_choices) or _buttons.is_empty():
		return
	var count := _choices.get_child_count()
	for index in count:
		var button: Control = _buttons[index]
		button.focus_neighbor_left = button.get_path_to(_buttons[index - 1] if index % _choices.columns > 0 else button)
		button.focus_neighbor_right = button.get_path_to(_buttons[index + 1] if index + 1 < count and (index + 1) % _choices.columns > 0 else button)
		button.focus_neighbor_top = button.get_path_to(_buttons[index - _choices.columns] if index >= _choices.columns else button)
		button.focus_neighbor_bottom = button.get_path_to(_buttons[index + _choices.columns] if index + _choices.columns < count else _buttons[count])
	_buttons[count].focus_neighbor_top = _buttons[count].get_path_to(_buttons[0])
	_buttons[count].focus_neighbor_bottom = _buttons[count].get_path()

func _focus_current() -> void:
	var index := 0
	for user in Profiles.users:
		if user.id == Profiles.active:
			_buttons[index].grab_focus()
			return
		index += 1
	if not _buttons.is_empty():
		_buttons[0].grab_focus()

func _enter_name() -> void:
	if _keyboard != null:
		return
	_keyboard = Keyboard.new()
	_keyboard.title_text = "User name"
	_keyboard.initial_text = _name
	_keyboard.masked = false
	_keyboard.submitted.connect(func(value: String):
		_name = value.strip_edges().left(24)
		_close_keyboard()
		_render_form())
	_keyboard.cancelled.connect(func():
		_close_keyboard()
		_buttons[0].grab_focus())
	add_child(_keyboard)

func _close_keyboard() -> void:
	var keyboard := _keyboard
	_keyboard = null
	remove_child(keyboard)
	keyboard.queue_free()

func _save_user() -> void:
	if _edit_current:
		if Profiles.edit_user(_name, _color):
			_show_picker()
		else:
			_message.text = Profiles.error
		return
	var key := Profiles.add_user(_name, _color)
	if key.is_empty():
		_message.text = Profiles.error
		return
	var selected: bool = await _select(key)
	if not selected and is_inside_tree():
		_show_picker()

func _select(key: String) -> bool:
	if _busy:
		return false
	_busy = true
	_message.text = "Switching user…"
	for button in _buttons:
		button.disabled = true
	var selected: bool = await Profiles.select_user(key)
	_busy = false
	if selected:
		closed.emit.call_deferred()
	else:
		_message.text = Profiles.error
		for button in _buttons:
			button.disabled = false
		_focus_current()
	return selected

func _unhandled_input(event: InputEvent) -> void:
	if _busy or _keyboard != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _editing:
			_show_picker()
		elif not startup:
			closed.emit.call_deferred()
