extends Control

## THE BROWSER. Not a browser the shell launches -- a browser the shell IS.
##
## Everything on this screen except the page itself is drawn here, in this
## project's theme, by this project's code: the cursor, the status line, the
## hint row, the error sentence. The page is a MowserView, which is Chromium's
## engine rendering off-screen into a texture (see mowser/src/mowser.h). That
## division is the whole point of the owner's ask -- "my own custom made
## chromium that is only the engine inside my launcher" -- and it is why there
## is no address bar here unless this file draws one, no tab strip unless this
## file draws one, and no settings page at all.
##
## WHAT REPLACED WHAT. Zen was a browser with a UI nobody could drive with a
## pad. The Chromium flatpak that replaced it for a day was the same problem
## with the UI hidden rather than absent -- kiosk mode is a flag on somebody
## else's application, one changed default away from a window this machine
## cannot dismiss. This is the third and last answer: the engine is a library,
## and the browser is ours.
##
## THE PAD DRIVES THE PAGE BY METHOD CALL. pad_keys.gd exists because the shell
## could not reach inside a foreign X client, so it spawns an xdotool process
## per event and aims it at whatever gamescope focused. None of that applies to
## a page inside this process: the stick moves a cursor this screen owns, and A
## is one call into the engine at a coordinate in this control's own space. No
## processes, no injection, no guessing which window has focus.
##
## NAVIGATION, and it is the settings list's argument adapted to a surface that
## has no rows: there is nothing focusable on this screen at all. The page is
## not a Control tree the engine's focus can walk, so B is not "up one level" --
## it is the page's own history, and only when the history is empty does it
## close the screen. That is the one place this shell lets a button mean two
## things, and it is what a person expects from a back button in a browser.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Keyboard = preload("res://src/keyboard.gd")
const ListMenu = preload("res://src/list_menu.gd")

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
const LIBRARY_PATH := "user://browser-library.json"
const MAX_TABS := 8
var _picker: Control = null
var _picker_view: Control = null
var _dialog_view: Control = null
var _launch_suspended := false
var return_label := "Close browser"
var _page_popup_open := false

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

	# THE PAGE GETS THE SCREEN, EDGE TO EDGE, and this is the one surface in the
	# shell that does not take the TV-safe inset. A web page is somebody else's
	# layout: insetting it would letterbox every site behind a border while the
	# page's own margins are already inside that, and a checkout's Pay button
	# sitting under a black bar is the failure this whole route exists to avoid.
	# The shell's own furniture below KEEPS the inset, so nothing this file
	# draws lands in the overscan.
	_view = _build_view()
	_tabs.append(_view)
	if FileAccess.file_exists(LIBRARY_PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIBRARY_PATH))
		if saved is Dictionary:
			for key in ["bookmarks", "history"]:
				if saved.get(key) is Array:
					_library[key] = saved[key]
	add_child(_view)
	# THE PRESET IS RE-APPLIED AFTER PARENTING, and it is not superstition.
	# Anchors set on a Control that has no parent yet have nothing to resolve
	# against, so the view can end up in the tree at zero size -- which the
	# engine never notices (it is told a size through GetViewRect and paints
	# happily at the fallback) and which draws as nothing at all. Cheap, and it
	# removes a whole class of "the page is black" from this screen.
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.offset_top = 130
	_view.offset_bottom = -110

	# The cursor and the chrome ride above the page, in their own layer, so the
	# page cannot paint over them.
	_cursor_layer = Control.new()
	_cursor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cursor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.draw.connect(_draw_cursor)
	add_child(_cursor_layer)

	add_child(_build_chrome())

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

func _new_tab(url: String = "https://duckduckgo.com") -> void:
	if _tabs.size() >= MAX_TABS:
		_last_error = "Eight tabs are open. Close a tab to open another."
		_refresh_status()
		return
	var view := _build_view()
	_tabs.append(view)
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_top = 130
	view.offset_bottom = -110
	move_child(view, 1)
	_activate_tab(view)
	open_url(url)

func _activate_tab(view: Control) -> void:
	_close_keyboard()
	_view.hide()
	_view = view
	_view.show()
	_field_context = {}
	_opening_title = view.get_page_title() if view.has_method("get_page_title") else ""
	_last_error = ""
	if view.has_method("get_page_url"): _on_url_changed(view.get_page_url())
	_refresh_status()
	_refresh_hints()
	_cursor_layer.queue_redraw()

func _close_tab() -> void:
	if _tabs.size() <= 1:
		open_url("https://duckduckgo.com")
		return
	var old := _view
	_tabs.erase(old)
	_activate_tab(_tabs[0])
	for download: Dictionary in _downloads.values():
		if download.get("view") == old and download.state == "downloading":
			download.state = "cancelled"
	remove_child(old)
	old.queue_free()

