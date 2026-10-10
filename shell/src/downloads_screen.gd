extends Control

signal closed()
const TvTheme = preload("res://src/tv_theme.gd")
const ConsoleButton = preload("res://src/console_button.gd")
const DownloadRow = preload("res://src/download_row.gd")
const ListMenu = preload("res://src/list_menu.gd")
const Keyboard = preload("res://src/keyboard.gd")
var initial_torrent := ""
var _rows: Dictionary = {}
var _list: VBoxContainer
var _status: Label
var _summary: Label
var _empty: Label
var _filter := "all"
var _filters: Array = []
var _actions: Array = []
var _modal: Control
var _return_focus: Control
var _selected: Dictionary = {}
var _install_actions: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_X)
	for edge in ["top", "bottom"]: safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_Y)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	safe.add_child(column)
	var title := Label.new()
	title.text = "Downloads"
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	column.add_child(title)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_summary.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	column.add_child(_summary)
	var toolbar := HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 12)
	toolbar.add_theme_constant_override("v_separation", 12)
	column.add_child(toolbar)
	for item in [["All", "all"], ["Active", "active"], ["Finished", "finished"]]:
		var button := _button(item[0], func(): _change_filter(item[1]))
		button.active = item[1] == _filter
		toolbar.add_child(button)
		_filters.append(button)
	for item in [["Add link", _add_link], ["Add torrent", _pick_torrent]]:
		var button := _button(item[0], item[1])
		toolbar.add_child(button)
		_actions.append(button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_DESTRUCTIVE)
	column.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	_empty = Label.new()
	_empty.text = "No downloads yet. Add a link or torrent."
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_list.add_child(_empty)
	var hints := HFlowContainer.new()
	hints.add_theme_constant_override("h_separation", TvTheme.HINT_GAP)
	for item in [["A", "Actions"], ["X", "Add link"], ["Y", "Add torrent"], ["B", "Back"]]: hints.add_child(TvTheme.hint(item[0], item[1]))
	column.add_child(hints)
	Downloads.changed.connect(_refresh)
	_refresh()
	if _actions[0].disabled: _filters[0].grab_focus()
	else: _actions[0].grab_focus()
	if not initial_torrent.is_empty(): _review.call_deferred(initial_torrent, true)

func _button(caption: String, action: Callable) -> Button:
	var button := ConsoleButton.new()
	button.text = caption
	button.pressed.connect(action)
	return button

func _change_filter(value: String) -> void:
	_filter = value
	for i in _filters.size(): _filters[i].active = ["all", "active", "finished"][i] == value
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_list): return
	_status.text = Downloads.error
	_status.visible = not _status.text.is_empty()
	var available: bool = Downloads.snapshot.get("available", false)
	for button: Button in _actions: button.disabled = not available
	if not available and _modal == null and get_viewport().gui_get_focus_owner() in _actions: _filters[0].grab_focus()
	var entries := Downloads.tasks()
	var active := 0
	var speed := 0
	var visible_ids: Array = []
	var focus := get_viewport().gui_get_focus_owner()
	var focus_id := ""
	for id: String in _rows:
		if _rows[id] == focus: focus_id = id
	for task: Dictionary in entries:
		var finished: bool = task.get("status") in ["complete", "seeding", "error", "cancelled"]
		if task.get("status") in ["active", "waiting", "seeding"]: active += 1
		speed += int(task.get("speed", 0))
		if (_filter == "active" and task.get("status") not in ["active", "waiting", "paused", "seeding"]) or (_filter == "finished" and not finished): continue
		var id := str(task.id)
		visible_ids.append(id)
		if not _rows.has(id):
			var row := DownloadRow.new()
			row.task = task
			row.pressed.connect(func(): _task_actions(row.task))
			_list.add_child(row)
			_rows[id] = row
		_rows[id].update_task(task)
	for id: String in _rows.keys():
		if id not in visible_ids:
			var row: Control = _rows[id]
			_list.remove_child(row)
			row.queue_free()
			_rows.erase(id)
	_summary.text = "%d active · %s/s" % [active, String.humanize_size(speed)] if active > 0 else "%d downloads" % entries.size()
	_empty.text = "No downloads yet. Add a link or torrent." if _filter == "all" else "No %s downloads." % _filter
	_empty.visible = visible_ids.is_empty()
	var controls: Array = _filters + _actions
	for i in controls.size():
		var button: Control = controls[i]
		button.focus_neighbor_left = button.get_path_to(controls[maxi(0, i - 1)])
		button.focus_neighbor_right = button.get_path_to(controls[mini(controls.size() - 1, i + 1)])
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(_rows[visible_ids[0]] if not visible_ids.is_empty() else button)
	var rows: Array = []
	for id: String in visible_ids: rows.append(_rows[id])
	TvTheme.wire_column(rows)
	if not rows.is_empty(): rows[0].focus_neighbor_top = rows[0].get_path_to(_filters[0])
	if _modal == null and not focus_id.is_empty() and not _rows.has(focus_id): _filters[0].grab_focus()

