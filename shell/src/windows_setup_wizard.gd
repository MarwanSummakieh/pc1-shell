extends Control

## A live view of the installer, not a replacement installation recipe.
const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")
const Keyboard = preload("res://src/keyboard.gd")
const ListMenu = preload("res://src/list_menu.gd")
var job_key := ""
var source_name := ""
var _heading: Label
var _status: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _rows: Array = []
var _images: Dictionary = {}
var _page: Dictionary = {}
var _signature := ""
var _modal: Control
var _saved_focus: Control
var _list_edit: Dictionary = {}
var _pending_until := 0
var _read_scroll: ScrollContainer
var _footer: HBoxContainer
var _body_rows: Array = []
var _footer_rows: Array = []
var _step: Label
var _location: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_X)
	for edge in ["top", "bottom"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_Y)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	safe.add_child(column)
	_heading = Label.new()
	_heading.text = "Install " + source_name
	_heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_heading)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	column.add_child(panel)
	var inset := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + edge, 24)
	panel.add_child(inset)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	inset.add_child(content)
	_step = Label.new()
	_step.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY + 6)
	_step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_step)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	_scroll.add_child(_list)
	_location = Label.new()
	_location.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_location)
	column.add_child(HSeparator.new())
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 16)
	column.add_child(_footer)
	var hints := Label.new()
	hints.text = "D-pad: select    A: choose    B: previous step    Home: setup options"
	hints.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	column.add_child(hints)
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(_refresh)
	timer.autostart = true
	add_child(timer)
	_refresh()


func _directory() -> String:
	return WindowsInstall.home.path_join("setup-ui").path_join(job_key)


func _refresh() -> void:
	if not visible:
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(_directory().path_join("page.json"))) if FileAccess.file_exists(_directory().path_join("page.json")) else null
	if value is Dictionary:
		_page = value
	var signature := JSON.stringify(_page)
	if _page.is_empty():
		_status.text = "Preparing Windows setup. First-time setup may take several minutes."
	else:
		_status.text = str(_page.get("error", ""))
		if _page.get("finished", false):
			_status.text = "Finishing setup…"
	if not _list_edit.is_empty():
		_status.text = "D-pad: choose an option    A: toggle    B: done"
	_status.visible = not _status.text.is_empty()
	if signature != _signature and _modal == null:
		_signature = signature
		_build_page()
	for identifier in _images:
		var path := _directory().path_join("widget-%s.bmp" % str(identifier))
		var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if image != null and not image.is_empty():
			_images[identifier].texture = ImageTexture.create_from_image(image)


