extends SceneTree

## Real file listings in isolated fixture directories; controller input uses the
## viewport seam. Optional captures use the same rendered scene as the checks.
var failures := 0
var fixture := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func frames(count: int = 5) -> void:
	for frame in count:
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

func capture(viewport: SubViewport, caption: String) -> void:
	var directory := OS.get_environment("MARWANOS_FILES_CAPTURE")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(directory.path_join(caption + ".png"))

func _run() -> void:
	fixture = OS.get_environment("MARWANOS_SHELL_FILES_HOME")
	if fixture.is_empty():
		push_error("Set MARWANOS_SHELL_FILES_HOME to an isolated fixture directory")
		quit(1)
		return
	for folder in ["Downloads", "Pictures", "Videos", "Music", "Projects"]:
		DirAccess.make_dir_recursive_absolute(fixture.path_join(folder))
	for caption in ["MarwanOS release notes.txt", "Controller layout.pdf", "Library backup.zip", "Setup.exe", "Weekend playlist.m3u", "A long filename that must keep its identity when the window gets narrow.txt"]:
		var file := FileAccess.open(fixture.path_join("Downloads").path_join(caption), FileAccess.WRITE)
		file.store_string("MarwanOS file layout fixture\n".repeat(48))
	for i in 22:
		var file := FileAccess.open(fixture.path_join("Projects/Project %02d.txt" % i), FileAccess.WRITE)
		file.store_string("Project notes\n")
	for dimensions in [Vector2i(1920, 1080), Vector2i(2580, 1080), Vector2i(900, 1080), Vector2i(480, 900), Vector2i(1280, 720), Vector2i(3840, 2160)]:
		var logical: Vector2i = Vector2i(1920, 1080) if dimensions.x in [1280, 3840] else dimensions
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.size_2d_override = logical
		viewport.size_2d_override_stretch = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var screen: Control = load("res://src/files_screen.gd").new()
		viewport.add_child(screen)
		await frames()
		check(screen._pane()._items.size() >= 5, "Files opens with a real listing at %s" % dimensions)
		check(screen._content.get_global_rect().end.x <= logical.x + 1, "content stays inside the viewport at %s" % dimensions)
		check(screen._pane()._scroll.size.y >= 100, "listing retains useful height at %s" % dimensions)
		var downloads: Dictionary = screen._places.places().filter(func(place: Dictionary): return place.name == "Downloads")[0]
		screen._on_place_chosen(downloads)
		await frames()
		check(screen._places._rows.filter(func(row: Control): return row.active).size() == 1, "current location has one marker at %s" % dimensions)
		var item: Control = screen._pane()._items[1]
		item.grab_focus()
		var header: Control = screen._heading.get_parent()
		check(header.get_children().filter(func(child: Node): return child is Button and child.text in ["Back", "Search", "View", "Actions"]).is_empty(), "Files has no duplicate top action buttons at %s" % dimensions)
		check(screen._hints.get_children().any(func(hint: Control): return hint.get_child(1).text == "Search"), "footer advertises Triangle search at %s" % dimensions)
		await press(viewport, "ui_shell_options")
		check(screen._menu != null and screen._menu_targets.size() == 1 and screen._menu_targets[0].name == item.entry.name, "Options targets the focused file at %s" % dimensions)
		check(screen._menu.items.any(func(option: Dictionary): return option.id == "mode"), "view settings stay available through Options at %s" % dimensions)
		await press(viewport, "ui_cancel")
		check(item.has_focus(), "closing Options restores the file at %s" % dimensions)
		await press(viewport, "ui_shell_y")
		check(screen._keyboard != null and screen._keyboard_purpose == "search" and screen._menu == null, "Triangle opens Search directly at %s" % dimensions)
		await press(viewport, "ui_cancel")
		check(item.has_focus(), "cancelling Search restores the file at %s" % dimensions)
		item.grab_focus()
		screen._menu_targets = [item.entry]
		screen._return_focus_name = item.entry.name
		screen._open_properties()
		await frames()
		var properties: Control = screen._properties
		var panel: Control = properties.get_child(1)
		check(absf(panel.position.x + panel.size.x - logical.x) < 1 and panel.size.y == logical.y, "Properties attaches to the screen edge at %s" % dimensions)
		var fact: Control = viewport.gui_get_focus_owner()
		await press(viewport, "ui_down")
		check(viewport.gui_get_focus_owner() != fact and properties.is_ancestor_of(viewport.gui_get_focus_owner()), "controller can move through Properties at %s" % dimensions)
		await capture(viewport, "files-properties-%d" % dimensions.x)
		await press(viewport, "ui_cancel")
		check(item.has_focus(), "closing Properties restores its file at %s" % dimensions)
		await press(viewport, "ui_shell_x")
		await frames()
		check(screen._selection.text == "1 selected" and item._check.modulate.a == 1.0, "selection has count and checkmark at %s" % dimensions)
		await press(viewport, "ui_shell_x")
		check(screen._pane().selection_count() == 0, "Square toggles selection off at %s" % dimensions)
		screen._refresh_chrome()
		await capture(viewport, "files-%d" % dimensions.x)
		screen._toggle_split()
		await frames()
		check(screen._panes[1].visible or screen._compact, "split keeps both locations available at %s" % dimensions)
		await press(viewport, "ui_shell_r1")
		check(screen._active == 1 and screen._panes[1].has_focus_inside() and screen._panes[1].visible, "R1 reaches the second pane at %s" % dimensions)
		await capture(viewport, "files-split-%d" % dimensions.x)
		await press(viewport, "ui_shell_l1")
		screen._toggle_split()
		await frames()
		screen._show_places()
		check(screen._places.has_focus_inside(), "Places stays reachable at %s" % dimensions)
		if screen._compact:
			check(not screen._content.visible and screen._places.size.x <= logical.x + 1, "compact Places uses the available width at %s" % dimensions)
			await press(viewport, "ui_cancel")
			check(screen._content.visible and screen._pane().has_focus_inside(), "Back returns from compact Places at %s" % dimensions)
		else:
			await press(viewport, "ui_right")
			check(screen._pane().has_focus_inside(), "Right returns from Places at %s" % dimensions)
		screen._pane()._items[0].grab_focus()
		await press(viewport, "ui_up")
		await press(viewport, "ui_up")
		check(screen._places_button.has_focus() if screen._compact else screen._pane()._crumbs.back().has_focus(), "Up stays in the breadcrumb or reaches compact Places at %s" % dimensions)
		await press(viewport, "ui_down")
		check(screen._pane()._crumbs.back().has_focus() if screen._compact else screen._pane()._items[0].has_focus(), "Down returns toward the listing at %s" % dimensions)
		screen._on_place_chosen({"name": "Home", "path": fixture, "root": fixture, "root_label": "Home"})
		await frames()
		var folder: Control = screen._pane()._items.filter(func(row: Control): return row.entry.name == "Downloads")[0]
		folder.grab_focus()
		await press(viewport, "ui_accept")
		check(screen._pane().path == fixture.path_join("Downloads"), "Cross opens the focused folder at %s" % dimensions)
		await press(viewport, "ui_cancel")
		check(screen._pane().path == fixture and screen._pane().focused_name() == "Downloads", "Circle goes back and restores the folder at %s" % dimensions)
		screen._on_place_chosen(downloads)
		var pane: Control = screen._pane()
		pane.set_search("nothing matches this")
		await frames()
		check(pane._empty.visible and pane._summary.text.contains("Search:"), "empty search remains understandable at %s" % dimensions)
		pane.set_search("")
		pane.set_view("icons", "name", false, false)
		await frames()
		check(pane._grid.size.x <= pane._scroll.size.x + 1, "icon view fits at %s" % dimensions)
		pane.set_view("compact", "name", false, false)
		await frames()
		check(pane._grid.size.x <= pane._scroll.size.x + 1, "compact view fits at %s" % dimensions)
		pane.set_view("details", "name", false, false)
		pane.show_directory(fixture.path_join("Projects"))
		await frames()
		pane._items.back().grab_focus()
		await frames()
		check(pane._scroll.scroll_vertical > 0, "long listings follow controller focus at %s" % dimensions)
		if dimensions.x == 1920:
			var retained: Control = pane._items.back()
			viewport.size = Vector2i(900, 1080)
			viewport.size_2d_override = Vector2i(900, 1080)
			await frames()
			check(pane._items.back() == retained and retained.has_focus(), "resize preserves the focused file without rebuilding rows")
			check(pane._scroll.scroll_vertical > 0 and retained.get_global_rect().end.y <= pane._scroll.get_global_rect().end.y + 1, "resize keeps the focused file scrolled into view")
			check(screen._content.visible and not screen._places.visible and pane._grid.size.x <= pane._scroll.size.x + 1, "resize reflows columns without opening Places")
		viewport.remove_child(screen)
		screen.queue_free()
		root.remove_child(viewport)
		viewport.queue_free()
		await frames()
	print("Files design checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
