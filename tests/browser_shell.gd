extends SceneTree

## Native layout and controller regression checks; actual CEF has separate suites.
class PageFixture extends Control:
	var url := "https://example.com"
	var title := "Example page"
	var pointer := Vector2(100, 100)
	var back_count := 0
	var clicks := 0
	var releases := 0
	var edits: Array = []
	var occlusion := Rect2()
	var loading := false
	func load_url(value: String) -> void: url = value
	func get_page_url() -> String: return url
	func get_page_title() -> String: return title
	func can_go_back() -> bool: return true
	func can_go_forward() -> bool: return false
	func is_loading() -> bool: return loading
	func go_back() -> void: back_count += 1
	func get_pointer() -> Vector2: return pointer
	func set_pointer(value: Vector2) -> void: pointer = value
	func move_pointer(value: Vector2) -> void: pointer += value
	func click(_button: int, pressed: bool) -> void:
		if pressed: clicks += 1
		else: releases += 1
	func scroll(_amount: Vector2) -> void: pass
	func type_text(value: String) -> void: edits.append(value)
	func send_editing_key(key: String) -> void: edits.append(key)
	func reveal_focused_field(rect: Rect2) -> void: occlusion = rect

var failures := 0
var web: Control
var captures := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func capture(filename: String) -> void:
	if captures.is_empty(): return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(captures.path_join(filename))