func _show_modal(control: Control) -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	if is_instance_valid(_return_focus): _return_focus.release_focus()
	_modal = control
	add_child(control)
	set_process_unhandled_input(false)

func _close_modal(after: Callable = Callable()) -> void:
	if is_instance_valid(_modal):
		remove_child(_modal)
		_modal.queue_free()
	_modal = null
	set_process_unhandled_input(true)
	if is_instance_valid(_return_focus) and _return_focus.is_inside_tree() and _return_focus.is_visible_in_tree(): _return_focus.grab_focus()
	else: _filters[0].grab_focus()
	if after.is_valid(): after.call_deferred()

func _menu(title: String, items: Array, note: String, chosen: Callable) -> void:
	var menu := ListMenu.new()
	menu.title_text = title
	menu.items = items
	menu.note_text = note
	var pending := {"id": ""}
	menu.chosen.connect(func(id: String): pending.id = id)
	menu.closed.connect(func(): _close_modal.call_deferred(func():
		if not str(pending.id).is_empty(): chosen.call(pending.id)))
	_show_modal(menu)

func _add_link() -> void:
	if _modal != null or not Downloads.snapshot.get("available", false): return
	var keyboard := Keyboard.new()
	keyboard.title_text = "Download link"
	keyboard.masked = false
	keyboard.input_context = "url"
	keyboard.done_label = "Review"
	keyboard.submitted.connect(func(value: String): _close_modal.call_deferred(func(): _review(value.strip_edges(), false)))
	keyboard.cancelled.connect(func(): _close_modal.call_deferred())
	_show_modal(keyboard)

func _pick_torrent() -> void:
	if _modal != null or not Downloads.snapshot.get("available", false): return
	var picker: Control = load("res://src/files_screen.gd").new()
	picker.picker_mode = true
	picker.picker_title = "Choose torrent"
	picker.picker_extensions = PackedStringArray(["torrent"])
	var selected := {"path": ""}
	picker.files_picked.connect(func(paths: PackedStringArray):
		if not paths.is_empty(): selected.path = paths[0])
	picker.closed.connect(func(): _close_modal.call_deferred(func():
		if not str(selected.path).is_empty(): _review(selected.path, true)))
	_show_modal(picker)

func _review(source: String, torrent: bool) -> void:
	if source.is_empty(): return
	var name := source.get_file() if torrent else ("Magnet link" if source.begins_with("magnet:") else source)
	_menu("Add download", [{"id": "start", "label": "Download", "icon": "download"}, {"id": "paused", "label": "Add paused", "icon": ""}, {"id": "cancel", "label": "Cancel", "icon": "close"}],
		name + "\nSave to Downloads in its own folder.", func(id: String):
			if id != "cancel": Downloads.request("torrent" if torrent else "add", "", {"source": source, "paused": id == "paused"}))

