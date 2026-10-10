extends Control

## The shell owns the browser window, start page, tabs, cursor and keyboard.
## Mowser renders only the web content. L3 switches between native controls and
## the page pointer; Circle leaves controls before navigating page history.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Keyboard = preload("res://src/keyboard.gd")
const ListMenu = preload("res://src/list_menu.gd")
const BrowserChrome = preload("res://src/browser_chrome.gd")
const ExtensionToolbar = preload("res://src/browser_extension_toolbar.gd")
const PadKeys = preload("res://src/pad_keys.gd")
const BrowserExtensionMenu = preload("res://src/browser_extension_menu.gd")
const BrowserExtensions = preload("res://src/browser_extensions.gd")

## Cursor speed and response, lifted verbatim from pad_keys.gd's pointer
## dialect -- the same stick doing the same job should feel identical whether
## the thing under it is a page in this shell or an application beside it.
const POINTER_SPEED := 900.0
const POINTER_CURVE := 2.0

## How far one shoulder press scrolls. CEF takes wheel deltas in pixels, and
## this is about a third of a screen -- a reading step rather than a nudge.
const SCROLL_STEP := 320.0

## Repeat cadence for a held shoulder, matching the pad bridge's own.
const SCROLL_INTERVAL := 0.1

## Continuous page scrolling on the right stick. The deadzone absorbs ordinary
## controller drift; the curve keeps small reading adjustments precise while a
## full tilt can cross a long page without repeated shoulder presses.
const STICK_SCROLL_DEADZONE := 0.18
const STICK_SCROLL_SPEED := 1200.0
const STICK_SCROLL_CURVE := 1.6

## The cursor this screen draws, because the engine deliberately draws none.
## A ring rather than an arrow: an arrow has a hotspot a person has to learn,
## and on a television at three metres the thing that matters is being able to
## FIND it against arbitrary page content -- so it is a light ring with a dark
## outline, which survives being over white text and over a black hero image.
const CURSOR_RADIUS := 11.0
const CURSOR_OUTLINE := 3.0

## What the status line says while the engine works. The page cannot be trusted
## to explain itself -- a site that hangs shows nothing at all -- so this line
## is the shell's own account of what it asked for and what came back.
const STATUS_LOADING := "Loading"
const STATUS_READY := ""

var _view: Control = null
var _status: Label = null
var _hints: HBoxContainer = null
var _cursor_layer: Control = null
var _keyboard: Keyboard = null
var _menu: Control = null
var _keyboard_purpose := "page"
var _address: Label = null
var _last_error := ""
var _tabs: Array[Control] = []
var _library: Dictionary = {"bookmarks": [], "history": []}
var LIBRARY_PATH := "user://browser-library.json"
const MAX_TABS := 8
var _picker: Control = null
var _picker_view: Control = null
var _dialog_view: Control = null
var _launch_suspended := false
var return_label := "Close browser"
var _page_popup_open := false
var _chrome: BrowserChrome
var _controls_active := false
var _page_bounds := Rect2()
var _keyboard_rect := Rect2()
var _address_url := ""
var _focus_before_modal: Control = null
var backdrop: Texture2D
var _extension_toolbar: Window
var _extension_pad: Node
var _extension_active := false
var _extension_overlay: ColorRect
var _extension_panel_handle := 0

var _scroll_dir := 0
var _scroll_clock := 0.0
var _stick_scroll_remainder := Vector2.ZERO

## Where this screen was opened FROM, for the one sentence the status line shows
## before anything has loaded. Set by the caller through open_url.
var _opening_title := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	if backdrop != null:
		var art := TextureRect.new()
		art.texture = backdrop
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(1, 1, 1, 0.18)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
	_view = _build_view()
	_tabs.append(_view)
	LIBRARY_PATH = Profiles.personal_path("browser-library.json", ProjectSettings.globalize_path("user://browser-library.json"))
	DirAccess.make_dir_recursive_absolute(LIBRARY_PATH.get_base_dir())
	if FileAccess.file_exists(LIBRARY_PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIBRARY_PATH))
		if saved is Dictionary:
			for key in ["bookmarks", "history"]:
				if saved.get(key) is Array:
					_library[key] = saved[key]
	add_child(_view)

	# The cursor and the chrome ride above the page, in their own layer, so the
	# page cannot paint over them.
	_cursor_layer = Control.new()
	_cursor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cursor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.draw.connect(_draw_cursor)
	add_child(_cursor_layer)

	add_child(_build_chrome())
	resized.connect(_layout_browser)
	_layout_browser.call_deferred()
	show_start_page()

	set_process(true)
	set_process_unhandled_input(true)
	ShellLog.info("browser screen up")
	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)
	Launcher.minimized.connect(_on_launch_finished)

func _on_launch_started(_entry: Dictionary) -> void:
	if visible:
		_launch_suspended = true
		hide()
		set_process_unhandled_input(false)

func _on_launch_finished(_entry: Dictionary) -> void:
	if _launch_suspended:
		_launch_suspended = false
		show()
		set_process_unhandled_input(_keyboard == null and _menu == null and _picker == null)

func suspend_surface() -> void:
	_close_extension_window()
	_close_keyboard()
	_close_menu()
	_cancel_picker()
	if is_instance_valid(_dialog_view):
		_dialog_view.respond_script_dialog(false, "")
	_dialog_view = null
	_scroll_dir = 0
	_launch_suspended = false
	hide()
	set_process_unhandled_input(false)

func _new_tab(url: String = "") -> void:
	if _tabs.size() >= MAX_TABS:
		_last_error = "Eight tabs are open. Close a tab to open another."
		_refresh_status()
		return
	var view := _build_view()
	_tabs.append(view)
	add_child(view)
	move_child(view, get_children().find(_cursor_layer))
	view.set_meta("start_page", url.is_empty())
	_activate_tab(view)
	if url.is_empty(): show_start_page()
	else: open_url(url)