func action(name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	web._unhandled_input(event)

func stick_click() -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_LEFT_STICK
	event.pressed = true
	web._unhandled_input(event)

func press_action(name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await settle()

func _run() -> void:
	for mapped_action in InputMap.get_actions():
		for event in InputMap.action_get_events(mapped_action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(mapped_action, event)
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	captures = OS.get_environment("PC1_UI_CAPTURE_DIR")
	web = load("res://src/browser_screen.gd").new()
	root.add_child(web)
	web._library = {"bookmarks": [], "history": []}
	web._chrome.refresh_library(web._library)
	await settle()
	check(web._is_start_page() and web._controls_active, "browser opens on native start page")
	check(root.gui_get_focus_owner() == web._chrome.search, "start page focuses search for controller use")
	check(web._chrome._tabs.tooltip_text.contains("1/8"), "toolbar keeps the tab switcher available without a tab strip")
	check(web._chrome._window.get_rect() == Rect2(Vector2.ZERO, web.size), "browser fills the screen without an outer window frame")
	check(web._chrome.page_rect() == Rect2(0, 60, 1920, 1020), "page fills the screen below a single toolbar")
	web._chrome._tabs.pressed.emit()
	check(web._menu_purpose == "tabs" and web._menu.items[0].label == "Current · New tab", "toolbar opens the retained tab list")
	web._close_menu()
	web._chrome.search.grab_focus()
	check(web._chrome._shortcuts.get_child_count() == 6, "start page exposes six working shortcuts")
	await capture("browser-start-1920.png")
	await press_action("ui_down")
	check(web._chrome._shortcuts.is_ancestor_of(root.gui_get_focus_owner()), "D-pad moves focus from search into the shortcuts")
	web._chrome.search.grab_focus()
	action("ui_shell_x")
	await settle()
	check(web._keyboard != null, "Square opens address keyboard from start page")
	await capture("browser-address-1920.png")
	web._close_keyboard()
	check(root.gui_get_focus_owner() == web._chrome.search, "cancelling address restores native focus")
	web._open_menu()
	web._close_menu()
	check(root.gui_get_focus_owner() == web._chrome.search, "dismissing options restores native focus")
	var old: Control = web._view
	var page := PageFixture.new()
	web.add_child(page)
	web.move_child(page, web.get_children().find(web._cursor_layer))
	web._tabs[0] = page
	web._view = page
	web.remove_child(old)
	old.queue_free()
	web.show_start_page()
	web._chrome._shortcuts.get_child(0).grab_focus()
	await press_action("ui_accept")
	check(page.url == "https://www.youtube.com" and not web._is_start_page(), "shortcut activation opens its URL in the current tab")
	check(page.clicks == 0 and page.releases == 0, "selecting a shortcut never sends its confirm press or release into Chromium")
	web.open_url("https://example.com")
	await settle()
	check(web._view.visible and not web._chrome._start.visible, "opening a URL exchanges the native start surface for web content")
	check(web._address.text == "https://example.com", "address shows the requested URL immediately")
	check(not web._controls_active and root.gui_get_focus_owner() == null, "opening a URL gives the controller to the page")
	check(web._view.get_rect() == web._chrome.page_rect(), "Chromium occupies exactly the window content rectangle")
	stick_click()
	check(web._controls_active and root.gui_get_focus_owner() == web._chrome.address_button, "L3 focuses browser controls")
	action("ui_accept")
	check(page.clicks == 0, "native control selection never clicks the page beneath")
	action("ui_cancel")
	check(not web._controls_active and page.back_count == 0, "Circle leaves native controls before navigating history")
	action("ui_cancel")
	check(page.back_count == 1, "Circle in page mode navigates history")
	web._open_address()
	await settle()
	check(web._keyboard.initial_text == "https://example.com", "address editor preserves the current URL")
	check(web._view.get_rect() == web._page_bounds, "floating keyboard preserves the browser content rectangle")
	web._close_keyboard()
	check(web._view.get_rect() == web._page_bounds, "closing keyboard preserves fullscreen page geometry")
	web._keyboard_moved(Rect2(80, 400, 568, 480))
	check(web._view.get_rect() == web._page_bounds, "moving the floating keyboard keeps the page inside its window")
	web._keyboard_rect = Rect2()
	web._layout_browser()
	web._click(true)
	web._on_keyboard_context({"editable": true, "type": "text"})
	await settle()
	check(web._keyboard == null, "field activation waits until the pointer is released")
	web._click(false)
	await settle()
	check(web._keyboard != null and web._keyboard.live_input, "clicking a text field automatically opens the floating keyboard")
	var keyboard: Control = web._keyboard
	web._on_keyboard_context({"editable": true, "type": "text"})
	await settle()
	check(web._keyboard == keyboard, "duplicate focus notifications retain the same keyboard and key focus")
	web._keyboard._insert("hello")
	check(page.edits == ["hello"] and web._keyboard._text.is_empty(), "floating keys type directly into the active page")
	web._keyboard.move_panel(Vector2(-200, -100))
	check(web._view.get_rect() == web._page_bounds, "moving the floating keyboard never resizes the document")
	var click := InputEventMouseButton.new()
	click.position = web._view.global_position + Vector2(20, 20)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	web._input(click)
	click.pressed = false
	web._input(click)
	check(page.clicks >= 1 and not web._click_held, "the page remains clickable around the floating keyboard")
	web._on_keyboard_context({"editable": true, "type": "password"})
	await settle()
	check(web._keyboard.masked and not web._keyboard._entry.visible, "switching to a password field keeps its content in the page")
	web._on_keyboard_context({"editable": false})
	await settle()
	check(web._keyboard == null, "leaving editable fields dismisses the floating keyboard")
	web._open_menu()
	web._on_keyboard_context({"editable": true, "type": "text"})
	await settle()
	check(web._keyboard == null, "field notifications cannot interrupt an open browser menu")
	web._close_menu()
	web._toggle_bookmark()
	check(web._library.bookmarks.size() == 1 and web._chrome._saved_heading.text == "Bookmarks", "saving a page updates native bookmark shortcuts")
	web._toggle_bookmark()
	check(web._library.bookmarks.is_empty() and web._chrome._saved_heading.text == "Shortcuts", "removing bookmark restores default shortcuts")
	web._record_history(page, page.url)
	check(web._chrome._recent.get_child_count() == 1 and web._chrome._recent.get_child(0).text == "Example page", "successful visits update recent pages")
	web._new_tab()
	check(web._tabs.size() == 2 and web._is_start_page(), "new tabs open the native start page")
	web._chrome._recent.get_child(0).grab_focus()
	web._chrome.refresh_library(web._library)
	check(root.gui_get_focus_owner() == web._chrome._recent.get_child(0), "history updates preserve focus on the selected recent page")
	web._activate_tab(page)
	check(web._view == page and page.back_count == 1, "tab switching retains existing page state")
	web._close_tab()
	check(web._tabs.size() == 1 and web._is_start_page(), "closing live tab returns to retained start page")
	for index in 7: web._new_tab()
	web._new_tab()
	check(web._tabs.size() == 8 and not web._last_error.is_empty(), "tab limit is enforced and visible on native start page")
	check(web._status.text == web._last_error, "native page displays tab limit errors without an engine")
	web.suspend_surface()
	web.resume_surface()
	check(web.visible and web._controls_active and root.gui_get_focus_owner() != null, "reopening browser restores controller focus")
	for viewport in [Vector2i(1280, 720), Vector2i(2580, 1080), Vector2i(960, 720)]:
		root.size = viewport
		await settle()
		web._layout_browser()
		await settle()
		var rect: Rect2 = web._chrome._window.get_rect()
		check(rect == Rect2(Vector2.ZERO, web.size), "browser fills %dx%d" % [viewport.x, viewport.y])
		check(web._chrome.page_rect() == Rect2(0, 60, web.size.x, web.size.y - 60), "page uses the full available screen at %dx%d" % [viewport.x, viewport.y])
		check(web._chrome._toolbar.size.x >= web._chrome._toolbar.get_combined_minimum_size().x, "toolbar controls fit %dx%d" % [viewport.x, viewport.y])
		check(web._chrome.search.get_global_rect().end.x <= rect.end.x, "search remains inside screen at %dx%d" % [viewport.x, viewport.y])
		await capture("browser-start-%d.png" % viewport.x)
	root.remove_child(web)
	web.queue_free()
	await settle()
	var browser := root.get_node("Browser")
	browser.open()
	await settle()
	check(browser.is_open() and browser._screen._is_start_page(), "Browser service opens native start page without a network navigation")
	var retained: Control = browser._screen._view
	browser._screen._chrome_action("close")
	await settle()
	check(not browser.is_open(), "Home closes the surface through its existing service lifecycle")
	browser.open()
	await settle()
	check(browser._screen._view == retained and root.gui_get_focus_owner() != null, "Browser service reuses its retained tab and restores native focus")
	browser._finish_deferred()
	print("Browser shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
