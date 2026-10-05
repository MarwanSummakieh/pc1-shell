extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func _run() -> void:
	var installs := root.get_node("WindowsInstall")
	var directory: String = installs.home.path_join("setup-ui/layout-fixture")
	DirAccess.make_dir_recursive_absolute(directory)
	var controls: Array = [{"id": 1, "kind": "text", "text": "Select components"},
		{"id": 2, "kind": "text", "text": "Choose the components you want to install."},
		{"id": 3, "kind": "edit", "text": "C:\\Games\\Fixture Game", "destination": true},
		{"id": 4, "kind": "check", "text": "Limit installer to 2 GB of RAM usage", "checked": 0}]
	var names := ["English voiceovers", "French voiceovers", "German voiceovers", "Optional HD textures", "Update DirectX", "Install Microsoft Visual C++", "Create desktop shortcut", "Verify files after installation"]
	for index in names.size():
		controls.append({"id": index + 10, "kind": "check", "text": names[index], "checked": 1 if index == 0 else 0})
	controls.append_array([{"id": 39, "kind": "button", "text": "Installer music", "music": true}, {"id": 40, "kind": "button", "text": "< Back"},
		{"id": 41, "kind": "button", "text": "Install"}, {"id": 42, "kind": "button", "text": "Cancel"}])
	var file := FileAccess.open(directory.path_join("page.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"title": "Fixture Game — FitGirl Repack", "page": 100,
		"host_directory": "/home/player/Games/local-fixture", "controls": controls}))
	file.close()
	var wizard: Control = load("res://src/windows_setup_wizard.gd").new()
	wizard.job_key = "layout-fixture"
	root.add_child(wizard)
	var evidence := OS.get_environment("PC1_SETUP_EVIDENCE")
	if not evidence.is_empty():
		DirAccess.make_dir_recursive_absolute(evidence)
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = dimensions
		await create_timer(0.15).timeout
		check(wizard._body_rows.size() == 10, "all repack options remain available at %s" % str(dimensions))
		check(wizard._footer.get_global_rect().end.y <= root.get_visible_rect().end.y, "navigation stays inside the viewport at %s" % str(dimensions))
		check(wizard._scroll.get_global_rect().end.y < wizard._footer.get_global_rect().position.y, "option scrolling stays above navigation at %s" % str(dimensions))
		wizard._body_rows[-1].grab_focus()
		await create_timer(0.15).timeout
		check(wizard._scroll.scroll_vertical > 0, "focus scrolls to the final verification option at %s" % str(dimensions))
		wizard._body_rows[0].grab_focus()
		await create_timer(0.15).timeout
		if not evidence.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(evidence.path_join("setup-%dx%d.png" % [dimensions.x, dimensions.y]))
	print("Windows setup layout checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