func _activate_tab(view: Control) -> void:
	_close_keyboard()
	_view.hide()
	_view = view
	_view.visible = not _is_start_page()
	_field_context = {}
	_opening_title = view.get_page_title() if view.has_method("get_page_title") else ""
	_last_error = ""
	if view.has_method("get_page_url"): _on_url_changed(view.get_page_url())
	_refresh_status()
	_refresh_hints()
	_layout_browser()
	_refresh_chrome()
	if _is_start_page(): _focus_controls(_chrome.search)
	else: _focus_page()
	_cursor_layer.queue_redraw()

func _close_tab() -> void:
	if _tabs.size() <= 1:
		show_start_page()
		return
	var old := _view
	_tabs.erase(old)
	_activate_tab(_tabs[0])
	for download: Dictionary in _downloads.values():
		if download.get("view") == old and download.state == "downloading":
			download.state = "cancelled"
	remove_child(old)
	old.queue_free()
	_refresh_chrome()

func _show_list(purpose: String, title: String, items: Array, note: String = "") -> void:
	_menu_purpose = purpose
	_scroll_dir = 0
	_remember_focus()
	_menu = BrowserExtensionMenu.new() if purpose.begins_with("extension") else ListMenu.new()
	_menu.title_text = title
	_menu.items = items
	_menu.note_text = note
	_menu.chosen.connect(_menu_chosen)
	var menu := _menu
	_menu.closed.connect(func():
		if _menu == menu: _dismiss_list())
	add_child(_menu)
	set_process_unhandled_input(false)

func _dismiss_list() -> void:
	var purpose := _menu_purpose
	_close_menu()
	if purpose == "extension_apps": _show_extension_panel()
	if purpose == "dialog" and is_instance_valid(_dialog_view):
		_dialog_view.respond_script_dialog(false, "")
		_dialog_view = null

func _open_tabs() -> void:
	var items: Array = []
	for index in _tabs.size():
		var view := _tabs[index]
		var title: String = view.get_page_title() if view.has_method("get_page_title") else "Browser unavailable"
		if view.get_meta("start_page", false): title = "New tab"
		if title.is_empty(): title = "Loading"
		items.append({"id": "tab:%d" % index, "label": ("Current · " if view == _view else "") + title, "icon": "browser"})
	if _tabs.size() < MAX_TABS:
		items.append({"id": "new", "label": "New tab", "icon": "browser"})
	items.append({"id": "close_tab", "label": "Close current tab" if _tabs.size() > 1 else "Reset current tab", "icon": "close"})
	_show_list("tabs", "Tabs", items, "Closing a tab cancels its unfinished downloads.")

func _save_library() -> void:
	var file := FileAccess.open(LIBRARY_PATH, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(_library))

func _record_history(view: Control, url: String) -> void:
	# Local documents and blank/error surfaces do not expose disk paths in history.
	if not url.to_lower().begins_with("https://") and not url.to_lower().begins_with("http://"): return
	var history: Array = _library.history
	for index in range(history.size() - 1, -1, -1):
		if history[index].get("url") == url: history.remove_at(index)
	history.push_front({"url": url, "title": view.get_page_title()})
	if history.size() > 100: history.resize(100)
	_save_library()
	if _chrome != null: _chrome.refresh_library(_library)

func _toggle_bookmark() -> void:
	if _is_start_page() or not _view.has_method("get_page_url"): return
	var url: String = _view.get_page_url()
	if address_url(url) != url:
		_last_error = "Only internet pages can be bookmarked."
		_refresh_status()
		return
	var bookmarks: Array = _library.bookmarks
	for index in bookmarks.size():
		if bookmarks[index].get("url") == url:
			bookmarks.remove_at(index)
			_save_library()
			_refresh_chrome()
			_chrome.refresh_library(_library)
			return
	bookmarks.append({"url": url, "title": _view.get_page_title()})
	_save_library()
	_refresh_chrome()
	_chrome.refresh_library(_library)

func _open_library(purpose: String) -> void:
	var items: Array = []
	if purpose == "bookmarks" and not _is_start_page() and _view.has_method("get_page_url"):
		var saved := false
		for bookmark: Dictionary in _library.bookmarks:
			if _view.has_method("get_page_url") and bookmark.get("url") == _view.get_page_url(): saved = true
		items.append({"id": "save", "label": "Remove current bookmark" if saved else "Bookmark current page", "icon": "browser"})
	var entries: Array = _library[purpose]
	for index in entries.size():
		var entry: Dictionary = entries[index]
		items.append({"id": "visit:%d" % index, "label": str(entry.get("title", "")) if not str(entry.get("title", "")).is_empty() else str(entry.url), "icon": "browser"})
	if entries.is_empty(): items.append({"id": "empty", "label": "No %s yet" % purpose, "icon": "browser"})
	else: items.append({"id": "clear", "label": "Clear " + purpose, "icon": "close"})
	_show_list(purpose, purpose.capitalize(), items)

func _cancel_picker() -> void:
	if _picker != null:
		if is_instance_valid(_picker_view): _picker_view.respond_file_dialog(PackedStringArray())
		remove_child(_picker)
		_picker.queue_free()
		_picker = null
	_picker_view = null

func _on_file_dialog(request: Dictionary, view: Control) -> void:
	if not visible or _picker != null:
		view.respond_file_dialog(PackedStringArray())
		return
	_close_keyboard()
	_close_menu()
	_remember_focus()
	# Files owns the controller picker and its filesystem policy.
	_picker = load("res://src/files_screen.gd").new()
	_picker_view = view
	_picker.picker_mode = true
	_picker.picker_title = str(request.get("title", "Choose file"))
	_picker.picker_multiple = request.get("multiple", false)
	var extensions := PackedStringArray()
	for extension: String in request.get("extensions", PackedStringArray()):
		if extension.begins_with("."): extensions.append(extension.trim_prefix(".").to_lower())
	_picker.picker_extensions = extensions
	_picker.files_picked.connect(func(paths: PackedStringArray):
		if is_instance_valid(view): view.respond_file_dialog(paths)
		_picker_view = null
		_finish_picker.call_deferred(), CONNECT_ONE_SHOT)
	add_child(_picker)
	set_process_unhandled_input(false)