func _show_list(purpose: String, title: String, items: Array, note: String = "") -> void:
	_menu_purpose = purpose
	_scroll_dir = 0
	_menu = ListMenu.new()
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
	if purpose == "dialog" and is_instance_valid(_dialog_view):
		_dialog_view.respond_script_dialog(false, "")
		_dialog_view = null

func _open_tabs() -> void:
	var items: Array = []
	for index in _tabs.size():
		var view := _tabs[index]
		var title: String = view.get_page_title() if view.has_method("get_page_title") else "Browser unavailable"
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

func _toggle_bookmark() -> void:
	if not _view.has_method("get_page_url"): return
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
			return
	bookmarks.append({"url": url, "title": _view.get_page_title()})
	_save_library()

func _open_library(purpose: String) -> void:
	var items: Array = []
	if purpose == "bookmarks":
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
		if view == _view: _on_title_changed(title))
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
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


## The shell's own furniture: a status line and the hint row, both inside the
## TV-safe inset even though the page above them is not.
func _build_chrome() -> Control:
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(column)

	_address = Label.new()
	_address.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_address.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_address.text = "Browser"
	column.add_child(_address)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	column.add_child(_hints)
	_refresh_hints()

	return safe


## THE HINT ROW SAYS WHAT B DOES RIGHT NOW, and it changes, because B does two
## things: the page's history while there is any, and closing this screen when
## there is not. Advertising one word for both would make the button a surprise
## exactly once per visit -- which is the visit where somebody loses a checkout.
func _refresh_hints() -> void:
	if _hints == null:
		return
	for child in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()
	_hints.add_child(TvTheme.hint("A", "Click"))
	_hints.add_child(TvTheme.hint("Y", "Type"))
	_hints.add_child(TvTheme.hint("X", "Address"))
	_hints.add_child(TvTheme.hint("Menu", "Options"))
	_hints.add_child(TvTheme.hint("L1/R1/R stick", "Scroll"))
	_hints.add_child(TvTheme.hint("B", "Dismiss" if _is_page_popup_open() else ("Back" if _can_go_back() else "Close")))


func _can_go_back() -> bool:
	return _view != null and _view.has_method("can_go_back") and _view.can_go_back()

func _is_page_popup_open() -> bool:
	return _view != null and _view.has_method("is_popup_open") and _view.is_popup_open()


## Open a URL, with a human name for it to show while it loads. The name is the
## caller's -- the store knows the game's title long before the page does -- and
## a status line that said the raw URL would be showing somebody a query string
## on a television.
func open_url(url: String, title: String = "") -> void:
	_opening_title = title
	_last_error = ""
	_on_url_changed(url)
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
	if _view == null or not _view.has_method("is_loading"):
		_status.text = ""
		return
	if not _last_error.is_empty():
		_status.text = _last_error
		return
	if _view.is_loading():
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
	var popup_open := _is_page_popup_open()
	if _page_popup_open != popup_open:
		_page_popup_open = popup_open
		_refresh_hints()
	if not visible or _keyboard != null or _menu != null or _picker != null or _view == null or not _view.has_method("move_pointer"):
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

	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_click(true)
		return
	if event.is_action_released("ui_accept"):
		get_viewport().set_input_as_handled()
		_click(false)
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
		if _field_context.get("editable", false):
			_open_keyboard.call_deferred()


## The cursor, drawn by the shell over the page. See CURSOR_RADIUS for why it is
## a ring: this has to be findable over arbitrary content nobody here chose.
func _draw_cursor() -> void:
	if _view == null or not _view.has_method("get_pointer"):
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

func _on_keyboard_context(context: Dictionary) -> void:
	if str(context.get("type", "")).is_empty():
		context["type"] = "text"
	_field_context = context
	if _keyboard != null and _keyboard_purpose == "page":
		_close_keyboard()
	if context.get("editable", false) and _keyboard == null and _menu == null:
		_open_keyboard.call_deferred()

func _open_keyboard() -> void:
	if not visible or _click_held or _keyboard != null or _view == null or not _view.has_method("type_text"):
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
	# Reserve space instead of covering the page. Chromium reflows the document,
	# then scrolls the focused editor into its remaining visible area.
	_hints.hide()
	_cursor_layer.hide()
	add_child(_keyboard)
	if _keyboard.has_signal("panel_moved"):
		_keyboard.panel_moved.connect(_keyboard_moved)
	_keyboard_moved(_keyboard.get_panel_rect())
	set_process_unhandled_input(false)
	_reveal_field_later()

