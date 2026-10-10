extends Control

## Native browser furniture. Chromium only owns the rectangle returned by page_rect().
signal action_requested(action: String)
signal url_requested(url: String)

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")
const WINDOW := Color("#192B37")
const CONTENT := Color("#203440")
const LINE := Color("#526D7F")
const ACCENT := Color("#BCDFF5")
const SHORTCUTS := [
	["YouTube", "https://www.youtube.com", "youtube", Color("#624650")],
	["Steam", "https://store.steampowered.com", "store", Color("#38536C")],
	["Twitch", "https://www.twitch.tv", "controller", Color("#514A6A")],
	["Reddit", "https://www.reddit.com", "more", Color("#645043")],
	["Wikipedia", "https://www.wikipedia.org", "file", Color("#4A5A64")],
	["GitHub", "https://github.com", "github", Color("#3E5B59")],
]

var address: Label
var status: Label
var hints: HBoxContainer
var search: Button
var address_button: Button
var _window: Panel
var _toolbar: HBoxContainer
var _tabs: Button
var _back: Button
var _forward: Button
var _reload: Button
var _bookmark: Button
var _page_area: Control
var _start: ScrollContainer
var _start_column: VBoxContainer
var _shortcuts: GridContainer
var _saved_heading: Label
var _recent: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_window()
	resized.connect(_layout)
	_layout()

static func box(color: Color, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

static func label(caption: String, font_size: int = 22, color: Color = TvTheme.TEXT_PRIMARY) -> Label:
	var result := Label.new()
	result.text = caption
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return result

func _button(caption: String, action: String, glyph: String = "", selected: bool = false) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 22)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, TvTheme.TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", Color("#8DA1AF"))
	button.add_theme_stylebox_override("normal", box(TvTheme.SURFACE_FOCUS if selected else Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", box(TvTheme.SURFACE_FOCUS))
	button.add_theme_stylebox_override("pressed", box(TvTheme.SURFACE_PRESSED))
	button.add_theme_stylebox_override("disabled", box(Color.TRANSPARENT))
	button.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, ACCENT, 3))
	if not glyph.is_empty():
		button.text = ""
		button.tooltip_text = caption
		button.custom_minimum_size.x = 44
		var mark := Icons.label(glyph, 26, TvTheme.TEXT_PRIMARY)
		mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(mark)
	button.pressed.connect(func(): action_requested.emit(action))
	button.focus_entered.connect(func(): action_requested.emit("controls"))
	return button

func _build_window() -> void:
	_window = Panel.new()
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Chromium is drawn beneath this control. Only the toolbar has a fill.
	_window.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_window)
	var strip := ColorRect.new()
	strip.color = WINDOW
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 60
	_window.add_child(strip)
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 8)
	_window.add_child(_toolbar)
	_back = _button("Back", "back", "caret-left")
	_forward = _button("Forward", "forward", "caret-right")
	_reload = _button("Reload", "reload", "restart")
	for button in [_back, _forward, _reload]: _toolbar.add_child(button)
	address_button = _button("Website or search", "address")
	address_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_button.add_theme_stylebox_override("normal", box(CONTENT))
	_toolbar.add_child(address_button)
	address = label("Website or search", 22, TvTheme.TEXT_SECONDARY)
	address.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	address.offset_left = 12
	address.offset_right = -12
	address.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	address_button.text = ""
	address_button.add_child(address)
	_bookmark = _button("Bookmark this page", "save", "bookmark")
	_toolbar.add_child(_bookmark)
	_tabs = _button("Tabs", "tabs", "stack")
	_toolbar.add_child(_tabs)
	_toolbar.add_child(_button("Extensions", "extensions", "puzzle"))
	_toolbar.add_child(_button("Browser options", "options", "more"))
	_page_area = Control.new()
	_page_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_page_area)
	_build_start()
	status = label("", 20, TvTheme.TEXT_SECONDARY)
	status.add_theme_stylebox_override("normal", box(WINDOW))
	status.visible = false
	_window.add_child(status)