func _finish_picker() -> void:
	_cancel_picker()
	set_process_unhandled_input(true)
	_restore_focus()

func _on_script_dialog(request: Dictionary, view: Control) -> void:
	if not visible or _dialog_view != null:
		view.respond_script_dialog(false, "")
		return
	_close_keyboard()
	_close_menu()
	_dialog_view = view
	if request.type == "prompt":
		_keyboard_purpose = "prompt"
		_keyboard = Keyboard.new()
		_keyboard.title_text = str(request.message).left(180)
		_keyboard.masked = false
		_keyboard.initial_text = str(request.get("default", ""))
		_keyboard.submitted.connect(_on_typed)
		_keyboard.cancelled.connect(func():
			_close_keyboard()
			if is_instance_valid(_dialog_view): _dialog_view.respond_script_dialog(false, "")
			_dialog_view = null)
		_mount_keyboard()
	else:
		_show_list("dialog", "Website message", [{"id": "accept", "label": "OK", "icon": "check"}, {"id": "cancel", "label": "Cancel", "icon": "close"}], str(request.origin).left(160) + "\n" + str(request.message).left(500))


## The engine, or the honest sentence when there is none.
##
## MowserView is a GDExtension class, so a build whose image is missing
## libmowser.so does not merely fail to browse -- the class does not exist and
## naming it is a script error. That is checked rather than assumed: the shell
## must still come up on a machine whose browser payload did not land, exactly
## as it comes up with no network and no Steam.
func _build_view() -> Control:
	if not ClassDB.class_exists("MowserView"):
		ShellLog.error("MowserView is not registered -- the browser engine is not in this image")
		return _build_engine_missing("the browser is not installed in this image")

	var view: Control = ClassDB.instantiate("MowserView")
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_downloads(view)
	view.page_started.connect(func(url: String):
		if view == _view: _on_page_started(url))
	view.page_finished.connect(func(url: String, status: int):
		_record_history(view, url)
		if view == _view: _on_page_finished(url, status))
	view.page_failed.connect(func(url: String, reason: String):
		if view == _view: _on_page_failed(url, reason))
	view.title_changed.connect(func(title: String):
		if view == _view: _on_title_changed(title)
		else: _refresh_chrome())
	view.url_changed.connect(func(url: String):
		if view == _view: _on_url_changed(url))
	if view.has_signal("keyboard_context_changed"):
		view.keyboard_context_changed.connect(func(context: Dictionary):
			if view == _view and visible: _on_keyboard_context(context))
	if view.has_signal("file_dialog_requested"):
		view.file_dialog_requested.connect(_on_file_dialog.bind(view))
	if view.has_signal("script_dialog_requested"):
		view.script_dialog_requested.connect(_on_script_dialog.bind(view))
	if view.has_signal("popup_requested"):
		view.popup_requested.connect(func(url: String):
			if visible: _new_tab(url))
	return view


static func download_directory() -> String:
	# The player-owned installer worker and FDM accept this exact root. XDG can
	# return HOME when user-dirs.dirs is absent, or a custom directory outside it.
	return OS.get_environment("HOME").path_join("Downloads")


func _configure_downloads(view: Control) -> void:
	if view.has_method("set_download_directory"):
		view.set_download_directory(download_directory())
		view.download_updated.connect(_on_download_updated.bind(view))


## A page-shaped panel saying why there is no page. Same first-class-render rule
## the storefront grid follows: every state draws something that explains
## itself, and a black rectangle explains nothing.
func _build_engine_missing(reason: String) -> Control:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = "The browser cannot open -- %s." % reason
	label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	label.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 48
	label.offset_right = -48
	label.offset_top = 32
	label.offset_bottom = -32
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


func _build_chrome() -> Control:
	_chrome = BrowserChrome.new()
	_chrome.action_requested.connect(_chrome_action)
	_chrome.url_requested.connect(open_url)
	# The child builds its controls in _ready, after the caller parents it.
	_chrome.ready.connect(func():
		_address = _chrome.address
		_status = _chrome.status
		_hints = _chrome.hints
		_chrome.refresh_library(_library))
	return _chrome

func _is_start_page() -> bool:
	return _view != null and _view.get_meta("start_page", false)

func show_start_page() -> void:
	_close_keyboard()
	_view.set_meta("start_page", true)
	_view.hide()
	_address_url = ""
	_address.text = "Website or search"
	_last_error = ""
	_refresh_chrome()
	_refresh_status()
	_focus_controls(_chrome.search)

func _refresh_chrome() -> void:
	if _chrome == null or not _chrome.is_node_ready(): return
	_chrome.refresh_tabs(_tabs, _view)
	var saved := false
	for entry: Dictionary in _library.bookmarks:
		if entry.get("url") == _address_url: saved = true
	var forward: bool = not _is_start_page() and _view.has_method("can_go_forward") and _view.can_go_forward()
	var loading: bool = not _is_start_page() and _view.has_method("is_loading") and _view.is_loading()
	_chrome.refresh_navigation(_can_go_back(), forward, loading, saved, _is_start_page())
	_cursor_layer.visible = not _controls_active and not _is_start_page() and _keyboard == null
	_refresh_hints()