func _build_page() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	var focused := str(owner.get_meta("key", "")) if owner != null else ""
	if _rows.size() == 1 and str(_rows[0].get_meta("key", "")) == "home":
		focused = ""
	for container in [_list, _footer]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_rows.clear()
	_body_rows.clear()
	_footer_rows.clear()
	_images.clear()
	_heading.text = str(_page.get("title", "Install " + source_name))
	if _heading.text.is_empty():
		_heading.text = "Install " + source_name
	_step.text = ""
	var host_directory := str(_page.get("host_directory", ""))
	_location.text = "Games folder: " + host_directory if not host_directory.is_empty() else ""
	_location.visible = not _location.text.is_empty()
	var unsupported := false
	for control in _page.get("controls", []):
		if control.get("kind") == "unsupported" and control.get("enabled", false):
			unsupported = true
	if unsupported:
		_status.text = "This setup page needs the original interface. Restart with Original Windows setup from Files."
		_status.visible = true
	var last_label := ""
	var navigation: Array = []
	for control in _page.get("controls", []):
		var kind := str(control.get("kind", ""))
		var caption := str(control.get("text", ""))
		if kind in ["button", "check", "radio"]:
			caption = _caption(caption)
		var identifier := str(int(control.get("id", 0)))
		if _is_navigation(control):
			navigation.append(control)
			continue
		match kind:
			"text":
				if caption.length() > 500:
					_add_row(identifier, "Read setup text", "", _read_text.bind(str(control.get("text", ""))))
				elif not caption.is_empty():
					if _step.text.is_empty() and caption.length() < 100:
						_step.text = caption
						last_label = caption
						continue
					var label := Label.new()
					label.text = caption
					label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
					_list.add_child(label)
					last_label = caption
			"progress":
				var progress := ProgressBar.new()
				progress.custom_minimum_size.y = 28
				progress.max_value = maxi(1, int(control.get("range", 100)))
				progress.value = int(control.get("position", 0))
				_list.add_child(progress)
			"button", "check", "radio", "edit", "combo", "list":
				var detail := ""
				if kind in ["check", "radio"]:
					detail = "Selected" if int(control.get("checked", 0)) != 0 else "Not selected"
				elif kind == "edit":
					detail = caption
					caption = "Install location" if control.get("destination", false) else "Edit " + (last_label if last_label.length() < 65 and not last_label.is_empty() else "value")
				elif kind == "combo":
					detail = caption
					caption = "Choose language" if "Language" in _heading.text else "Choose option"
				elif kind == "list":
					caption = "Edit options"
					detail = "D-pad chooses an option; A toggles it."
				var row := _add_row(identifier, caption, detail, _activate.bind(control.duplicate(true)))
				row.disabled = not bool(control.get("enabled", true)) or unsupported
				if kind in ["check", "radio"]:
					var indicator := PanelContainer.new()
					indicator.custom_minimum_size = Vector2(36, 36)
					indicator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
					var box := StyleBoxFlat.new()
					box.bg_color = Color.TRANSPARENT
					box.border_color = TvTheme.TEXT_PRIMARY
					box.set_border_width_all(2)
					box.set_corner_radius_all(18 if kind == "radio" else 4)
					indicator.add_theme_stylebox_override("panel", box)
					var mark := Label.new()
					mark.text = ("●" if kind == "radio" else "✓") if int(control.get("checked", 0)) != 0 else ""
					mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					mark.add_theme_font_size_override("font_size", 28)
					mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
					indicator.add_child(mark)
					var content: HBoxContainer = row._name.get_parent()
					content.add_child(indicator)
					content.move_child(indicator, 0)
					row._value.visible = false
				if kind == "list":
					var picture := TextureRect.new()
					picture.custom_minimum_size = Vector2(0, 320)
					picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					_list.add_child(picture)
					_images[int(control.get("id", 0))] = picture
	_step.visible = not _step.text.is_empty()
	for control in navigation:
		var row := _add_row(str(int(control.get("id", 0))), _caption(str(control.get("text", ""))), "", _activate.bind(control.duplicate(true)), true)
		if control.get("music", false):
			var speaker := TextureRect.new()
			speaker.custom_minimum_size = Vector2(40, 40)
			speaker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			speaker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			speaker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var content: HBoxContainer = row._name.get_parent()
			content.add_child(speaker)
			content.move_child(speaker, 0)
			_images[int(control.get("id", 0))] = speaker
		# Cancel remains available even if a custom choice cannot be adapted.
		row.disabled = not bool(control.get("enabled", true)) or (unsupported and not control.get("music", false) and _navigation_name(str(control.get("text", ""))) not in ["cancel", "back"])
	_add_row("home", "Setup options", "", _options, true)
	_wire_navigation()
	var target: Control
	for row in _rows:
		if not row.disabled and (target == null or str(row.get_meta("key", "")) == focused):
			target = row
	if target != null:
		target.grab_focus()
	if not _list_edit.is_empty():
		var found := false
		for control in _page.get("controls", []):
			if int(control.get("id", 0)) == int(_list_edit.get("id", -1)) and control.get("kind") == "list":
				_list_edit = control
				found = true
		if not found:
			_list_edit.clear()


func _navigation_name(caption: String) -> String:
	return _caption(caption).replace("<", "").replace(">", "").strip_edges().to_lower()


func _is_navigation(control: Dictionary) -> bool:
	if control.get("kind") != "button":
		return false
	if control.get("music", false):
		return true
	if _navigation_name(str(control.get("text", ""))) in ["back", "next", "install", "cancel", "finish", "close"]:
		return true
	var rect: Array = control.get("rect", [])
	return rect.size() == 4 and int(_page.get("height", 0)) > 0 and int(rect[1]) >= int(_page["height"]) - 90


func _wire_navigation() -> void:
	var body: Array = _body_rows.filter(func(row): return not row.disabled)
	var footer: Array = _footer_rows.filter(func(row): return not row.disabled)
	TvTheme.wire_column(body + footer)
	for index in footer.size():
		var row: Control = footer[index]
		row.focus_neighbor_left = row.get_path_to(footer[maxi(0, index - 1)])
		row.focus_neighbor_right = row.get_path_to(footer[mini(footer.size() - 1, index + 1)])
		if not body.is_empty():
			row.focus_neighbor_top = row.get_path_to(body[-1])
			row.focus_neighbor_bottom = row.get_path_to(body[0])
	if not body.is_empty() and not footer.is_empty():
		body[-1].focus_neighbor_bottom = body[-1].get_path_to(footer[0])
		body[0].focus_neighbor_top = body[0].get_path_to(footer[0])


func _add_row(key: String, caption: String, detail: String, action: Callable, footer: bool = false) -> Control:
	var row := ActionRow.new()
	row.setup(caption, detail)
	row.set_meta("key", key)
	row.activated.connect(action)
	if footer:
		_footer.add_child(row)
		_footer_rows.append(row)
	else:
		_list.add_child(row)
		_body_rows.append(row)
	row._name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row._name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if footer:
		row._value.visible = false
	_rows.append(row)
	return row


