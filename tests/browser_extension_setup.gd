extends SceneTree

var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
func _run() -> void:
	for mapped_action in InputMap.get_actions():
		for event in InputMap.action_get_events(mapped_action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(mapped_action, event)
	var view: Control = ClassDB.instantiate("MowserView")
	view.size = Vector2(800, 600)
	var path := OS.get_environment("PC1_EXTENSION_FIXTURE_PATH")
	var accepted: bool = view.set_extension_paths(PackedStringArray([path]))
	check(accepted, "setup fixture is accepted before browser startup")
	if not accepted:
		view.free()
		quit(1)
		return
	root.add_child(view)
	await create_timer(2).timeout
	var canonical: String = view.get_active_extension_paths()[0]
	var entry := {"uid": canonical.get_file()}
	var page: String = load("res://src/browser_extensions.gd").page_url(entry, view.get_active_extension_paths())
	view.set_extension_panel_rect(Rect2(840, 104, 760, 796))
	check(view.open_extension_page(page.replace("setup.html", "popup.html")), "extension action page opens in the native panel")
	await create_timer(2).timeout
	OS.execute("/usr/bin/xdotool", ["mousemove", "1000", "150", "click", "1"])
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline and view.get_extension_page_url() != page:
		await create_timer(0.1).timeout
	check(view.get_extension_page_url() == page, "chrome.tabs.create setup pages stay open inside the panel")
	await create_timer(1).timeout
	OS.execute("/usr/bin/xdotool", ["mousemove", "1000", "150", "click", "1"])
	await create_timer(0.2).timeout
	view.extension_type_text("bench")
	await create_timer(0.3).timeout
	check(view.get_extension_page_url().ends_with("setup.html#bench"), "controller text reaches the extension's focused setup field")
	view.extension_editing_key("BackSpace")
	await create_timer(0.3).timeout
	check(view.get_extension_page_url().ends_with("setup.html#benc"), "controller editing keys update the extension setup field")
	var capture := OS.get_environment("PC1_UI_CAPTURE_DIR")
	if not capture.is_empty(): OS.execute("/usr/bin/import", ["-window", "root", capture.path_join("native-extension-setup-input.png")])
	view.extension_command("close")
	await create_timer(1).timeout
	root.remove_child(view)
	view.queue_free()
	await create_timer(0.5).timeout
	print("Extension setup checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