func _chrome_action(action: String) -> void:
	_menu_purpose = "options"
	match action:
		"": return
		"controls":
			_controls_active = true
			_scroll_dir = 0
			_cursor_layer.hide()
			_refresh_hints()
		"new": _new_tab()
		"page": _focus_page()
		"save": _toggle_bookmark()
		"options": _open_menu()
		"reload":
			if _view.has_method("is_loading") and _view.is_loading():
				_menu_chosen("stop")
			else: _menu_chosen("reload")
		_:
			_menu_purpose = "options"
			_menu_chosen(action)

func _focus_controls(target: Control = null) -> void:
	_controls_active = true
	_scroll_dir = 0
	_stick_scroll_remainder = Vector2.ZERO
	if _click_held: _click(false)
	if target == null: target = _chrome.address_button
	target.grab_focus()
	_cursor_layer.hide()
	_refresh_hints()

func _focus_page() -> void:
	if _is_start_page():
		_focus_controls(_chrome.search)
		return
	_controls_active = false
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null: owner.release_focus()
	_cursor_layer.show()
	_refresh_hints()

func _remember_focus() -> void:
	if not is_inside_tree(): return
	_focus_before_modal = get_viewport().gui_get_focus_owner()
	if _focus_before_modal != null: _focus_before_modal.release_focus()

func _restore_focus() -> void:
	if not is_inside_tree() or not visible or _keyboard != null or _menu != null or _picker != null: return
	if _controls_active:
		_focus_controls(_focus_before_modal if is_instance_valid(_focus_before_modal) and _focus_before_modal.is_visible_in_tree() else null)
	else: _focus_page()
	_focus_before_modal = null

func resume_surface() -> void:
	show()
	set_process_unhandled_input(true)
	_restore_focus()

func _layout_browser() -> void:
	if _chrome == null or not _chrome.is_node_ready(): return
	_chrome._layout()
	_page_bounds = _chrome.page_rect()
	for view in _tabs:
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.position = _page_bounds.position
		view.size = _page_bounds.size
	_cursor_layer.queue_redraw()


## THE HINT ROW SAYS WHAT B DOES RIGHT NOW, and it changes, because B does two
## things: the page's history while there is any, and closing this screen when
## there is not. Advertising one word for both would make the button a surprise
## exactly once per visit -- which is the visit where somebody loses a checkout.
func _refresh_hints() -> void:
	if _hints != null:
		_chrome.refresh_hints(_controls_active, _is_page_popup_open(), _can_go_back(), _is_start_page())


func _can_go_back() -> bool:
	return _view != null and not _is_start_page() and _view.has_method("can_go_back") and _view.can_go_back()

func _is_page_popup_open() -> bool:
	return _view != null and _view.has_method("is_popup_open") and _view.is_popup_open()


## Open a URL, with a human name for it to show while it loads. The name is the
## caller's -- the store knows the game's title long before the page does -- and
## a status line that said the raw URL would be showing somebody a query string
## on a television.
func open_url(url: String, title: String = "") -> void:
	_opening_title = title
	_last_error = ""
	# AN EMPTY URL IS A CALLER BUG AND MUST SAY SO. Handed one, the engine
	# stays on about:blank and renders a blank page -- indistinguishable from a
	# page that failed to load, which is exactly how a broken file_url() hid
	# behind a log line that only ever printed the title.
	if url.is_empty():
		ShellLog.error("browser asked to open an empty URL; nothing to show")
		if _status != null:
			_status.text = "There is nothing to open here"
			_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
		return
	_view.set_meta("start_page", false)
	_view.show()
	_on_url_changed(url)
	_layout_browser()
	_refresh_chrome()
	_focus_page()
	if _view != null and _view.has_method("load_url"):
		_view.load_url(url)
	_refresh_status()
	# THE URL, not just the title. The title is what a person reads; the URL is
	# what the machine was actually told to do, and they are only the same when
	# nothing has gone wrong.
	ShellLog.info("browser opening %s%s"
		% [url, "" if title.is_empty() else " for %s" % title])


func _refresh_status() -> void:
	if _status == null:
		return
	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	if not _last_error.is_empty():
		_status.text = _last_error
		_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
		return
	if _view != null and _view.has_method("is_loading") and _view.is_loading() and not _is_start_page():
		_status.text = "%s -- %s" % [STATUS_LOADING, _opening_title] \
			if not _opening_title.is_empty() else STATUS_LOADING
		_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		return
	# ONCE A PAGE IS UP THE LINE GOES QUIET. The page is its own title, drawn at
	# full size by the site itself, and a shell caption repeating it would be
	# the storefront's "caption on a photograph of itself" all over again.
	_status.text = _download_summary if not _download_summary.is_empty() else STATUS_READY


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## The stick, polled rather than evented, for pad_keys.gd's reason: a stick held
## at half tilt produces no further events, and a cursor that only moves when
## somebody wiggles it is a broken mouse.
func _process(delta: float) -> void:
	_sync_extension_window()
	if _extension_active: return
	if _chrome != null: _chrome.refresh_status()
	var popup_open := _is_page_popup_open()
	if _page_popup_open != popup_open:
		_page_popup_open = popup_open
		_refresh_hints()
	if not visible or _controls_active or _keyboard != null or _menu != null or _picker != null or _view == null or not _view.has_method("move_pointer"):
		_stick_scroll_remainder = Vector2.ZERO
		return

	var dx := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	var dy := Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	var tilt := Vector2(dx, dy)
	if tilt.length() > 1.0:
		tilt = tilt.normalized()
	if tilt.length() > 0.0:
		# Squared response: a slow edge without costing the fast middle, the
		# same curve the pad bridge uses.
		var step: Vector2 = tilt * pow(tilt.length(), POINTER_CURVE - 1.0) * POINTER_SPEED * delta
		_view.move_pointer(step)
		if _cursor_layer != null:
			_cursor_layer.queue_redraw()

	if _scroll_dir != 0:
		_scroll_clock += delta
		if _scroll_clock >= SCROLL_INTERVAL:
			_scroll_clock = 0.0
			_view.scroll(Vector2(0, SCROLL_STEP * _scroll_dir))

	var pad := PlayerOne.device
	if pad < 0 or not _view.has_method("scroll"):
		_stick_scroll_remainder = Vector2.ZERO
		return
	var scroll_tilt := _shape_scroll_stick(Vector2(
		PlayerOne.axis(JOY_AXIS_RIGHT_X),
		PlayerOne.axis(JOY_AXIS_RIGHT_Y)
	))
	# CEF wheel deltas run opposite to the direction the viewport travels.
	_stick_scroll_remainder -= scroll_tilt * STICK_SCROLL_SPEED * delta
	var stick_step := Vector2i(_stick_scroll_remainder)
	if stick_step != Vector2i.ZERO:
		_stick_scroll_remainder -= Vector2(stick_step)
		_view.scroll(Vector2(stick_step))


