extends Control

signal closed()
const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")
var _status: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _rows: Array = []
var _list_signature := ""
var _saved_focus: Control
## Set before _ready when Files opens this screen for one concrete installer.
## General setup uses the exact path chosen in Files, without a recipe gate.
var source_path := ""
var source_name := ""


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
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)
	var heading := Label.new()
	heading.text = "Install %s" % source_name if not source_name.is_empty() else "Install Windows apps"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	column.add_child(heading)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	_scroll.add_child(_list)
	var note := Label.new()
	note.text = "Controller setup keeps the installer's choices. Original setup uses the controller pointer."
	note.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)
	WindowsInstall.changed.connect(_refresh)
	WindowsInstall.guided_backgrounded.connect(_on_guided_backgrounded)
	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)
	Launcher.minimized.connect(_on_launch_finished)
	_refresh()


func _refresh() -> void:
	var state: Dictionary = WindowsInstall.snapshot
	var recipes: Array = state.get("recipes", [])
	var candidates: Array = state.get("candidates", [])
	var library: Array = WindowsInstall.library()
	var jobs: Array = WindowsInstall.local_jobs
	var selected_job: Dictionary = {}
	for job in jobs:
		if str(job.get("source", "")) == source_path and not source_path.is_empty() and float(job.get("created_at", 0)) >= float(selected_job.get("created_at", 0)):
			selected_job = job
	var active := WindowsInstall.available and WindowsInstall.ACTIVE.has(str(state.get("status", "")))
	_status.text = "Choose a Windows installer in Files, or select one below."
	if not source_path.is_empty():
		_status.text = "Run the setup wizard, then choose the installed program for your library."
		if not selected_job.is_empty():
			_status.text = str(selected_job.get("detail", ""))
			if str(selected_job.get("status", "")) in ["preparing", "installing"] and not Launcher.is_busy():
				_status.text = "Setup was interrupted. Run the installer again."
	elif active or str(state.get("status", "")) in ["failed", "done", "cancelled"]:
		_status.text = str(state.get("detail", ""))
		if str(state.get("status", "")) == "downloading":
			_status.text += " — %d%%" % int(state.get("progress", 0))
	if not WindowsInstall.message.is_empty():
		_status.text = WindowsInstall.message
	var signature := JSON.stringify([recipes, candidates, library, jobs, active, source_path])
	if signature == _list_signature:
		return
	_list_signature = signature
	var focused := ""
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and _rows.has(owner):
		focused = str(owner.get_meta("key", ""))
	for row in _rows:
		_list.remove_child(row)
		row.queue_free()
	_rows.clear()
	if source_path.is_empty():
		for recipe in recipes:
			var key := str(recipe.get("id", ""))
			var installed: Dictionary = {}
			for entry in library:
				if str(entry.get("recipe_id", "")) == key:
					installed = entry
			if installed.is_empty():
				_add_row("download." + key, "Install %s" % str(recipe.get("title", "")),
					"Automatic download and setup", WindowsInstall.install.bind(key))
			else:
				_add_row("download." + key, "Open %s" % str(recipe.get("title", "")), "Installed", _launch.bind(installed))
		for job in jobs:
			if str(job.get("status", "")) != "done":
				_add_choices(job)
				if str(job.get("status", "")) not in ["preparing", "installing"]:
					_add_row("discard." + str(job.get("id", "")), "Remove setup files",
						str(job.get("source", "")).get_file(), WindowsInstall.confirm_discard.bind(job))
		for entry in library:
			_add_row("remove." + str(entry.get("id", "")), "Remove " + str(entry.get("title", "")),
				"Windows app", WindowsInstall.confirm_remove.bind(entry))
		for source in candidates:
			_add_source_row(source)
	else:
		_add_choices(selected_job)
		if str(selected_job.get("status", "")) == "done":
			for entry in library:
				if str(entry.get("recipe_id", "")) == str(selected_job.get("id", "")):
					_add_row("open", "Open " + str(entry.get("title", "")), "Installed", _launch.bind(entry))
		var source_id := "local-source"
		for source in candidates:
			if str(source.get("path", "")) == source_path:
				source_id = str(source.get("id", source_id))
		_add_row(source_id, "Resume setup" if WindowsInstall.guided_source == source_path else "Run Windows setup", source_name,
			WindowsInstall.guided_install.bind(source_path))
		_add_row("original", "Original Windows setup", "Use the controller pointer for unsupported setup pages.",
			WindowsInstall.local_install.bind(source_path))
		if source_path.get_extension().to_lower() == "exe":
			_add_row("portable", "Add as portable app",
				"For apps that run without setup. Keep this file and its folder in place.",
				WindowsInstall.local_install.bind(source_path, true))
	if active:
		_add_row("cancel", "Cancel automatic installation", "Stops the background installation", WindowsInstall.cancel)
	_add_row("back", "Back to Files" if not source_path.is_empty() else "Back to library", "", _back)
	TvTheme.wire_column(_rows)
	if not is_visible_in_tree() or Launcher.is_busy() or (is_instance_valid(WindowsInstall._guided_screen) and WindowsInstall._guided_screen.visible):
		return
	var target: Control = _rows[0]
	for row in _rows:
		if str(row.get_meta("key", "")) == focused:
			target = row
	target.grab_focus()


func _add_choices(job: Dictionary) -> void:
	if str(job.get("status", "")) not in ["select", "failed"]:
		return
	for choice in job.get("choices", []):
		var key := str(job.get("id", ""))
		var choice_id := str(choice.get("id", ""))
		_add_row(key + "." + choice_id, "Add " + str(choice.get("title", "")) + " to library",
			str(choice.get("detail", "")), WindowsInstall.register_local.bind(key, choice_id))


func _add_source_row(source: Dictionary) -> void:
	_add_row(str(source.get("id", "")), str(source.get("name", "")),
		str(source.get("location", "")) + " — Run Windows setup",
		WindowsInstall.guided_install.bind(str(source.get("path", ""))))


func _add_row(key: String, title: String, detail: String, action: Callable) -> void:
	var row := ActionRow.new()
	row.setup(title, detail)
	row.set_meta("key", key)
	row.activated.connect(action)
	_list.add_child(row)
	_rows.append(row)
	row.focus_entered.connect(func(): _scroll.ensure_control_visible.call_deferred(row))


func _launch(entry: Dictionary) -> void:
	Launcher.launch(entry)


func _on_guided_backgrounded() -> void:
	if is_visible_in_tree() and not _rows.is_empty() and not Launcher.is_busy():
		_rows[0].grab_focus()


func _on_launch_started(_entry: Dictionary) -> void:
	_saved_focus = get_viewport().gui_get_focus_owner()
	hide()
	if not source_path.is_empty():
		get_parent().hide()
	set_process_unhandled_input(false)


func _on_launch_finished(_entry: Dictionary) -> void:
	if not source_path.is_empty():
		get_parent().show()
	show()
	set_process_unhandled_input(true)
	_refresh()
	if is_instance_valid(_saved_focus):
		_saved_focus.grab_focus()
	elif not _rows.is_empty():
		_rows[0].grab_focus()


func _back() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(WindowsInstall._guided_screen) and WindowsInstall._guided_screen.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
