extends SceneTree

## Behaviour and layout checks for the shared console design system.
var failures := 0

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

func _run() -> void:
	var router := root.get_node("ControllerRouter")
	router.set_process(false)
	router._routed = true
	root.get_node("PlayerOne").device = 15
	var installed := root.get_node("Installed")
	for child in installed.get_children():
		if child is Timer:
			child.stop()
	var artwork := OS.get_environment("MARWANOS_DESIGN_ART")
	installed.apps = []
	var ids := ["1778820", "1030300", "1245620", "1551360", "1145360", "1091500"]
	var titles := ["TEKKEN 8", "Hollow Knight: Silksong", "Elden Ring", "Forza Horizon 5", "Hades", "Cyberpunk 2077"]
	for index in ids.size():
		installed.apps.append({"id": "steam." + ids[index], "title": titles[index],
			"state": "installed", "exec": ["never-run"],
			"cover": artwork.path_join(ids[index] + ".jpg") if not artwork.is_empty() else "",
			"metadata": {"release_date": "2026", "genres": ["Action", "Adventure"], "developers": ["Example Game Studio"],
				"description": "Explore a detailed world, discover new places and master its challenges with your friends.",
				"assets": {"background": {"path": artwork.path_join("hero.jpg") if not artwork.is_empty() else ""}}}})
	installed.apps.append({"id": "steam", "title": "Steam", "state": "installed", "exec": ["never-run"]})
	installed.apps.append({"id": "managed.fdm", "title": "FDM Classic", "state": "installed", "exec": ["never-run"]})
	installed.apps.append({"id": "steam.pending", "title": "Pending game", "state": "downloading", "exec": []})
	for dimensions in [Vector2i(1920, 1080), Vector2i(2580, 1080), Vector2i(900, 1080), Vector2i(1280, 720), Vector2i(3840, 2160)]:
		var logical: Vector2i = Vector2i(1920, 1080) if dimensions.x in [1280, 3840] else dimensions
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.size_2d_override = logical
		viewport.size_2d_override_stretch = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var home: Control = load("res://scenes/shell_root.tscn").instantiate()
		viewport.add_child(home)
		await frames()
		check(not home._bar_row.visible, "system dock starts hidden with a controller at %s" % dimensions)
		check(home._cards.size() == ids.size(), "Home excludes Steam, download tools and pending transfers at %s" % dimensions)
		check(home._rail_row.position.y >= home._header.position.y + home._header.size.y,
			"library never overlaps user identity at %s" % dimensions)
		check(home._bar_row.position.y + home._bar_row.size.y <= logical.y + 1,
			"bottom navigation fits the viewport at %s" % dimensions)
		check(home._bar_row.size.x <= logical.x + 1,
			"bottom navigation scrolls within the viewport at %s" % dimensions)
		check(home._cards[0].get_global_rect().end.y <= home._summary_row.get_global_rect().position.y,
			"enlarged artwork leaves the game overview clear at %s" % dimensions)
		check(home._home_actions.position.y >= home._summary_row.position.y + home._summary_row.get_combined_minimum_size().y,
			"Play and Options stay below wrapped game details at %s" % dimensions)
		check(home._cards[0].size.x < home._cards[0].size.y, "Home artwork uses vertical rectangular tiles")
		check(home._cards[0]._icon_rect.get_parent().clip_children == CanvasItem.CLIP_CHILDREN_ONLY,
			"artwork is clipped to the rounded card silhouette")
		var original: Control = home._cards[0]
		home._on_apps_changed(installed.apps)
		await frames()
		check(home._cards[0] == original, "library refresh reuses unchanged controls at %s" % dimensions)
		installed.apps[0]["state"] = "downloading"
		home._on_apps_changed(installed.apps)
		check(home._cards.size() == ids.size() - 1, "pending transfers leave Home")
		installed.apps[0]["state"] = "installed"
		home._on_apps_changed(installed.apps)
		await frames()
		original = home._cards[0]
		original.grab_focus()
		check(not home._play_button.disabled, "installation completion restores a playable card")
		await press(viewport, "ui_down")
		check(home._details == null and home.visible and home._play_button.has_focus(), "Down enters Home actions without opening a details page")
		await press(viewport, "ui_cancel")
		check(original.has_focus(), "Back returns to the selected game")
		home._selected_card = original
		home._open_card_menu()
		await frames()
		var menu: Control = home._card_menu
		check(menu != null and menu._rows.size() == 3, "Options exposes supported game actions")
		check(menu._rows[0].has_focus(), "Options begins on the safe View details action")
		var panel: Control = menu.get_child(1)
		check(absf(panel.position.x + panel.size.x - logical.x) < 1 and absf(panel.size.y - logical.y) < 1,
			"Options attaches to the right edge and fills the height at %s" % dimensions)
		if dimensions.x == 1920:
			await capture(viewport, "options")
		home._close_card_menu()
		await frames()
		check(original.has_focus(), "closing Options restores the originating game")
		await press(viewport, "ui_shell_home")
		check(home._bar_row.visible and home._bar_buttons[0].has_focus(), "PS/Home reveals and focuses the system dock")
		home._audio_button.grab_focus()
		await frames()
		await press(viewport, "ui_accept")
		var volume: Control = home._volume_popup
		check(volume != null and home.visible and home._details == null, "Audio opens a compact slider over Home")
		await frames()
		var volume_rect: Rect2 = volume._panel.get_global_rect()
		check(volume_rect.position.x >= 0 and volume_rect.end.x <= logical.x and volume_rect.position.y >= 0,
			"volume popup fits the viewport at %s" % dimensions)
		check(volume_rect.end.y < home._audio_button.global_position.y, "volume popup stays above Audio at %s" % dimensions)
		await capture(viewport, "volume-%d" % dimensions.x)
		await press(viewport, "ui_focus_next")
		check(volume.is_ancestor_of(viewport.gui_get_focus_owner()), "Tab stays inside the volume popup")
		if dimensions.x == 1920:
			var outside := InputEventMouseButton.new()
			outside.button_index = MOUSE_BUTTON_LEFT
			outside.position = Vector2(4, 4)
			outside.pressed = true
			viewport.push_input(outside, true)
			await frames()
			outside.pressed = false
			viewport.push_input(outside, true)
			await frames()
		else:
			await press(viewport, "ui_cancel")
		check(home._volume_popup == null and home._audio_button.has_focus(), "dismissing volume restores Audio focus")
		home._bar_buttons[0].grab_focus()
		await press(viewport, "ui_right")
		await press(viewport, "ui_shell_home")
		check(not home._bar_row.visible and original.has_focus(), "second PS/Home hides the dock and restores the game")
		await press(viewport, "ui_up")
		check(home._play_button.has_focus() and not home._bar_row.visible, "Up reaches Play without revealing the system dock")
		await press(viewport, "ui_right")
		check(home._details_button.has_focus(), "controller reaches the secondary action")
		await press(viewport, "ui_down")
		check(original.has_focus(), "actions return to the selected game without targeting hidden navigation")
		home._open_stores()
		await frames()
		check(home._stores != null and home._stores._steam.has_focus(), "Stores opens with Steam focused")
		check(not home._bar_row.visible and home._header.is_visible_in_tree(), "Stores keeps user identity while the dock is hidden")
		var expanded_height: float = home._stores.size.y
		await press(viewport, "ui_shell_home")
		check(home._bar_row.visible and viewport.gui_get_focus_owner().get_meta("destination", "") == "Stores", "PS/Home focuses the active Stores destination")
		check(home._stores.size.y < expanded_height, "Stores reserves dock space only while it is shown")
		await press(viewport, "ui_up")
		check(home._stores._steam.has_focus(), "system navigation returns to the visible store")
		await press(viewport, "ui_shell_home")
		check(not home._bar_row.visible and home._stores._steam.has_focus(), "PS/Home hides navigation without leaving Stores")
		await press(viewport, "ui_down")
		check(home._stores._steam.has_focus(), "hidden dock controls are excluded from store navigation")
		var steam := root.get_node("SteamEmbed")
		var previous_snapshot: Dictionary = steam.snapshot
		steam.snapshot = {"phase": "ready"}
		steam._surface = home._stores._pane
		steam._want_focus = true
		viewport.gui_get_focus_owner().release_focus()
		await press(viewport, "ui_shell_home")
		check(home._bar_row.visible and not steam.owns_input(), "PS/Home transfers embedded Steam input to the dock")
		await press(viewport, "ui_shell_home")
		check(not home._bar_row.visible and steam.owns_input(), "second PS/Home restores embedded Steam input")
		steam.leave_pane()
		steam.snapshot = previous_snapshot
		home._stores._open_steam()
		await frames()
		check(not root.get_node("Launcher").is_busy(), "unavailable windowed Steam never launches a fullscreen client")
		var store_window: Control = home._stores._window
		check(store_window.position.x + store_window.size.x <= home._stores.size.x + 1 and
			store_window.position.y + store_window.size.y <= home._stores.size.y + 1,
			"Steam window stays inside the content region at %s" % dimensions)
		if dimensions.x != 2580:
			await capture(viewport, "stores-%d" % dimensions.x)
		home._show_home()
		await frames()
		check(home._stores == null and original.has_focus(), "Home restores the library and selected game")
		await create_timer(0.3).timeout
		await frames()
		await capture(viewport, "home-%d" % dimensions.x)
		viewport.remove_child(home)
		home.queue_free()
		root.remove_child(viewport)
		viewport.queue_free()
		await frames()
	installed.apps = []
	var empty_viewport := SubViewport.new()
	empty_viewport.size = Vector2i(1920, 1080)
	root.add_child(empty_viewport)
	var empty_home: Control = load("res://scenes/shell_root.tscn").instantiate()
	empty_viewport.add_child(empty_home)
	await frames()
	check(empty_home._bar_row.visible, "an empty library initially exposes its setup navigation")
	await press(empty_viewport, "ui_shell_home")
	check(not empty_home._bar_row.visible, "PS/Home can hide navigation with an empty library")
	await press(empty_viewport, "ui_shell_home")
	check(empty_home._bar_row.visible and empty_viewport.gui_get_focus_owner() != null, "PS/Home always recovers navigation with an empty library")
	empty_viewport.queue_free()
	await frames()
	print("Design shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)

func capture(viewport: SubViewport, name_text: String) -> void:
	var folder := OS.get_environment("MARWANOS_DESIGN_CAPTURE")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	# Offscreen viewports must also render while a desktop preview is minimised.
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	if image != null:
		image.save_png(folder.path_join(name_text + ".png"))