static func _shape_scroll_stick(value: Vector2) -> Vector2:
	var magnitude := minf(value.length(), 1.0)
	if magnitude <= STICK_SCROLL_DEADZONE:
		return Vector2.ZERO
	var strength := (magnitude - STICK_SCROLL_DEADZONE) / (1.0 - STICK_SCROLL_DEADZONE)
	return value.normalized() * pow(strength, STICK_SCROLL_CURVE)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _keyboard != null or _menu != null or _picker != null:
		return
	if event.is_action_pressed("ui_shell_home"):
		get_viewport().set_input_as_handled()
		closed.emit()
		return
	if event.is_action_pressed("ui_shell_x"):
		get_viewport().set_input_as_handled()
		_open_address()
		return
	if event.is_action_pressed("ui_shell_options"):
		get_viewport().set_input_as_handled()
		_open_menu()
		return
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_STICK and event.pressed:
		get_viewport().set_input_as_handled()
		if _controls_active: _focus_page()
		else: _focus_controls()
		return
	if event.is_action_pressed("ui_cancel") and _controls_active:
		get_viewport().set_input_as_handled()
		if _is_start_page(): closed.emit()
		else: _focus_page()
		return
	if event is InputEventMouseMotion and not _is_start_page() and _view.get_global_rect().has_point(event.position) and _view.has_method("set_pointer"):
		if _controls_active: _focus_page()
		_view.set_pointer(event.position - _view.global_position)
		_cursor_layer.queue_redraw()
		return
	if event is InputEventMouseButton and not _is_start_page() and _view.get_global_rect().has_point(event.position) and _view.has_method("set_pointer"):
		if _controls_active: _focus_page()
		get_viewport().set_input_as_handled()
		_view.set_pointer(event.position - _view.global_position)
		if event.button_index == MOUSE_BUTTON_LEFT: _click(event.pressed)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_view.scroll(Vector2(0, 120 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -120))
		return
	if _controls_active: return

	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_click(true)
		return
	if event.is_action_released("ui_accept"):
		get_viewport().set_input_as_handled()
		if _click_held: _click(false)
		return

	if event.is_action_pressed("ui_shell_y"):
		get_viewport().set_input_as_handled()
		_open_keyboard()
		return

	# The shoulders scroll, and they arrive as raw buttons because the shell's
	# nine actions deliberately do not cover them -- pad_keys.gd's own note.
	if event is InputEventJoypadButton:
		var direction := 0
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			direction = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			direction = 1
		if direction != 0:
			get_viewport().set_input_as_handled()
			if event.pressed:
				_scroll_dir = direction
				_scroll_clock = 0.0
				if _view != null and _view.has_method("scroll"):
					_view.scroll(Vector2(0, SCROLL_STEP * direction))
			elif _scroll_dir == direction:
				_scroll_dir = 0
			return

	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _is_page_popup_open():
		_view.send_editing_key("Escape")
		return
	# B IS THE PAGE'S HISTORY FIRST. See the header: this is the one button in
	# the shell that means two things, because a back button that closed the
	# browser from three pages deep would be the wrong one every time.
	if _can_go_back():
		_view.go_back()
		_refresh_hints()
		ShellLog.info("browser went back")
		return
	closed.emit()


func _click(pressed: bool) -> void:
	_click_held = pressed
	if _view != null and _view.has_method("click"):
		_view.click(1, pressed)
	if not pressed:
		# A click is the most likely thing to have started a navigation, so the
		# hint row's B word is re-derived on the release rather than waiting for
		# a load to report.
		_refresh_hints()
		if not _controls_active and _field_context.get("editable", false):
			_open_keyboard.call_deferred()


## The cursor, drawn by the shell over the page. See CURSOR_RADIUS for why it is
## a ring: this has to be findable over arbitrary content nobody here chose.
func _draw_cursor() -> void:
	if _controls_active or _is_start_page() or _view == null or not _view.has_method("get_pointer"):
		return
	var at: Vector2 = _view.get_pointer() + _view.position
	_cursor_layer.draw_circle(at, CURSOR_RADIUS + CURSOR_OUTLINE, Color(0, 0, 0, 0.65))
	_cursor_layer.draw_circle(at, CURSOR_RADIUS, TvTheme.TEXT_PRIMARY)


# ---------------------------------------------------------------------------
# Typing
# ---------------------------------------------------------------------------

var _click_held := false
var _field_context: Dictionary = {}
var _page_done_action := ""

func _input(event: InputEvent) -> void:
	if _extension_active:
		if event.is_action_pressed("ui_shell_home"):
			_close_extension_window()
			get_viewport().set_input_as_handled()
		return
	# Leave the page clickable around the floating panel, including when moving
	# directly from one editor to another. Keyboard buttons retain their own GUI input.
	if not visible or _keyboard == null or _keyboard_purpose != "page":
		return
	if not event is InputEventMouseButton and not event is InputEventMouseMotion:
		return
	if _keyboard.get_panel_rect().has_point(event.position):
		return
	if _view.get_global_rect().has_point(event.position) and _view.has_method("set_pointer"):
		_view.set_pointer(event.position - _view.global_position)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.pressed)
		elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_view.scroll(Vector2(0, 120 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -120))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_close_keyboard()