func _build_start() -> void:
	_start = ScrollContainer.new()
	_start.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_start.follow_focus = true
	_start.add_theme_stylebox_override("panel", box(CONTENT))
	_page_area.add_child(_start)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + edge, 20)
	_start.add_child(pad)
	_start_column = VBoxContainer.new()
	_start_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_column.add_theme_constant_override("separation", 16)
	pad.add_child(_start_column)
	_start_column.add_child(label("Search the web", 30))
	search = _button("Search or enter a website", "address")
	search.custom_minimum_size.y = 56
	search.add_theme_stylebox_override("normal", box(TvTheme.SURFACE, LINE, 1))
	_start_column.add_child(search)
	search.text = ""
	var search_row := HBoxContainer.new()
	search_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	search_row.offset_left = 20
	search_row.offset_right = -20
	search_row.add_theme_constant_override("separation", 16)
	search_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	search.add_child(search_row)
	search_row.add_child(Icons.label("search", 28, ACCENT))
	var search_caption := label("Search or enter a website")
	search_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	search_row.add_child(search_caption)
	_saved_heading = label("Shortcuts", 22, ACCENT)
	_start_column.add_child(_saved_heading)
	_shortcuts = GridContainer.new()
	_shortcuts.columns = 6
	_shortcuts.add_theme_constant_override("h_separation", 12)
	_shortcuts.add_theme_constant_override("v_separation", 12)
	_start_column.add_child(_shortcuts)
	_start_column.add_child(label("Recent pages", 22, ACCENT))
	_recent = VBoxContainer.new()
	_recent.add_theme_constant_override("separation", 4)
	_start_column.add_child(_recent)
	hints = HBoxContainer.new()
	hints.add_theme_constant_override("separation", 20)
	_start_column.add_child(hints)
	refresh_library({"bookmarks": [], "history": []})

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func refresh_library(library: Dictionary) -> void:
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_url := ""
	if owner != null and (_shortcuts.is_ancestor_of(owner) or _recent.is_ancestor_of(owner)):
		focus_url = str(owner.get_meta("url", ""))
	_clear(_shortcuts)
	_clear(_recent)
	var bookmarks: Array = library.get("bookmarks", [])
	_saved_heading.text = "Shortcuts" if bookmarks.is_empty() else "Bookmarks"
	var entries: Array = SHORTCUTS if bookmarks.is_empty() else bookmarks.slice(0, 6)
	for entry: Variant in entries:
		var caption: String = str(entry.get("title", entry.get("url", ""))) if entry is Dictionary else entry[0]
		var url: String = str(entry.url) if entry is Dictionary else entry[1]
		var glyph: String = "globe" if entry is Dictionary else entry[2]
		var color: Color = TvTheme.SURFACE if entry is Dictionary else entry[3]
		var button := _button(caption, "")
		button.pressed.connect(func(): url_requested.emit(url))
		button.text = ""
		button.custom_minimum_size = Vector2(0, 80)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", box(color))
		button.tooltip_text = url
		button.set_meta("url", url)
		_shortcuts.add_child(button)
		var column := VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 8
		column.offset_right = -8
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(Icons.label(glyph, 28, TvTheme.TEXT_PRIMARY))
		var name_label := label(caption)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(name_label)
		button.add_child(column)
	var history: Array = library.get("history", [])
	if history.is_empty(): _recent.add_child(label("No recent pages", 22, TvTheme.TEXT_SECONDARY))
	for entry: Dictionary in history.slice(0, 3):
		var url := str(entry.get("url", ""))
		var title := str(entry.get("title", ""))
		var button := _button(title if not title.is_empty() else url, "")
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = url
		button.set_meta("url", url)
		button.pressed.connect(func(): url_requested.emit(url))
		_recent.add_child(button)
	if not focus_url.is_empty():
		for button in _shortcuts.get_children() + _recent.get_children():
			if button.get_meta("url", "") == focus_url:
				button.grab_focus()
				return
		search.grab_focus()

func refresh_tabs(tabs: Array[Control], current: Control) -> void:
	_tabs.tooltip_text = "Tabs · %d/8 · current %d" % [tabs.size(), tabs.find(current) + 1]

func refresh_navigation(can_back: bool, can_forward: bool, loading: bool, saved: bool, home: bool) -> void:
	_back.disabled = not can_back
	_forward.disabled = not can_forward
	_reload.disabled = home
	_reload.tooltip_text = "Stop loading" if loading else "Reload"
	_bookmark.disabled = home
	_bookmark.tooltip_text = "Remove bookmark" if saved else "Bookmark this page"
	(_bookmark.get_child(0) as Label).text = Icons.glyph("check" if saved else "bookmark")
	(_reload.get_child(0) as Label).text = Icons.glyph("close" if loading else "restart")
	_bookmark.add_theme_stylebox_override("normal", box(TvTheme.SURFACE_FOCUS if saved else Color.TRANSPARENT))
	for button in [_back, _forward, _reload, _bookmark]:
		for child in button.get_children(): child.modulate.a = 0.4 if button.disabled else 1.0
	_start.visible = home

func refresh_hints(native_controls: bool, popup: bool, can_back: bool, home: bool) -> void:
	_clear(hints)
	hints.add_child(TvTheme.hint("A", "Select" if native_controls else "Click"))
	hints.add_child(TvTheme.hint("X", "Address"))
	if not native_controls:
		hints.add_child(TvTheme.hint("Y", "Type"))
		hints.add_child(TvTheme.hint("R stick", "Scroll"))
	if not home: hints.add_child(TvTheme.hint("L3", "Page" if native_controls else "Controls"))
	hints.add_child(TvTheme.hint("B", "Dismiss" if popup else ("Page" if native_controls and not home else ("Back" if can_back else "Close"))))

func page_rect() -> Rect2:
	return Rect2(_window.position + _page_area.position, _page_area.size)

func refresh_status() -> void:
	status.visible = not status.text.is_empty()

func _layout() -> void:
	if _window == null: return
	_window.position = Vector2.ZERO
	_window.size = size
	_toolbar.position = Vector2(8, 8)
	_toolbar.size = Vector2(size.x - 16, 44)
	_page_area.position = Vector2(0, 60)
	_page_area.size = Vector2(size.x, maxf(0, size.y - 60))
	status.position = Vector2(12, size.y - 44)
	status.size = Vector2(size.x - 24, 32)
	_shortcuts.columns = 6 if _page_area.size.x >= 950 else 3
