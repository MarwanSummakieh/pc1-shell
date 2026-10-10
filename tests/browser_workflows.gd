extends SceneTree

var web: Control
var failures := 0
var base := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func wait_title(title: String) -> bool:
	for attempt in 120:
		if web._view.get_page_title() == title: return true
		await create_timer(0.1).timeout
	return false

func click_at(y: float) -> void:
	web._view.set_pointer(Vector2(150, y))
	web._view.click(1, true)
	web._view.click(1, false)

func press(button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func _run() -> void:
	web = load("res://src/browser_screen.gd").new()
	root.add_child(web)
	base = "http://127.0.0.1:" + OS.get_environment("PC1_DOWNLOAD_PORT")
	web.open_url(base + "/workflows")
	check(await wait_title("Workflows ready"), "actual CEF workflow fixture renders")
	await create_timer(0.5).timeout
	click_at(35)
	await create_timer(0.5).timeout
	check(web._menu != null and web._menu_purpose == "dialog", "JavaScript confirmation uses controller menu")
	web._menu_chosen("accept")
	check(await wait_title("Confirmed"), "controller confirms JavaScript dialog")
	click_at(105)
	await create_timer(0.5).timeout
	check(web._keyboard != null and web._keyboard_purpose == "prompt", "JavaScript prompt uses shell keyboard")
	web._on_typed("controller reply")
	check(await wait_title("Prompt:controller reply"), "prompt draft returned once to Chromium")
	click_at(175)
	await create_timer(0.5).timeout
	check(web._picker != null and web._picker.picker_mode, "file input opens controller Files picker")
	var path := OS.get_environment("PC1_DOWNLOAD_DIR").path_join("upload.txt")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("Browser upload fixture")
	file.close()
	var picker_completions: Array = []
	if web._picker != null:
		web._picker.files_picked.connect(func(paths: PackedStringArray): picker_completions.append(paths))
		web._picker._pane().show_directory(path.get_base_dir(), "upload.txt")
		web._picker._pane().grab_pane_focus("upload.txt")
		root.get_node("PlayerOne").device = 0
		await press(JOY_BUTTON_A)
	check(picker_completions == [PackedStringArray([path])], "Cross selects the readable upload file and completes Files picker once")
	check(await wait_title("File:upload.txt"), "controller-picked file reaches Chromium file input")
	# Select widgets need CEF's popup surface and keyboard navigation.
	web._view.set_pointer(Vector2(150, 245))
	web._view.click(1, true)
	await create_timer(0.2).timeout
	web._view.click(1, false)
	await create_timer(0.3).timeout
	check(web._view.is_popup_open(), "HTML select exposes popup state for controller dismissal")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	web._unhandled_input(cancel)
	await create_timer(0.3).timeout
	check(not web._view.is_popup_open() and web._view.get_page_title() == "File:upload.txt", "Circle dismisses select popup without navigating away")
	web._view.set_pointer(Vector2(150, 245))
	web._view.click(1, true)
	await create_timer(0.2).timeout
	web._view.click(1, false)
	await create_timer(0.3).timeout
	web._view.send_editing_key("Down")
	web._view.send_editing_key("Return")
	check(await wait_title("Selected:Second"), "HTML select works through embedded popup surface")
	var original: Control = web._view
	click_at(315)
	check(await wait_title("Download fixture"), "new-window link opens a live browser tab")
	check(web._tabs.size() == 2 and web._view != original, "controller link activation creates a separate tab")
	web._close_tab()
	check(web._view == original and web._view.get_page_title() == "Selected:Second", "closing link tab returns to its retained source page")
	web._toggle_bookmark()
	check(web._library.bookmarks.size() > 0, "bookmark saved")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(web.LIBRARY_PATH))
	check(saved is Dictionary and not saved.get("bookmarks", []).is_empty(), "bookmarks persisted to the browser library file")
	check(web._library.history.size() > 0, "successful internet visit recorded")
	web._open_menu()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("PC1_BROWSER_SCREENSHOT").get_base_dir().path_join("browser-options-verified.png"))
	web._menu_chosen("tabs")
	check(web._menu != null and web._menu_purpose == "tabs", "nested tab menu stays open")
	web._close_menu()
	web._open_downloads()
	check(web._picker != null and web._picker.get_script().resource_path == "res://src/downloads_screen.gd", "Browser opens the system Downloads surface")
	web._cancel_picker()
	var first: Control = web._view
	web._new_tab(base + "/second")
	check(await wait_title("Download fixture"), "second live CEF tab renders")
	web._activate_tab(first)
	check(web._view.get_page_title() == "Selected:Second", "switching tabs retains document state")
	web._view.set_download_directory(OS.get_environment("PC1_DOWNLOAD_DIR"))
	web._view.load_url(base + "/slow")
	await create_timer(1.0).timeout
	web.suspend_surface()
	await create_timer(2.0).timeout
	var active := false
	for download: Dictionary in web._downloads.values():
		if download.state == "downloading" and int(download.received) > 0: active = true
	check(not web.visible and active, "download continues while browser surface is hidden")
	web.show()
	web.set_process_unhandled_input(true)
	web._close_tab()
	check(web._tabs.size() == 1 and web._view != first, "tab closure leaves valid active page")
	check(web.address_url("JaVaScRiPt:alert(1)").is_empty(), "mixed-case unsafe address rejected")
	check(web.address_url("https://example.com\nheader").is_empty(), "address control characters rejected")
	print("Browser workflow checks: %d failure(s)" % failures)
	root.remove_child(web)
	web.queue_free()
	await create_timer(0.5).timeout
	quit(1 if failures else 0)