func _on_keyboard_context(context: Dictionary) -> void:
	if str(context.get("type", "")).is_empty():
		context["type"] = "text"
	var same_field := context == _field_context
	_field_context = context
	if same_field and _keyboard != null and _keyboard_purpose == "page":
		return
	if _keyboard != null and _keyboard_purpose == "page":
		_close_keyboard()
	if context.get("editable", false) and not _controls_active and _keyboard == null and _menu == null:
		_open_keyboard.call_deferred()

func _open_keyboard() -> void:
	if not visible or _click_held or _keyboard != null or _menu != null or _picker != null or _controls_active or _view == null or not _view.has_method("type_text"):
		return
	if not _field_context.get("editable", false):
		_status.text = "Select a text field first, then press Triangle to type."
		return
	_keyboard_purpose = "page"
	_scroll_dir = 0
	_keyboard = Keyboard.new()
	var type := str(_field_context.get("type", "text")).to_lower()
	var mode := str(_field_context.get("mode", "")).to_lower()
	_keyboard.input_context = mode if not mode.is_empty() else type
	_keyboard.masked = type == "password"
	_keyboard.live_input = true
	var titles := {"password": "Password", "email": "Email address", "url": "Website", "search": "Search", "tel": "Phone number", "number": "Number", "numeric": "Number", "decimal": "Number"}
	_keyboard.title_text = str(titles.get(type, titles.get(mode, "Type")))
	var label := str(_field_context.get("label", "")).strip_edges().replace("\n", " ")
	if not label.is_empty():
		_keyboard.title_text += " · " + label
	_page_done_action = ""
	var action := str(_field_context.get("action", ""))
	if type == "search" or mode == "search" or action == "search":
		_keyboard.done_label = "Search"
		_page_done_action = "Return"
	elif action == "next":
		_keyboard.done_label = "Next"
		_page_done_action = "Tab"
	_keyboard.text_inserted.connect(_view.type_text)
	_keyboard.editing_key.connect(_view.send_editing_key)
	_keyboard.submitted.connect(_on_typed)
	_keyboard.cancelled.connect(_close_keyboard)
	_mount_keyboard()

func _mount_keyboard() -> void:
	# The document keeps its full width beneath the floating keyboard.
	_hints.hide()
	_cursor_layer.hide()
	_remember_focus()
	add_child(_keyboard)
	if _keyboard.has_signal("panel_moved"):
		_keyboard.panel_moved.connect(_keyboard_moved)
	_keyboard_moved(_keyboard.get_panel_rect())
	set_process_unhandled_input(false)
	_reveal_field_later()

func _keyboard_moved(rect: Rect2) -> void:
	_keyboard_rect = rect
	_reveal_field_later()

func _reveal_field_later() -> void:
	await get_tree().create_timer(0.15).timeout
	if _keyboard != null and _keyboard_purpose == "page" and _view.has_method("reveal_focused_field"):
		_view.reveal_focused_field(Rect2(_keyboard_rect.position - _view.global_position, _keyboard_rect.size))

func _on_typed(text: String) -> void:
	var purpose := _keyboard_purpose
	var action := _page_done_action
	_close_keyboard()
	if purpose == "page":
		if not action.is_empty():
			_view.send_editing_key(action)
		return
	if purpose == "prompt":
		if is_instance_valid(_dialog_view):
			_dialog_view.respond_script_dialog(true, text)
		_dialog_view = null
		return
	if text.is_empty():
		return
	var url := address_url(text)
	if url.is_empty():
		_last_error = "Enter a website address or search words."
		_refresh_status()
	else:
		open_url(url)

func _close_keyboard() -> void:
	if _keyboard == null:
		return
	var keyboard := _keyboard
	_keyboard = null
	remove_child(keyboard)
	keyboard.queue_free()
	_keyboard_rect = Rect2()
	_layout_browser()
	_hints.show()
	_restore_focus()
	set_process_unhandled_input(true)


# ---------------------------------------------------------------------------
# Engine callbacks
# ---------------------------------------------------------------------------

func _on_page_started(_url: String) -> void:
	_field_context = {}
	if _keyboard != null and _keyboard_purpose == "page":
		_close_keyboard()
	_last_error = ""
	_refresh_status()
	_refresh_hints()
	_refresh_chrome()


func _on_page_finished(_url: String, http_status: int) -> void:
	if http_status >= 400:
		_last_error = "Website returned HTTP %d. Options → Reload to retry." % http_status
	_refresh_status()
	_refresh_hints()
	_refresh_chrome()
	ShellLog.info("browser page finished with status %d" % http_status)


## A LOAD FAILURE IS THIS SCREEN'S TO RENDER, not the engine's. Chromium has its
## own error pages and they are somebody else's design, in somebody else's
## typeface, telling a person on a sofa to check their proxy settings. The
## status line says what happened in this shell's own words instead.
func _on_page_failed(_url: String, reason: String) -> void:
	_last_error = "That page did not open — %s. Options → Reload to retry." % reason
	if _status != null:
		_status.text = _last_error
		_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	_refresh_hints()
	ShellLog.warn("browser page failed: %s" % reason)
	_refresh_chrome()


func _on_title_changed(title: String) -> void:
	# Kept for the status line's loading sentence, which prefers the caller's
	# name but falls back to the page's own once it has one.
	if _opening_title.is_empty():
		_opening_title = title
	_refresh_chrome()