func _caption(text: String) -> String:
	return text.replace("&&", "\u0001").replace("&", "").replace("\u0001", "&")


func _send(control: Dictionary, verb: int = 1, text: String = "", revision: int = -1) -> void:
	if Time.get_ticks_msec() < _pending_until or FileAccess.file_exists(_directory().path_join("action.bin")):
		return
	var path := _directory().path_join("action.bin")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		_status.text = "Could not send the setup choice. Try again."
		return
	file.store_32(int(_page.get("page", 0)) if revision < 0 else revision)
	file.store_64(int(control.get("id", 0)))
	file.store_32(verb)
	var bytes := text.to_utf8_buffer()
	file.store_32(bytes.size())
	file.store_buffer(bytes)
	file.close()
	FileAccess.set_unix_permissions(path + ".tmp", 384)
	if DirAccess.rename_absolute(path + ".tmp", path) == OK:
		_pending_until = Time.get_ticks_msec() + 350


func _activate(control: Dictionary) -> void:
	match str(control.get("kind", "")):
		"edit":
			_saved_focus = get_viewport().gui_get_focus_owner()
			var revision := int(_page.get("page", 0))
			var keyboard := Keyboard.new()
			keyboard.title_text = "Install location" if control.get("destination", false) else "Edit setup value"
			keyboard.masked = false
			keyboard.initial_text = str(control.get("text", ""))
			keyboard.submitted.connect(func(text: String): _send(control, 2, text, revision); _close_modal())
			keyboard.cancelled.connect(_close_modal)
			_modal = keyboard
			add_child(keyboard)
		"combo":
			_saved_focus = get_viewport().gui_get_focus_owner()
			var revision := int(_page.get("page", 0))
			var menu := ListMenu.new()
			menu.title_text = "Choose option"
			var options: Array = control.get("options", [])
			for index in options.size():
				menu.items.append({"id": str(index), "label": str(options[index]), "icon": ""})
			menu.chosen.connect(func(id: String): _send(control, 3, id, revision); _close_modal())
			menu.closed.connect(_close_modal)
			_modal = menu
			add_child(menu)
		"list":
			_list_edit = control
			_refresh()
		_:
			_send(control)


func _read_text(text: String) -> void:
	_saved_focus = get_viewport().gui_get_focus_owner()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	_read_scroll = ScrollContainer.new()
	_read_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_read_scroll)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_read_scroll.add_child(label)
	_modal = panel
	add_child(panel)


func _options() -> void:
	if _modal != null:
		return
	_saved_focus = get_viewport().gui_get_focus_owner()
	var menu := ListMenu.new()
	menu.title_text = "Setup options"
	menu.items = [{"id": "resume", "label": "Resume setup", "icon": ""}, {"id": "files", "label": "Return to Files", "icon": ""}, {"id": "stop", "label": "Stop setup", "icon": ""}]
	menu.chosen.connect(func(id: String):
		_close_modal()
		if id == "files":
			WindowsInstall.background_guided()
		elif id == "stop":
			WindowsInstall.stop_guided()
	)
	menu.closed.connect(_close_modal)
	_modal = menu
	add_child(menu)


func _close_modal() -> void:
	if _modal != null:
		remove_child(_modal)
		_modal.queue_free()
	_modal = null
	_read_scroll = null
	if is_instance_valid(_saved_focus):
		_saved_focus.grab_focus()
	_signature = ""


func restore_focus() -> void:
	_refresh()
	if not _rows.is_empty():
		_rows[0].grab_focus()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _read_scroll != null:
		if event.is_action_pressed("ui_cancel"):
			_close_modal()
		elif event.is_action_pressed("ui_down"):
			_read_scroll.scroll_vertical += 100
		elif event.is_action_pressed("ui_up"):
			_read_scroll.scroll_vertical -= 100
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if _modal != null:
		return
	if not _list_edit.is_empty():
		if event.is_action_pressed("ui_cancel"):
			_list_edit.clear()
		elif event.is_action_pressed("ui_up"):
			_send(_list_edit, 4, "up")
		elif event.is_action_pressed("ui_down"):
			_send(_list_edit, 4, "down")
		elif event.is_action_pressed("ui_accept"):
			_send(_list_edit, 4, "space")
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_shell_home"):
		get_viewport().set_input_as_handled()
		_options()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		for control in _page.get("controls", []):
			if _navigation_name(str(control.get("text", ""))) == "back" and control.get("kind") == "button" and control.get("enabled", false):
				_send(control)
				return
		_options()