func _keyboard_moved(rect: Rect2) -> void:
	# Put the page on the opposite side of the movable keyboard. Reflowing
	# keeps editors visible without retaining page values in shell memory.
	if rect.get_center().x >= size.x / 2.0:
		_view.offset_left = 0
		_view.offset_right = -size.x + rect.position.x - Keyboard.PANEL_GAP
	else:
		_view.offset_left = rect.end.x + Keyboard.PANEL_GAP
		_view.offset_right = 0
	_reveal_field_later()

func _reveal_field_later() -> void:
	await get_tree().create_timer(0.15).timeout
	if _keyboard != null and _keyboard_purpose == "page" and _view.has_method("reveal_focused_field"):
		_view.reveal_focused_field()

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
	_view.offset_right = 0
	_view.offset_left = 0
	_hints.show()
	_cursor_layer.show()
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


func _on_page_finished(_url: String, http_status: int) -> void:
	if http_status >= 400:
		_last_error = "Website returned HTTP %d. Options → Reload to retry." % http_status
	_refresh_status()
	_refresh_hints()
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


func _on_title_changed(title: String) -> void:
	# Kept for the status line's loading sentence, which prefers the caller's
	# name but falls back to the page's own once it has one.
	if _opening_title.is_empty():
		_opening_title = title


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
	if _address != null:
		_address.text = "%d/%d · %s" % [_tabs.find(_view) + 1, _tabs.size(), url]


func _open_address() -> void:
	if _keyboard != null:
		return
	_keyboard_purpose = "address"
	_scroll_dir = 0
	_keyboard = Keyboard.new()
	_keyboard.title_text = "Website or search"
	_keyboard.masked = false
	_keyboard.input_context = "url"
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
	_menu = ListMenu.new()
	_menu.title_text = "Browser"
	_menu.items = [
		{"id": "address", "label": "Website or search", "icon": "browser"},
		{"id": "tabs", "label": "Tabs (%d/%d)" % [_tabs.size(), MAX_TABS], "icon": "browser"},
		{"id": "bookmarks", "label": "Bookmarks", "icon": "browser"},
		{"id": "history", "label": "History", "icon": "browser"},
		{"id": "downloads", "label": "Downloads", "icon": "folder"},
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


func _menu_chosen(id: String) -> void:
	var purpose := _menu_purpose
	_close_menu()
	if purpose == "downloads":
		if id.begins_with("cancel:"):
			var download: Dictionary = _downloads.get(id.trim_prefix("cancel:").to_int(), {})
			if is_instance_valid(download.get("view")):
				download.view.cancel_download(download.id)
		elif id == "files": _open_download_folder()
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
		"close": closed.emit()
		"enter", "backspace":
			if _view != null and _view.has_method("send_editing_key"):
				_view.send_editing_key("Return" if id == "enter" else "BackSpace")
		_:
			var method := {"back": "go_back", "forward": "go_forward", "reload": "reload", "stop": "stop_loading"}.get(id, "") as String
			if _view != null and _view.has_method(method):
				_last_error = ""
				_view.call(method)


var _downloads: Dictionary = {}
var _download_summary := ""
var _menu_purpose := "options"

func _on_download_updated(download: Dictionary, view: Control = null) -> void:
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
	if _menu != null:
		return
	_menu_purpose = "downloads"
	_scroll_dir = 0
	_menu = ListMenu.new()
	_menu.title_text = "Downloads"
	_menu.note_text = "Files are saved in Downloads. Downloads continue when you return to the library. Closing a tab cancels its unfinished downloads."
	_menu.items = []
	_menu.items.append({"id": "files", "label": "Open Downloads in Files", "icon": "folder"})
	for download: Dictionary in _downloads.values():
		var active: bool = download.state == "downloading"
		var label := "Cancel: " if active else ("Saved: " if download.state == "complete" else str(download.state).capitalize() + ": ")
		_menu.items.append({"id": "cancel:%s" % download.id if active else "files", "label": label + str(download.name), "icon": "folder"})
	if _downloads.is_empty():
		_menu.items.append({"id": "empty", "label": "No downloads yet", "icon": "folder"})
	_menu.chosen.connect(_menu_chosen)
	var menu := _menu
	_menu.closed.connect(func():
		if _menu == menu: _close_menu())
	add_child(_menu)
	set_process_unhandled_input(false)

func _open_download_folder() -> void:
	if _picker != null: return
	_picker = load("res://src/files_screen.gd").new()
	_picker.initial_directory = download_directory()
	_picker.closed.connect(_finish_picker)
	add_child(_picker)
	set_process_unhandled_input(false)