static func address_url(text: String) -> String:
	var value := text.strip_edges()
	if value.is_empty():
		return ""
	var lower := value.to_lower()
	if "\n" in value or "\r" in value or "\t" in value:
		return ""
	if lower.begins_with("https://") or lower.begins_with("http://"):
		return value
	if "://" in value or lower.begins_with("javascript:") or lower.begins_with("data:") or lower.begins_with("file:") or lower.begins_with("about:"):
		return ""
	if not " " in value and ("." in value or value.begins_with("localhost")):
		return "https://" + value
	return "https://duckduckgo.com/?q=" + value.uri_encode()


func _on_url_changed(url: String) -> void:
	_address_url = url
	if _address != null:
		_address.text = "Website or search" if _is_start_page() else url
	_refresh_chrome()


func _open_address() -> void:
	if _keyboard != null:
		return
	_keyboard_purpose = "address"
	_scroll_dir = 0
	_keyboard = Keyboard.new()
	_keyboard.title_text = "Website or search"
	_keyboard.masked = false
	_keyboard.input_context = "url"
	_keyboard.initial_text = "" if _is_start_page() else _address_url
	_keyboard.done_label = "Go"
	_keyboard.submitted.connect(_on_typed)
	_keyboard.cancelled.connect(_close_keyboard)
	_mount_keyboard()


func _open_menu() -> void:
	if _is_page_popup_open(): _view.send_editing_key("Escape")
	_menu_purpose = "options"
	if _menu != null:
		return
	_scroll_dir = 0
	_remember_focus()
	_menu = ListMenu.new()
	_menu.title_text = "Browser"
	_menu.items = [
		{"id": "address", "label": "Website or search", "icon": "browser"},
		{"id": "tabs", "label": "Tabs (%d/%d)" % [_tabs.size(), MAX_TABS], "icon": "browser"},
		{"id": "bookmarks", "label": "Bookmarks", "icon": "browser"},
		{"id": "history", "label": "History", "icon": "browser"},
		{"id": "downloads", "label": "Downloads", "icon": "folder"},
		{"id": "extensions", "label": "Extensions", "icon": "puzzle"},
		{"id": "enter", "label": "Press Enter", "icon": "keyboard"},
		{"id": "backspace", "label": "Backspace", "icon": "keyboard"},
		{"id": "back", "label": "Back", "icon": "arrow-left"},
		{"id": "forward", "label": "Forward", "icon": "caret-right"},
		{"id": "reload", "label": "Reload", "icon": "restart"},
		{"id": "stop", "label": "Stop loading", "icon": "close"},
		{"id": "close", "label": return_label, "icon": "close"},
	]
	_menu.chosen.connect(_menu_chosen)
	var menu := _menu
	_menu.closed.connect(func():
		if _menu == menu: _close_menu())
	add_child(_menu)
	set_process_unhandled_input(false)


func _close_menu() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.queue_free()
		_menu = null
	set_process_unhandled_input(visible and _keyboard == null and _picker == null)
	_restore_focus()


func _menu_chosen(id: String) -> void:
	var purpose := _menu_purpose
	_close_menu()
	if purpose.begins_with("extension"):
		_extension_chosen(purpose, id)
		return
	if purpose == "tabs":
		if id == "new": _new_tab()
		elif id == "close_tab": _close_tab()
		elif id.begins_with("tab:"): _activate_tab(_tabs[id.trim_prefix("tab:").to_int()])
		return
	if purpose in ["bookmarks", "history"]:
		if id == "save": _toggle_bookmark()
		elif id == "clear":
			_library[purpose] = []
			_save_library()
			_chrome.refresh_library(_library)
		elif id.begins_with("visit:"):
			open_url(str(_library[purpose][id.trim_prefix("visit:").to_int()].url))
		return
	if purpose == "dialog":
		if is_instance_valid(_dialog_view):
			_dialog_view.respond_script_dialog(id == "accept", "")
		_dialog_view = null
		return
	match id:
		"address": _open_address()
		"tabs": _open_tabs()
		"bookmarks", "history": _open_library(id)
		"downloads": _open_downloads()
		"extensions": _open_extensions()
		"close": closed.emit()
		"enter", "backspace":
			if _view != null and _view.has_method("send_editing_key"):
				_view.send_editing_key("Return" if id == "enter" else "BackSpace")
		_:
			var method := {"back": "go_back", "forward": "go_forward", "reload": "reload", "stop": "stop_loading"}.get(id, "") as String
			if _view != null and _view.has_method(method):
				_last_error = ""
				_view.call(method)
				_refresh_chrome()


func _open_extensions() -> void:
	if _menu != null: return
	_extension_chosen("extensions", "manage")

func _extension_chosen(_purpose: String, id: String) -> void:
	if _purpose == "extension_apps":
		for entry: Dictionary in BrowserExtensions.installed_entries():
			if entry.id == id and _view.has_method("open_extension_page"):
				_view.open_extension_page(str(entry.url))
		_show_extension_panel()
		return
	if id not in ["store", "manage"]: return
	_set_extension_panel_rect()
	if not _view.has_method("open_extensions") or not _view.open_extensions(id == "manage"):
		_show_list("extension_error", "Extensions unavailable", [{"id": "dismiss", "label": "Close", "icon": "close"}], "Update MarwanOS to install extensions from the Chrome Web Store.")
		return
	_sync_extension_window()

