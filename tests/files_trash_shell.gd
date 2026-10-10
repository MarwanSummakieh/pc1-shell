extends SceneTree

const Trash = preload("res://src/file_trash.gd")
var failures := 0
var fixture := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func frames(count: int = 5) -> void:
	for _frame in count:
		await process_frame

func press(viewport: SubViewport, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	viewport.push_input(event, true)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)
	await frames(2)

func choose(viewport: SubViewport, screen: Control, id: String) -> void:
	for index in screen._menu.items.size():
		if screen._menu.items[index].id == id:
			screen._menu._rows[index].grab_focus()
			await press(viewport, "ui_accept")
			return
	check(false, "menu offers " + id)

func write(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("Trash fixture\n")
	file.close()

func _run() -> void:
	fixture = OS.get_environment("MARWANOS_SHELL_FILES_HOME")
	if fixture.is_empty():
		push_error("Set MARWANOS_SHELL_FILES_HOME to an isolated fixture directory")
		quit(1)
		return
	# Test deletion only inside a separate trash rooted in this fixture.
	OS.set_environment("XDG_DATA_HOME", fixture.path_join(".trash-test-data"))
	DirAccess.make_dir_recursive_absolute(fixture)
	var sentinel := fixture.path_join("Keep outside trash.txt")
	write(sentinel)
	for dimensions in [Vector2i(1920, 1080), Vector2i(900, 1080), Vector2i(480, 900)]:
		var document := fixture.path_join("Deleted notes.txt")
		var folder := fixture.path_join("Deleted folder")
		DirAccess.make_dir_recursive_absolute(folder.path_join("nested"))
		write(folder.path_join("nested/.hidden"))
		write(document)
		check(Trash.trash(document) == OK and Trash.trash(folder) == OK, "fixtures enter the recoverable trash at %s" % dimensions)
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var screen: Control = load("res://src/files_screen.gd").new()
		viewport.add_child(screen)
		await frames()
		var row: Control = screen._places._rows.filter(func(place: Control): return place.get_meta("place").path == Trash.LOCATION)[0]
		check(row._value == "2 items", "left Trash bin shows its item count at %s" % dimensions)
		screen._show_places()
		row.grab_focus()
		await press(viewport, "ui_accept")
		check(screen._pane().path == Trash.LOCATION and screen._pane()._items.size() == 2 and row.active, "Cross opens Trash bin as the active listing at %s" % dimensions)
		check(screen._content.visible and screen._pane()._scroll.size.y >= 100, "trash listing fits the available screen at %s" % dimensions)
		check(screen._pane().history_move(-1) and screen._pane().place_root == fixture, "history restores the previous location root at %s" % dimensions)
		check(screen._pane().history_move(1) and screen._pane().place_root == Trash.LOCATION, "history returns to Trash bin with its own root at %s" % dimensions)
		check(screen._pane()._items.all(func(item: Control): return item.entry.name in ["Deleted notes.txt", "Deleted folder"]), "trash shows original names at %s" % dimensions)
		var capture_dir := OS.get_environment("MARWANOS_FILES_CAPTURE")
		if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
			RenderingServer.force_draw(false)
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(capture_dir.path_join("trash-%d.png" % dimensions.x))
		var item: Control = screen._pane()._items.filter(func(file: Control): return file.entry.name == "Deleted notes.txt")[0]
		item.grab_focus()
		await press(viewport, "ui_shell_y")
		check(screen._keyboard != null and screen._keyboard.title_text == "Search trash bin", "Triangle searches Trash bin at %s" % dimensions)
		await press(viewport, "ui_cancel")
		check(item.has_focus(), "cancelling trash search restores its item at %s" % dimensions)
		await press(viewport, "ui_shell_x")
		await press(viewport, "ui_shell_options")
		check(screen._menu.items.any(func(option: Dictionary): return option.id == "restoretrash"), "Options offers restore for selected trash at %s" % dimensions)
		check(not screen._menu.items.any(func(option: Dictionary): return option.id in ["delete", "rename", "cut", "paste", "newfolder"]), "trash avoids ordinary file mutations at %s" % dimensions)
		await choose(viewport, screen, "restoretrash")
		check(FileAccess.file_exists(document) and screen._pane()._items.size() == 1 and row._value == "1 item", "restore updates disk, listing and sidebar at %s" % dimensions)
		screen._pane()._items[0].grab_focus()
		await press(viewport, "ui_accept")
		check(FileAccess.file_exists(folder.path_join("nested/.hidden")) and screen._pane()._items.is_empty(), "Cross restores a complete deleted folder at %s" % dimensions)
		check(screen._pane()._empty.text == "Trash bin is empty" and row._value == "0 items", "empty trash stays visible and understandable at %s" % dimensions)
		check(Trash.trash(document) == OK and Trash.trash(folder) == OK, "fixtures can be trashed again at %s" % dimensions)
		screen._refresh_trash()
		await press(viewport, "ui_shell_options")
		await choose(viewport, screen, "emptytrash")
		check(screen._menu != null and screen._menu.title_text == "Empty trash bin?" and screen._menu._rows[0].has_focus(), "emptying requires confirmation with Cancel focused at %s" % dimensions)
		await press(viewport, "ui_cancel")
		check(Trash.entries().size() == 2, "cancelling empty keeps every deleted item at %s" % dimensions)
		write(Trash.trash_root().path_join("files/.orphan"))
		write(Trash.trash_root().path_join("info/.orphan.trashinfo"))
		var link := Trash.trash_root().path_join("files/external-link")
		var link_error := DirAccess.open(Trash.trash_root().path_join("files")).create_link(fixture, link)
		if link_error != OK:
			print("SKIP: symlink creation unavailable on this host")
		await press(viewport, "ui_shell_options")
		await choose(viewport, screen, "emptytrash")
		await choose(viewport, screen, "emptytrashconfirmed")
		check(not Trash.has_contents() and Trash.entries().is_empty() and screen._pane()._items.is_empty() and row._value == "0 items", "confirmed empty removes files, nested folders, hidden entries and metadata at %s" % dimensions)
		check(FileAccess.file_exists(sentinel), "emptying leaves files outside Trash intact at %s" % dimensions)
		check(Trash._remove_entry(sentinel, Trash.trash_root().replace("\\", "/").simplify_path()) == ERR_INVALID_PARAMETER and FileAccess.file_exists(sentinel), "trash deletion rejects a path outside its root at %s" % dimensions)
		check(Trash.empty().ok, "emptying an already empty trash succeeds at %s" % dimensions)
		await press(viewport, "ui_cancel")
		check(screen._places.has_focus_inside(), "Circle returns from Trash bin to Places at %s" % dimensions)
		var closed: Array = []
		screen.closed.connect(func(): closed.append(true))
		await press(viewport, "ui_cancel")
		check(closed.size() == 1, "Circle can close Files from the location root at %s" % dimensions)
		viewport.remove_child(screen)
		screen.queue_free()
		root.remove_child(viewport)
		viewport.queue_free()
		await frames()
	var picker: Control = load("res://src/files_screen.gd").new()
	picker.picker_mode = true
	root.add_child(picker)
	await frames()
	check(not picker._places.places().any(func(place: Dictionary): return place.path == Trash.LOCATION), "file pickers omit Trash bin")
	root.remove_child(picker)
	picker.queue_free()
	await frames()
	print("Files trash checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