func _task_actions(task: Dictionary) -> void:
	_selected = task
	_install_actions.clear()
	var items: Array = []
	var status := str(task.get("status", ""))
	var browser: bool = task.get("kind") == "browser"
	if status in ["complete", "seeding"]:
		for source: String in Downloads.installation_sources(task):
			var job: Dictionary = Downloads.installation_job(source)
			var entry: Dictionary = {}
			for candidate: Dictionary in WindowsInstall.library():
				if not candidate.has("setup_id") and str(candidate.get("recipe_id", "")) == str(job.get("id", "missing")):
					entry = Metadata.enrich(candidate)
			var action := "install:%d" % _install_actions.size()
			var choose: bool = job.get("status") in ["select", "failed"] and not job.get("choices", []).is_empty()
			_install_actions[action] = {"source": source, "start": not choose, "entry": entry}
			var caption := "Play " + str(entry.get("title", "")) if not entry.is_empty() else ("Choose program to play" if choose else "Install " + source.get_file())
			items.append({"id": action, "label": caption, "icon": "controller" if choose or not entry.is_empty() else "download"})
	if not browser:
		if status in ["active", "waiting", "seeding"]: items.append({"id": "pause", "label": "Pause", "icon": ""})
		if status == "paused": items.append({"id": "resume", "label": "Resume", "icon": ""})
		if status == "error": items.append({"id": "retry", "label": "Retry", "icon": "download"})
		if status == "seeding": items.append({"id": "stop-seeding", "label": "Stop seeding", "icon": ""})
		if task.get("kind") == "torrent" and status == "paused" and not task.get("files", []).is_empty(): items.append({"id": "files", "label": "Choose files", "icon": "check"})
	if not str(task.get("directory", "")).is_empty(): items.append({"id": "folder", "label": "Open folder", "icon": "folder"})
	if task.get("kind") != "setup":
		items.append({"id": "remove", "label": "Cancel download" if browser and status == "active" else "Remove from queue", "icon": "close"})
	var note := str(task.get("error", ""))
	if browser and status == "active": note = "This browser transfer continues while you use Home. Closing its tab cancels it."
	elif task.get("kind") == "torrent" and status in ["active", "waiting"]: note = "Pause to choose which files to download."
	_menu(str(task.get("name", "Download")), items, note, _task_action)

func _task_action(action: String) -> void:
	if _install_actions.has(action):
		var install: Dictionary = _install_actions[action]
		if not install.entry.is_empty():
			Downloads._finish()
			Launcher.launch(install.entry)
		else:
			Downloads.open_installation(str(install.source), bool(install.start), str(_selected.id))
		return
	match action:
		"folder":
			var files: Control = load("res://src/files_screen.gd").new()
			files.initial_directory = str(_selected.get("directory", ""))
			files.closed.connect(func(): _close_modal.call_deferred())
			_show_modal(files)
		"files": _choose_files()
		"remove":
			_menu("Remove download?", [{"id": "cancel", "label": "Keep in queue", "icon": "close"}, {"id": "remove", "label": "Remove from queue", "icon": "trash"}],
				"The transfer stops. Downloaded files are kept.", func(id: String):
					if id == "remove": Downloads.request("remove", str(_selected.id)))
		_: Downloads.request(action, str(_selected.id))


func focus_task(id: String) -> void:
	if _rows.has(id): _rows[id].grab_focus()

func _choose_files() -> void:
	var items: Array = []
	for file: Dictionary in _selected.get("files", []):
		items.append({"id": str(file.index), "label": ("✓ " if file.selected else "— ") + str(file.name), "icon": ""})
	_menu("Torrent files", items, "Keep at least one file selected. Resume from the download's actions.", func(id: String):
		var indices: Array = []
		for file: Dictionary in _selected.get("files", []):
			if (file.selected and str(file.index) != id) or (not file.selected and str(file.index) == id): indices.append(str(file.index))
		Downloads.request("select", str(_selected.id), {"indices": indices}))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_shell_home"):
		get_viewport().set_input_as_handled()
		closed.emit()
	elif event.is_action_pressed("ui_shell_x"):
		get_viewport().set_input_as_handled()
		_add_link()
	elif event.is_action_pressed("ui_shell_y"):
		get_viewport().set_input_as_handled()
		_pick_torrent()