func _sync_extension_window() -> void:
	var active: bool = _view != null and _view.has_method("is_extension_window_open") and _view.is_extension_window_open()
	if active and is_instance_valid(_extension_pad):
		var blocked := TextInput.is_open() or _menu != null or _picker != null
		if _extension_pad.paused != blocked: _extension_pad.set_paused(blocked)
	if active: _attach_extension_panel()
	if active == _extension_active: return
	_extension_active = active
	_scroll_dir = 0
	if active:
		Kiosk.set_native_pointer_visible(true)
		_close_keyboard()
		_remember_focus()
		set_process_unhandled_input(false)
		_cursor_layer.hide()
		_extension_overlay = ColorRect.new()
		_extension_overlay.color = Color(BrowserChrome.WINDOW, 0.5)
		_extension_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_extension_overlay.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed: _close_extension_window())
		add_child(_extension_overlay)
		if DisplayServer.get_name() == "X11":
			_extension_toolbar = ExtensionToolbar.new()
			_extension_toolbar.visible = false
			_extension_toolbar.command_requested.connect(_extension_command)
			add_child(_extension_toolbar)
			_extension_toolbar.show_toolbar()
			_extension_pad = PadKeys.new()
			_extension_pad.mode = "pointer"
			_extension_pad.pointer_bounds = ExtensionToolbar.panel_rect(Rect2i(DisplayServer.screen_get_position(), DisplayServer.screen_get_size()))
			add_child(_extension_pad)
	else:
		Kiosk.set_native_pointer_visible(false)
		if TextInput.is_open(): TextInput.close()
		if is_instance_valid(_extension_toolbar): _extension_toolbar.queue_free()
		if is_instance_valid(_extension_pad): _extension_pad.queue_free()
		_extension_toolbar = null
		_extension_pad = null
		if is_instance_valid(_extension_overlay): _extension_overlay.queue_free()
		_extension_overlay = null
		_extension_panel_handle = 0
		DisplayServer.window_move_to_foreground()
		if _view.has_method("get_page_url"):
			var url: String = _view.get_page_url()
			if url.is_empty() or url == "about:blank": show_start_page()
			else: _on_url_changed(url)
		_refresh_status()
		set_process_unhandled_input(visible and _menu == null and _picker == null)
		_restore_focus()

func _extension_command(command: String) -> void:
	if command == "installed":
		if is_instance_valid(_extension_pad): _extension_pad.set_paused(true)
		_view.extension_command("hide")
		if is_instance_valid(_extension_toolbar): _extension_toolbar.hide()
		var items := BrowserExtensions.installed_entries()
		_show_list("extension_apps", "Open extension", items if not items.is_empty() else [{"id": "dismiss", "label": "Close"}], "" if not items.is_empty() else "No enabled extensions with a setup page. Install or enable an extension in Manage.")
		DisplayServer.window_move_to_foreground()
		return
	if command != "type":
		_view.extension_command(command)
		return
	if not _view.has_method("extension_type_text"): return
	if is_instance_valid(_extension_pad): _extension_pad.set_paused(true)
	TextInput.open_browser_editor(func(edit: Dictionary):
		if not _extension_active: return
		if edit.kind == "text": _view.extension_type_text(str(edit.text))
		elif edit.kind == "key": _view.extension_editing_key(str(edit.key)))

func _show_extension_panel() -> void:
	if not _extension_active: return
	_view.extension_command("show")
	if is_instance_valid(_extension_toolbar): _extension_toolbar.show_toolbar()
	set_process_unhandled_input(false)

func _set_extension_panel_rect() -> void:
	if _view == null or not _view.has_method("set_extension_panel_rect"): return
	var panel := ExtensionToolbar.panel_rect(Rect2i(DisplayServer.screen_get_position(), DisplayServer.screen_get_size()))
	_view.set_extension_panel_rect(Rect2(panel.position + Vector2i(0, ExtensionToolbar.HEIGHT), Vector2i(panel.size.x, maxi(1, panel.size.y - ExtensionToolbar.HEIGHT))))

func _attach_extension_panel() -> void:
	if not _view.has_method("get_extension_panel_handle"): return
	var handle: int = _view.get_extension_panel_handle()
	if handle <= 0 or handle == _extension_panel_handle: return
	if DisplayServer.get_name() == "X11" and OS.get_environment("MARWANOS_COMPOSITOR") != "x11":
		var output: Array = []
		if OS.execute("/usr/bin/timeout", ["1", "xprop", "-id", str(handle), "-f", "GAMESCOPE_EXTERNAL_OVERLAY", "32c", "-set", "GAMESCOPE_EXTERNAL_OVERLAY", "1"], output, true) != 0:
			_view.extension_command("close")
			return
	_extension_panel_handle = handle
	_set_extension_panel_rect()
	var panel := ExtensionToolbar.panel_rect(Rect2i(DisplayServer.screen_get_position(), DisplayServer.screen_get_size()))
	var target := panel.position + Vector2i(panel.size.x / 2, ExtensionToolbar.HEIGHT + 48)
	OS.create_process("xdotool", ["mousemove", "--", str(target.x), str(target.y)])

func _close_extension_window() -> void:
	if _view != null and _view.has_method("extension_command"):
		_view.extension_command("close")
	_sync_extension_window()

var _downloads: Dictionary = {}
var _download_summary := ""
var _menu_purpose := "options"

func _on_download_updated(download: Dictionary, view: Control = null) -> void:
	Downloads.browser_updated(download, view)
	download["view"] = view
	_downloads[download.id] = download
	var name := str(download.get("name", "download"))
	match str(download.state):
		"complete":
			_download_summary = "Saved to Downloads: " + name
			DownloadInstall.completed(str(download.get("path", "")))
		"cancelled": _download_summary = "Download cancelled: " + name
		"failed": _download_summary = name + " — " + str(download.detail)
		_:
			var total := int(download.get("total", 0))
			var progress := "%d%%" % (100 * int(download.received) / total) if total > 0 else String.humanize_size(int(download.received))
			_download_summary = "Downloading %s — %s · Options → Downloads" % [name, progress]
	_refresh_status()

func _open_downloads() -> void:
	if _menu != null or _picker != null: return
	_scroll_dir = 0
	_remember_focus()
	_picker = load("res://src/downloads_screen.gd").new()
	_picker.closed.connect(func(): _finish_picker.call_deferred())
	add_child(_picker)
	set_process_unhandled_input(false)
