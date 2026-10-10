extends Control

## Files uses the OS surfaces and controls: attached Places, a quiet listing,
## and an attached footer. Compact windows open Places as a full-width drawer.
##
## WHY A REDRAW AND NOT DOLPHIN. The Dolphin flatpak shipped here once and was
## removed, and the reason it is not coming back is not pride of authorship. It
## is a mouse-first desktop program: under the pad bridge it is puppeted with
## injected arrow keys, at desktop type sizes, with its verbs behind a menu bar
## and a right-click menu that a thumbstick cannot reach. What it has that this
## screen wanted is its SHAPE -- a Places column that never goes away, panes
## that can be split, three view modes, real sorting, multi-select, previews --
## and a shape is exactly the thing that can be rebuilt at TV scale on buttons
## the pad actually has. So: Dolphin's layout and feature set, none of its
## chrome, every verb on a real button.
##
## THE PIECES, and each is its own file for a reason worth keeping:
##
##   places_panel.gd  the left column, or compact drawer. It used to be a
##                    VIEW you backed out to, which made getting from a stick
##                    to Downloads five presses.
##   file_pane.gd     one pane: breadcrumb, listing, sort, view mode,
##                    selection. There are two of them, which IS split view.
##   file_item.gd     one folder or file, in whichever of the three modes.
##   file_thumbs.gd   budgeted, cached, cancellable picture decoding.
##   file_open.gd     what opens what: the built-in viewer, the browser, or
##                    an honest sentence.
##   image_viewer.gd  a picture fullscreen, with the folder under left/right.
##   file_properties.gd  an edge-attached, scrollable properties panel.
##
## THIS FILE IS THE COMPOSITION AND THE CONSEQUENCES. Layout, focus between
## regions, the clipboard, every file operation, the two menus, the status
## line. A pane renders and reports; nothing below this file writes to disk.
##
## THE PAD LAYOUT, and it is the answer to "use actual functioning buttons":
##
##   A         open -- descend, view a picture, launch a handler, or say why not
##   B         up one level; at a place's root, out to the Places column
##   X         select / deselect the thing under the cursor
##   Y         search the current folder
##   OPTIONS   the ACTIONS menu: open, copy, cut, paste, rename, delete,
##             new folder, properties, view settings -- and eject, on a drive in Places
##   L1 / R1   jump between the two panes in a split view
##
## THE VERBS ACT ON THE SELECTION IF THERE IS ONE AND ON THE CURSOR IF NOT.
## That one rule (FilePane.target_entries) is what keeps multi-select from
## being a mode: nothing has to be switched on, and X on nothing followed by
## Delete does exactly what Delete alone would have done.
##
## EVERY OPERATION'S OUTCOME LANDS ON THE STATUS LINE AND IN ShellLog. This
## machine's user cannot see stderr, and a copy that silently did nothing is
## indistinguishable from a copy that worked until the file is needed.
##
## Search and folder paths use the shared movable controller keyboard.
## Copy/move jobs yield every frame and publish only completed destinations.

signal closed()
signal files_picked(paths: PackedStringArray)

var picker_mode := false
var picker_title := "Choose file"
var picker_extensions := PackedStringArray()
var picker_multiple := false
var _picker_done := false
var initial_directory := ""

const TvTheme = preload("res://src/tv_theme.gd")
const ConsoleButton = preload("res://src/console_button.gd")
const ListMenu = preload("res://src/list_menu.gd")
const FilePane = preload("res://src/file_pane.gd")
const PlacesPanel = preload("res://src/places_panel.gd")
const FileOpen = preload("res://src/file_open.gd")
const FileItem = preload("res://src/file_item.gd")
const ImageViewer = preload("res://src/image_viewer.gd")
const BrowserScreen = preload("res://src/browser_screen.gd")
const WindowsInstallScreen = preload("res://src/windows_install_screen.gd")
const FileProperties = preload("res://src/file_properties.gd")
const Keyboard = preload("res://src/keyboard.gd")
const FileTransfer = preload("res://src/file_transfer.gd")
const FileTrash = preload("res://src/file_trash.gd")
var _transfer: FileTransfer
var _transfer_destination := ""
var _transfer_cut := false
var _operation_focus: Control

var _places: PlacesPanel = null
var _panes: Array = []
var _active: int = 0
var _split := false

## Has the second pane ever been pointed somewhere on purpose? It is listed at
## Home during _ready so that opening the split costs no listing (see the note
## there), which means "where is it" cannot be used to tell a pane nobody has
## touched from one somebody parked on Home deliberately. This flag is that
## distinction, and it is what makes the first split mirror the first pane
## while a later one remembers where the person left the second.
var _pane_two_touched := false

var _pane_row: HBoxContainer = null
var _heading: Label = null
var _status: Label = null
var _hints: HFlowContainer = null
var _body: HBoxContainer
var _content: MarginContainer
var _footer_pad: MarginContainer
var _places_button: Button
var _selection: Label
var _compact := false
var _places_open := false
var _places_from_back := false
var _pane_cursor: Control

## The clipboard: {"paths": Array, "cut": bool}, empty when nothing is armed.
## SCREEN-LIFETIME ON PURPOSE: it survives navigating anywhere within the
## screen (copy here, paste there is the whole point) and dies with the screen,
## because a clipboard that outlives its UI is an invisible loaded state the
## next opening would act on with no way to see it was armed.
var _clipboard: Dictionary = {}

var _menu: ListMenu = null
var _keyboard: Keyboard = null
var _viewer: ImageViewer = null

## The browser, while a document is open over this screen. Null the rest of the
## time: the engine is expensive enough that a page nobody asked for should not
## exist.
var _browser: Control = null
## The managed installer is embedded here when it was opened from a file. This
## keeps Files alive underneath it so Back returns to the directory and item
## that started the flow.
var _installer: Control = null
var _downloads: Control = null
var _properties: FileProperties = null

## What the open menu is about, captured when OPTIONS is pressed -- by the time
## a choice arrives the menu's row owns focus and the panes cannot be asked.
var _menu_targets: Array = []
var _menu_place: Dictionary = {}
var _keyboard_purpose: String = ""
var _return_focus_name: String = ""
var _next_menu := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 0)
	layout.add_child(_body)
	_places = PlacesPanel.new()
	_places.include_trash = not picker_mode
	_places.place_chosen.connect(_on_place_chosen)
	_places.became_active.connect(_on_places_active)
	_places.mounts_changed.connect(_on_mounts_changed)
	_body.add_child(_places)
	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_content)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 20)
	_content.add_child(column)

	# Keep selection separate from the page title and operation feedback.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	column.add_child(header)
	_places_button = ConsoleButton.new()
	_places_button.text = "Places"
	_places_button.pressed.connect(_show_places)
	_places_button.focus_entered.connect(_refresh_hints)
	header.add_child(_places_button)
	_heading = Label.new()
	_heading.text = "Files"
	_heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	_heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_heading)
	_selection = Label.new()
	_selection.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_selection.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	header.add_child(_selection)

	_pane_row = HBoxContainer.new()
	_pane_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pane_row.add_theme_constant_override("separation", TvTheme.FILES_PANE_GAP)
	_pane_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_pane_row)

	# BOTH PANES ARE BUILT NOW AND THE SECOND IS HIDDEN. Building it on demand
	# would mean the first split of a session pays a listing, a layout pass and
	# a focus grab in one frame, on llvmpipe -- and split view is pressed
	# mid-copy, which is the worst moment for the screen to stutter.
	for _i in 2:
		var pane := FilePane.new()
		pane.file_extensions = picker_extensions
		pane.activated.connect(_on_item_activated.bind(pane))
		pane.became_active.connect(_on_pane_active.bind(pane))
		pane.view_changed.connect(_refresh_chrome)
		pane.exit_up.connect(_on_pane_exit_up)
		_pane_row.add_child(pane)
		_panes.append(pane)
	_panes[1].visible = false

	# The status line: what the last operation actually did. Above the hints
	# rather than in them, because it is a sentence and they are a legend.
	var footer := PanelContainer.new()
	var footer_box := TvTheme.card_idle_box()
	footer_box.set_corner_radius_all(0)
	footer.add_theme_stylebox_override("panel", footer_box)
	layout.add_child(footer)
	_footer_pad = MarginContainer.new()
	footer.add_child(_footer_pad)
	var footer_column := VBoxContainer.new()
	footer_column.add_theme_constant_override("separation", 12)
	_footer_pad.add_child(footer_column)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	footer_column.add_child(_status)

	_hints = HFlowContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_theme_constant_override("h_separation", TvTheme.HINT_GAP)
	_hints.add_theme_constant_override("v_separation", 12)
	footer_column.add_child(_hints)

	_wire_regions()

	# Open on Home, in the left pane, with the cursor in the pane rather than in
	# the Places column: the person pressed Files to look at files.
	var home := _places.home_path()
	_point_pane(_panes[0], home, "Home")
	if not _panes[0].show_directory(home):
		_say("Could not open %s" % home, true)
	_point_pane(_panes[1], home, "Home")
	_panes[1].show_directory(home)
	if not initial_directory.is_empty() and initial_directory.is_absolute_path():
		_point_pane(_panes[0], "/", "Filesystem")
		if not _panes[0].show_directory(initial_directory.simplify_path()):
			_send_home(_panes[0])
			_say("Requested folder is unavailable", true)

	_set_active(0)
	_panes[0].grab_pane_focus()
	_refresh_chrome()
	resized.connect(_fit_files)
	_fit_files()

	Media.state_changed.connect(_on_media_state_changed)
	# DEAF WHILE A LAUNCH IS UP, the stores screen's rule and now this screen's
	# too -- because this screen can start one. A opens a file in its handler and
	# leaves this listing in the tree underneath; both read the same evdev
	# devices, so without this every arrow meant for the app would also walk the
	# cursor down a directory nobody is looking at, and a B meant for the app
	# would walk it up a folder.
	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)
	Launcher.minimized.connect(_on_launch_finished)

	ShellLog.info("files screen up at %s" % home)


func _search_folder() -> void:
	_restore_cursor()
	_return_focus_name = _pane().focused_name()
	_open_keyboard("search", "Search trash bin" if _pane().path == FileTrash.LOCATION else "Search this folder", _pane().search_text)


func _restore_cursor() -> void:
	if _pane().has_focus_inside():
		return
	if is_instance_valid(_pane_cursor) and _pane().is_ancestor_of(_pane_cursor):
		_pane_cursor.grab_focus()
	else:
		_pane().grab_pane_focus()


func _show_places() -> void:
	_places_from_back = false
	_places_open = _compact
	_fit_files()
	_places.grab_places_focus()


func _fit_files() -> void:
	if _content == null:
		return
	var unit := TvTheme.layout_unit(size)
	var was_compact := _compact
	_compact = size.x < 1100
	var owner := get_viewport().gui_get_focus_owner()
	if not was_compact and _compact:
		_places_open = _places.has_focus_inside()
	_places.visible = not _compact or _places_open
	_content.visible = not (_compact and _places_open)
	_places.custom_minimum_size.x = size.x if _compact else clampf(size.x * 0.23, 280, 40 * unit)
	_places_button.visible = _compact
	for edge in ["left", "right", "top", "bottom"]:
		var inset := maxi(20, roundi(size.x * 0.05)) if edge in ["left", "right"] else maxi(20, roundi(size.y * 0.05))
		_content.add_theme_constant_override("margin_" + edge, inset if edge != "left" or _compact else maxi(20, roundi(3.2 * unit)))
		_footer_pad.add_theme_constant_override("margin_" + edge, inset if edge in ["left", "right"] else maxi(16, roundi(2.4 * unit)))
	# A compact split keeps both locations, showing the active pane at full width.
	for i in _panes.size():
		_panes[i].visible = (i == _active if _compact and _split else i == 0 or _split)
	if is_instance_valid(owner) and not owner.is_visible_in_tree() and not _modal_open():
		_pane().grab_pane_focus()
	_wire_places_button()


func _wire_places_button() -> void:
	for edge in ["left", "right", "top"]:
		_places_button.set("focus_neighbor_" + edge, _places_button.get_path_to(_places_button))
	var target: Control = _pane()._crumbs.back() if not _pane()._crumbs.is_empty() else _places_button
	_places_button.focus_neighbor_bottom = _places_button.get_path_to(target)
	for pane in _panes:
		for crumb in pane._crumbs:
			crumb.focus_neighbor_top = crumb.get_path_to(_places_button if _compact else crumb)


func _on_launch_started(_entry: Dictionary) -> void:
	set_process_input(false)
	set_process_unhandled_input(false)


func _on_launch_finished(_entry: Dictionary) -> void:
	# Not while a menu, the keyboard, the viewer or the properties panel is up:
	# one of those owns input, and handing it back here would put two readers on
	# the same button.
	if _modal_open():
		return
	set_process_input(true)
	set_process_unhandled_input(true)
	# The launched application's window shuffle can leave the viewport with no
	# focus owner at all, which is the rail's _ensure_focus lesson: a screen
	# with nothing focused is a screen that ignores the pad.
	if get_viewport().gui_get_focus_owner() == null:
		_pane().grab_pane_focus(_return_focus_name)


## Which region left and right reach from each edge. Re-applied whenever the
## split opens or closes, because that is exactly when the answer changes.
##
## Not a loop: three regions with two different rules is clearer written out
## than parameterised, and this is the table the whole screen's navigability
## rests on -- the same argument the rail's neighbour table makes.
func _wire_regions() -> void:
	# The details view's columns are decided by whether a pane is sharing the
	# screen, and this is the one place that knows.
	for pane in _panes:
		pane.set_narrow(_split)
	_wire_places_button()


## LEFT AND RIGHT BETWEEN REGIONS, handled here rather than by a stored
## neighbour path. Every region rebuilds its focusable controls -- the Places
## rows when a drive appears, a pane's items on every listing -- so a NodePath
## saved across that boundary is a path to a freed node. Inside a region the
## explicit tables still do the work and still consume the press; they only
## reach this function by pointing at self at the edge, which leaves the press
## unconsumed. See FilePane._wire_focus.
##
## Returns true when it moved focus, so the caller knows to consume the event.
func _cross_region(going_right: bool) -> bool:
	if _places.has_focus_inside():
		if not going_right:
			return false
		_focus_pane(_active)
		return true

	var pane := _pane()
	if not pane.has_focus_inside():
		return false

	if going_right:
		if not pane.at_right_edge():
			return false
		if _split and _active == 0:
			_focus_pane(1)
			return true
		return false

	if not pane.at_left_edge():
		return false
	if _split and _active == 1:
		_focus_pane(0)
		return true
	_show_places()
	return true


# ---------------------------------------------------------------------------
# Regions and focus
# ---------------------------------------------------------------------------

func _pane() -> FilePane:
	return _panes[_active]


## THE FLOOR AND ITS NAME ALWAYS MOVE TOGETHER. A pane draws its floor as the
## first breadcrumb, so a root set without its label renders as
## "player" -- the last component of /var/home/player -- which is a directory
## nobody recognises as their own home. One function, so the two cannot be set
## apart by a branch that forgets the second.
func _point_pane(pane: FilePane, root: String, label: String) -> void:
	pane.place_root = root
	pane.place_label = label


## Send a pane home. The fallback for every "where it was looking no longer
## exists" case -- a drive pulled, a drive ejected -- and the one place that
## knows Home's label without asking the Places column for a list.
func _send_home(pane: FilePane) -> void:
	var home := _places.home_path()
	_point_pane(pane, home, "Home")
	pane.show_directory(home)


func _set_active(index: int) -> void:
	_active = index
	for i in _panes.size():
		_panes[i].set_active(_split and i == index)
	_fit_files()
	_refresh_chrome()


func _on_pane_active(pane: FilePane) -> void:
	var index := _panes.find(pane)
	if index == -1 or index == _active:
		_refresh_chrome()
		return
	_set_active(index)


func _on_places_active() -> void:
	_refresh_chrome()


## B at a pane's floor. Focus goes to the Places column, on the row for the
## place this pane is showing -- so backing out of a stick lands on the stick,
## not at the top of the list.
func _on_pane_exit_up() -> void:
	_show_places()
	_places_from_back = true
	ShellLog.info("files: out of the pane to Places")


func _on_place_chosen(place: Dictionary) -> void:
	var pane := _pane()
	var target := str(place.get("path", ""))
	var root := str(place.get("root", target))
	# The floor is set BEFORE the descent so a failed open leaves no half-armed
	# root; the stale one is overwritten by the next successful choice.
	_point_pane(pane, root, str(place.get("root_label", root.get_file())))
	if not pane.show_directory(target):
		_say("Could not open %s" % str(place.get("name", "")), true)
		return
	if pane == _panes[1]:
		_pane_two_touched = true
	_status.text = ""
	_places_open = false
	_places_from_back = false
	_fit_files()
	pane.grab_pane_focus()


# ---------------------------------------------------------------------------
# Drives
# ---------------------------------------------------------------------------

func _on_mounts_changed(arrived: Array, departed: Array) -> void:
	# A PANE INSIDE A DRIVE THAT WAS PULLED is showing a listing of a
	# filesystem that no longer exists, and every path in it is a path to
	# nowhere. Home is the only place still guaranteed true.
	for pane in _panes:
		for gone in departed:
			if pane.path == gone or pane.path.begins_with(str(gone) + "/"):
				_send_home(pane)
				_say("%s was removed" % str(gone).get_file(), true)
				break

	# A clipboard naming something on a drive that left would paste an error
	# later; disarm it now, while the connection between the two is still on
	# screen.
	if not _clipboard.is_empty():
		for gone in departed:
			for armed in _clipboard.get("paths", []):
				if str(armed).begins_with(str(gone) + "/"):
					_clipboard = {}
					break

	if not arrived.is_empty():
		var names := PackedStringArray()
		for mount_path in arrived:
			names.append(str(mount_path).get_file())
		_say("%s is ready" % ", ".join(names))
	_refresh_chrome()


## The privileged half finished (or refused) an eject. The drive is already
## gone from the Places poll by then in the happy case -- this is what puts the
## REASON on screen when it did not go.
func _on_media_state_changed(state: String, mount_path: String, said: String) -> void:
	match state:
		"done":
			_say("%s can be unplugged" % mount_path.get_file())
		"failed":
			_say("Could not eject %s%s"
				% [mount_path.get_file(), (" -- %s" % said) if not said.is_empty() else ""], true)
		"refused":
			_say("This machine will not eject that", true)


# ---------------------------------------------------------------------------
# The chrome: heading, hints
# ---------------------------------------------------------------------------

func _refresh_chrome() -> void:
	if _heading == null:
		return

	_heading.text = picker_title if picker_mode else ("Trash bin" if _pane().path == FileTrash.LOCATION else "Files")
	var selected := _pane().selection_count()
	_selection.text = "%d selected" % selected if selected > 0 else ""
	_selection.visible = selected > 0
	_places.set_location(_pane().path)
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and _pane().is_ancestor_of(owner):
		_pane_cursor = owner
	_wire_places_button()
	_status.visible = not _status.text.is_empty()
	_refresh_hints()


## THE LEGEND IS PER REGION AND PER ROW, and every entry in it is a press that
## does something where it is shown. A hint advertising a button whose press is
## correctly ignored is the exact shape of "broken input" on a machine with no
## other feedback -- the rule every screen in this shell follows.
func _refresh_hints() -> void:
	if _hints == null:
		return
	for child in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()
	if _transfer != null:
		_hints.add_child(TvTheme.hint("B", "Cancel move" if _transfer_cut else "Cancel copy"))
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner == _places_button:
		_hints.add_child(TvTheme.hint("A", "Places"))
		_hints.add_child(TvTheme.hint("Y", "Search"))
		_hints.add_child(TvTheme.hint("OPTIONS", "Actions"))
		_hints.add_child(TvTheme.hint("B", "Back"))
		return

	if _places.has_focus_inside():
		_hints.add_child(TvTheme.hint("A", "Open"))
		if bool(_places.focused_place().get("removable", false)):
			_hints.add_child(TvTheme.hint("OPTIONS", "Eject"))
		elif str(_places.focused_place().get("path", "")) == FileTrash.LOCATION:
			_hints.add_child(TvTheme.hint("OPTIONS", "Actions"))
		_hints.add_child(TvTheme.hint("B", "Back"))
		return

	var pane := _pane()
	var entry := pane.focused_entry()
	if not entry.is_empty():
		if pane.path == FileTrash.LOCATION:
			_hints.add_child(TvTheme.hint("A", "Restore"))
		elif bool(entry.get("is_dir", false)):
			_hints.add_child(TvTheme.hint("A", "Open"))
		else:
			var caption := "Open"
			if picker_mode:
				caption = "Select" if picker_multiple else "Choose file"
			_hints.add_child(TvTheme.hint("A", caption))
		_hints.add_child(TvTheme.hint("X",
			"Deselect" if _focused_is_selected(pane) else "Select"))

	_hints.add_child(TvTheme.hint("Y", "Search"))
	_hints.add_child(TvTheme.hint("OPTIONS", "Actions"))
	if _split:
		_hints.add_child(TvTheme.hint("L1/R1", "Other pane"))
	_hints.add_child(TvTheme.hint("B", "Back"))


func _focused_is_selected(pane: FilePane) -> bool:
	for chosen in pane.selected_entries():
		if str(chosen.get("path", "")) == str(pane.focused_entry().get("path", "")):
			return true
	return false


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## LEFT AND RIGHT ARE TAKEN BEFORE THE GUI SEES THEM, and that is forced
## rather than chosen. The obvious implementation is _unhandled_input: let each
## region's neighbour table move focus, and pick up the presses it does not
## use. It does not work, because a hard stop in this shell is a neighbour
## pointed at SELF -- the viewport resolves that to a perfectly valid focusable
## control, re-focuses it, and consumes the event. Nothing ever falls through,
## which the Xvfb run showed as Left at the left-hand column doing nothing at
## all instead of reaching the Places column.
##
## Leaving the neighbour UNSET would make it fall through, and would also hand
## the press to Control's geometric search first -- which is the thing every
## screen in this shell has an explicit table specifically to avoid.
##
## So the crossing is decided here, ahead of the GUI, and ONLY at an edge:
## anywhere else this returns without consuming and the region's own table does
## the work exactly as before.
func _input(event: InputEvent) -> void:
	if _transfer != null:
		if event.is_action_pressed("ui_cancel"):
			_transfer.cancel()
		get_viewport().set_input_as_handled()
		return
	if picker_mode and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		get_viewport().set_input_as_handled()
		_finish_picker(PackedStringArray())
		return
	if _modal_open():
		return
	var going_right := event.is_action_pressed("ui_right")
	if not going_right and not event.is_action_pressed("ui_left"):
		return
	if _cross_region(going_right):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _modal_open():
		return
	var focus := get_viewport().gui_get_focus_owner()

	if InputMap.has_action("ui_shell_options") and event.is_action_pressed("ui_shell_options"):
		get_viewport().set_input_as_handled()
		if focus == _places_button:
			_restore_cursor()
		_open_actions_menu()
		return

	if InputMap.has_action("ui_shell_y") and event.is_action_pressed("ui_shell_y"):
		if _places.has_focus_inside():
			return
		get_viewport().set_input_as_handled()
		_search_folder()
		return

	if InputMap.has_action("ui_shell_x") and event.is_action_pressed("ui_shell_x"):
		if _places.has_focus_inside() or focus == _places_button:
			return
		get_viewport().set_input_as_handled()
		var pane := _pane()
		pane.toggle_focused_selection()
		# Logged rather than said on the status line: the count is already in
		# the heading, and a sentence per press would overwrite the outcome of
		# the operation the person is selecting things FOR. The journal is
		# where the other end of an ssh session watches a bulk delete being
		# assembled -- and it is what the Xvfb harness asserts selection on.
		ShellLog.info("files: %s \"%s\" -- %d selected"
			% ["selected" if _focused_is_selected(pane) else "deselected",
				pane.focused_name(), pane.selection_count()])
		return

	# The shoulders are inert unless there is a second pane to reach. Advertised
	# only then, too -- see _refresh_hints.
	if _split and InputMap.has_action("ui_shell_l1") \
			and event.is_action_pressed("ui_shell_l1"):
		get_viewport().set_input_as_handled()
		_focus_pane(0)
		return
	if _split and InputMap.has_action("ui_shell_r1") \
			and event.is_action_pressed("ui_shell_r1"):
		get_viewport().set_input_as_handled()
		_focus_pane(1)
		return

	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the home rail underneath never sees the same press.
	get_viewport().set_input_as_handled()

	if _places.has_focus_inside():
		if _compact and not _places_from_back:
			_places_open = false
			_fit_files()
			_pane().grab_pane_focus()
			return
		ShellLog.info("files: closed by B at Places")
		if picker_mode:
			_finish_picker(PackedStringArray())
		else:
			closed.emit()
		return
	if focus == _places_button:
		_restore_cursor()
		return
	_status.text = ""
	_pane().go_up()


func _modal_open() -> bool:
	return _menu != null or _keyboard != null or _viewer != null or _properties != null \
		or _browser != null or _installer != null or _downloads != null or _transfer != null


func _focus_pane(index: int) -> void:
	_places_open = false
	_places_from_back = false
	if index == _active and _pane().has_focus_inside():
		return
	_set_active(index)
	_panes[index].grab_pane_focus(_panes[index].focused_name())


# ---------------------------------------------------------------------------
# Opening
# ---------------------------------------------------------------------------

## A on an item. Four outcomes and the plan decides which -- see file_open.gd.
func _on_item_activated(entry: Dictionary, pane: FilePane) -> void:
	if pane.path == FileTrash.LOCATION:
		_restore_trash_entries([entry])
		return
	if bool(entry.get("is_dir", false)):
		_status.text = ""
		if not pane.show_directory(str(entry["path"])):
			_say("Could not open %s" % str(entry.get("name", "")), true)
		elif pane == _panes[1]:
			_pane_two_touched = true
		return

	if picker_mode:
		if picker_multiple:
			pane.toggle_focused_selection()
		else:
			_choose_picker_entries([entry])
		return
	var file_name := str(entry.get("name", ""))
	var plan := FileOpen.plan(file_name)
	match str(plan["action"]):
		"image":
			_open_viewer(pane, str(entry["path"]))
		"browser":
			# A DOCUMENT IS A SCREEN NOW, not a launch. No Launcher.is_busy
			# check, because nothing is being spawned and there is no window to
			# wait for -- the browser is a Control this screen puts over itself,
			# the same as the picture viewer above.
			_open_browser(pane, str(entry["path"]), file_name)
		"installer":
			_open_installer(str(entry["path"]), file_name)
		"torrent":
			_open_downloads(str(entry["path"]))
		_:
			# Only "none" lands here: nothing on this machine draws or manages
			# this format, said in terms of THIS file.
			_say(str(plan["detail"]), true)


## An EXE/MSI opened from Files uses the same managed installation screen as
## the top-bar Install action, with the chosen path carried in as its initial
## focus. It is a child for the same lifetime reason as the image viewer and
## document browser: closing it reveals the exact file-list state underneath.
func _open_downloads(path: String) -> void:
	if _downloads != null: return
	_downloads = load("res://src/downloads_screen.gd").new()
	_downloads.initial_torrent = path
	_return_focus_name = path.get_file()
	_downloads.closed.connect(func(): _close_downloads.call_deferred())
	add_child(_downloads)
	set_process_unhandled_input(false)

func _close_downloads() -> void:
	if _downloads == null: return
	remove_child(_downloads)
	_downloads.queue_free()
	_downloads = null
	set_process_unhandled_input(true)
	_pane().grab_pane_focus(_return_focus_name)

func _open_installer(path: String, file_name: String) -> void:
	if _installer != null:
		return
	_installer = WindowsInstallScreen.new()
	_installer.source_path = path
	_installer.source_name = file_name
	_installer.closed.connect(_on_installer_closed, CONNECT_ONE_SHOT)
	_return_focus_name = file_name
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	add_child(_installer)
	set_process_unhandled_input(false)
	ShellLog.info("files: opening %s in the Windows installer" % file_name)


func _on_installer_closed() -> void:
	_close_installer.call_deferred()


func _close_installer() -> void:
	if _installer == null:
		return
	var installer := _installer
	_installer = null
	remove_child(installer)
	installer.queue_free()
	set_process_input(true)
	set_process_unhandled_input(true)
	_pane().grab_pane_focus(_return_focus_name)


func _open_viewer(pane: FilePane, path: String) -> void:
	if _viewer != null:
		return
	var pictures := pane.image_paths()
	_viewer = ImageViewer.new()
	_viewer.paths = pictures
	_viewer.index = maxi(0, pictures.find(path))
	_viewer.closed.connect(_on_viewer_closed, CONNECT_ONE_SHOT)
	_return_focus_name = path.get_file()
	# A child of this screen, wifi_screen's reason: closing the files screen can
	# then never leave a viewer orphaned over the rail.
	add_child(_viewer)
	set_process_unhandled_input(false)


## A document, in the shell's own browser. The picture viewer's shape exactly:
## a child of THIS screen rather than of the root, so closing the files screen
## can never leave a page orphaned over the rail, and this screen deaf while it
## is up.
func _open_browser(pane: FilePane, path: String, file_name: String) -> void:
	if _browser != null:
		return
	_browser = BrowserScreen.new()
	_browser.closed.connect(_on_browser_closed, CONNECT_ONE_SHOT)
	_return_focus_name = file_name
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	add_child(_browser)
	set_process_unhandled_input(false)
	# After the node is in the tree: the engine's view has no size until it has
	# been laid out once, and CEF stops painting a view it was told is empty.
	_browser.open_url(FileOpen.file_url(path), file_name)
	ShellLog.info("files: opening %s in the browser" % file_name)


func _on_browser_closed() -> void:
	_close_browser.call_deferred()


func _close_browser() -> void:
	if _browser == null:
		return
	var browser := _browser
	_browser = null
	remove_child(browser)
	browser.queue_free()
	set_process_input(true)
	set_process_unhandled_input(true)
	# Back onto the file that was opened, the viewer's rule: a listing that
	# comes back with no ring reads as a pad that stopped working. Focus is
	# restored BY NAME rather than by index, which is the pane's own contract
	# -- the listing may have been re-read while the document was up.
	_pane().grab_pane_focus(_return_focus_name)


func _on_viewer_closed() -> void:
	_close_viewer.call_deferred()


func _close_viewer() -> void:
	if _viewer == null:
		return
	# The picture the person stopped on is where the cursor goes back to, not
	# the one they opened. Walking six pictures forward and pressing B should
	# leave the list on the sixth.
	var landed := ""
	if _viewer.index >= 0 and _viewer.index < _viewer.paths.size():
		landed = str(_viewer.paths[_viewer.index]).get_file()
	var viewer := _viewer
	_viewer = null
	remove_child(viewer)
	viewer.queue_free()
	set_process_input(true)
	set_process_unhandled_input(true)
	_pane().grab_pane_focus(landed if not landed.is_empty() else _return_focus_name)


# ---------------------------------------------------------------------------
# View settings in the Options menu
# ---------------------------------------------------------------------------

## Dolphin's View menu, as one screen of rows. Every entry states its CURRENT
## value in its label -- "Sort by: Size" rather than "Sort by" -- because a
## menu that only says what it will change is a menu you have to open twice to
## find out where you are.
func _view_options() -> Array:
	var pane := _pane()
	var items := [
		{"id": "search", "label": "Search this folder", "icon": "search"},
		{"id": "location", "label": "Open folder path", "icon": "folder-open"},
		{"id": "refresh", "label": "Refresh", "icon": "more"},
		{"id": "historyback", "label": "Previous folder", "icon": "caret-left"},
		{"id": "historyforward", "label": "Next folder", "icon": "caret-right"},
		{"id": "mode", "label": "View: %s" % _mode_label(pane.mode), "icon": "folder-open"},
		{"id": "sort", "label": "Sort by: %s" % _sort_label(pane.sort_key), "icon": "more"},
		{"id": "order", "label": "Order: %s"
			% ("Descending" if pane.sort_descending else "Ascending"),
			"icon": "caret-right"},
		{"id": "hidden", "label": "Hidden files: %s"
			% ("Shown" if pane.show_hidden else "Hidden"), "icon": "check"},
		{"id": "split", "label": "Split view: %s" % ("On" if _split else "Off"),
			"icon": "copy"},
	]
	if not pane.search_text.is_empty():
		items.append({"id": "clearsearch", "label": "Clear search", "icon": "search"})
	if not pane.path.is_empty():
		items.append({"id": "selectall",
			"label": "Clear selection" if pane.selection_count() > 0 else "Select all",
			"icon": "check"})

	return items


func _mode_label(mode: String) -> String:
	match mode:
		FileItem.MODE_ICONS:
			return "Icons"
		FileItem.MODE_COMPACT:
			return "Compact"
		_:
			return "Details"


func _sort_label(key: String) -> String:
	match key:
		FilePane.SORT_SIZE:
			return "Size"
		FilePane.SORT_DATE:
			return "Date"
		FilePane.SORT_TYPE:
			return "Type"
		_:
			return "Name"


## Cycling rather than a submenu, and it is the pad that decides that: a
## submenu is a second screen to open, move in and back out of for a setting
## with three values. One press advances it, the label says where it landed,
## and the list is right there to see the effect on.
func _cycle_mode(pane: FilePane) -> void:
	var order := [FileItem.MODE_DETAILS, FileItem.MODE_ICONS, FileItem.MODE_COMPACT]
	var next: int = (order.find(pane.mode) + 1) % order.size()
	pane.set_view(str(order[next]), pane.sort_key, pane.sort_descending, pane.show_hidden)
	_say("%s view" % _mode_label(pane.mode))


func _cycle_sort(pane: FilePane) -> void:
	var order := [FilePane.SORT_NAME, FilePane.SORT_SIZE,
		FilePane.SORT_DATE, FilePane.SORT_TYPE]
	var next: int = (order.find(pane.sort_key) + 1) % order.size()
	pane.set_view(pane.mode, str(order[next]), pane.sort_descending, pane.show_hidden)
	_say("Sorted by %s" % _sort_label(pane.sort_key).to_lower())


## THE SECOND PANE OPENS ON THE SAME FOLDER, and that is deliberate rather than
## lazy. Split view is pressed in order to copy something somewhere, and the
## person has one of the two ends already on screen -- opening the new pane on
## Home would throw that away half the time. Same folder means the next move is
## always "point the other side somewhere", which is one visit to Places.
func _toggle_split() -> void:
	_split = not _split
	_panes[1].visible = _split
	if _split:
		var source: FilePane = _panes[0]
		if not _pane_two_touched:
			_point_pane(_panes[1], source.place_root, source.place_label)
			_panes[1].show_directory(source.path)
		_wire_regions()
		_set_active(1)
		_panes[1].grab_pane_focus()
		_say("Split view on -- L1 and R1 jump between the panes")
	else:
		_panes[1].clear_selection()
		_wire_regions()
		_set_active(0)
		_panes[0].grab_pane_focus(_panes[0].focused_name())
		_say("Split view off")


# ---------------------------------------------------------------------------
# The actions menu (OPTIONS)
# ---------------------------------------------------------------------------

func _open_actions_menu() -> void:
	if _modal_open():
		return

	if picker_mode:
		_menu_targets = _pane().target_entries()
		_open_menu([
			{"id": "pick", "label": "Choose selected files" if picker_multiple else "Choose file", "icon": "check"},
			{"id": "pickcancel", "label": "Cancel", "icon": "close"}], picker_title, "")
		return
	if (_places.has_focus_inside() and str(_places.focused_place().get("path", "")) == FileTrash.LOCATION) or (not _places.has_focus_inside() and _pane().path == FileTrash.LOCATION):
		_open_trash_actions()
		return

	# On the Places column OPTIONS is about the PLACE, and a drive has exactly
	# one verb: taking it out without losing what was just written to it. Home
	# has none -- you cannot eject the disk the shell is running from.
	if _places.has_focus_inside():
		var place := _places.focused_place()
		if not bool(place.get("removable", false)):
			ShellLog.info("files: OPTIONS on a place with nothing to offer")
			return
		if Media.is_busy():
			ShellLog.info("files: OPTIONS while an eject is already in flight; ignoring")
			return
		_menu_place = place
		_menu_targets = []
		_open_menu([{"id": "eject", "label": "Safely remove", "icon": "eject"}],
			str(place.get("name", "")),
			"Everything is written to the drive first. Wait for the message before unplugging it.")
		return

	var pane := _pane()
	var targets := pane.target_entries()
	var many := targets.size() > 1
	var items: Array = []

	if targets.size() == 1 and not bool(targets[0].get("is_dir", false)):
		var plan := FileOpen.plan(str(targets[0].get("name", "")))
		if str(plan["action"]) in ["image", "browser", "installer"]:
			items.append({"id": "open", "label": str(plan["detail"]), "icon": "folder-open"})

	if not targets.is_empty():
		items.append({"id": "copy", "label": _count_label("Copy", targets), "icon": "copy"})
		items.append({"id": "cut", "label": _count_label("Cut", targets), "icon": "cut"})

	if not _clipboard.is_empty():
		# Paste appears ONLY while armed: a permanent Paste that mostly says
		# "nothing to paste" would train the button to mean nothing. The verb
		# names its object so the menu carries its own state. "download" is the
		# closest mark the vendored table has -- an arrow into a tray IS
		# paste-into-here, and PROVENANCE.md forbids guessing new codepoints.
		var armed: Array = _clipboard.get("paths", [])
		var what: String = str(armed[0]).get_file() if armed.size() == 1 \
			else "%d items" % armed.size()
		items.append({"id": "paste", "label": "Paste %s" % what, "icon": "download"})

	if targets.size() == 1:
		# Rename is single by nature: two files cannot both become one name,
		# and a bulk rename needs a pattern language this screen has no way to
		# type. Offering it on a multi-selection would be a menu entry that
		# quietly acts on one of them.
		items.append({"id": "rename", "label": "Rename", "icon": "rename"})

	if not targets.is_empty():
		items.append({"id": "delete", "label": _count_label("Delete", targets), "icon": "trash"})

	# ALWAYS OFFERED, and it is the one item about the FOLDER rather than about
	# what the cursor is on -- which is why it is last, and why an empty folder
	# has a menu at all.
	items.append({"id": "newfolder", "label": "New folder", "icon": "folder"})
	items.append({"id": "opentrash", "label": "Open trash bin", "icon": "trash"})

	if targets.size() == 1:
		items.append({"id": "properties", "label": "Properties", "icon": "more"})
	items.append_array(_view_options())

	_menu_place = {}
	_menu_targets = targets
	_return_focus_name = pane.focused_name()

	var title := pane.path.get_file()
	if targets.size() == 1:
		title = str(targets[0].get("name", title))
	elif many:
		title = "%d items" % targets.size()

	var note := ""
	if not targets.is_empty():
		# Named cost, card_menu's discipline: delete here is the trash, which is
		# reversible from a desktop -- and saying "cannot be undone" about it
		# would be the note lying in the scary direction.
		note = "Delete moves things to the system's wastebasket, not into thin air."
	_open_menu(items, title, note)


func _count_label(verb: String, targets: Array) -> String:
	if targets.size() == 1:
		return verb
	return "%s %d items" % [verb, targets.size()]


func _open_menu(items: Array, title: String, note: String) -> void:
	if items.is_empty():
		ShellLog.info("files: nothing to offer here")
		return
	_menu = ListMenu.new()
	_menu.title_text = title
	_menu.items = items
	_menu.note_text = note
	_menu.chosen.connect(_on_menu_chosen)
	_menu.closed.connect(_on_menu_closed, CONNECT_ONE_SHOT)
	# Deaf while the menu is up, so one B press cannot close both surfaces.
	set_process_unhandled_input(false)
	add_child(_menu)


func _on_menu_chosen(id: String) -> void:
	var pane := _pane()
	if id.begins_with("restore:"):
		_restore_trash_entries([{"trash_id": id.trim_prefix("restore:")}])
		return
	match id:
		"restoretrash":
			_restore_trash_entries(_menu_targets)
		"emptytrash":
			_next_menu = "emptytrash"
		"emptytrashconfirmed":
			var result := FileTrash.empty()
			_refresh_trash()
			_say(str(result["message"]), not bool(result["ok"]))
		"cancel":
			pass
		"pick":
			_choose_picker_entries(_menu_targets)
		"pickcancel":
			_finish_picker(PackedStringArray())
		"search":
			_open_keyboard("search", "Search this folder", pane.search_text)
		"location":
			_open_keyboard("location", "Open folder path", pane.path)
		"clearsearch":
			pane.set_search("")
		"refresh":
			pane.refresh()
		"historyback":
			if not pane.history_move(-1):
				_say("No previous folder")
		"historyforward":
			if not pane.history_move(1):
				_say("No next folder")
		"opentrash":
			_open_trash.call_deferred()
		"mode":
			_cycle_mode(pane)
		"sort":
			_cycle_sort(pane)
		"order":
			pane.set_view(pane.mode, pane.sort_key, not pane.sort_descending, pane.show_hidden)
			_say("Order: %s" % ("descending" if pane.sort_descending else "ascending"))
		"hidden":
			pane.set_view(pane.mode, pane.sort_key, pane.sort_descending, not pane.show_hidden)
			_say("Hidden files %s" % ("shown" if pane.show_hidden else "hidden"))
		"split":
			_toggle_split()
		"selectall":
			pane.toggle_select_all()
			_say("%d selected" % pane.selection_count())
		"open":
			if not _menu_targets.is_empty():
				_on_item_activated(_menu_targets[0], pane)
		"copy":
			_arm_clipboard(false)
		"cut":
			_arm_clipboard(true)
		"paste":
			_paste_into(pane.path)
		"rename":
			_open_rename()
		"delete":
			_delete_targets()
		"newfolder":
			_open_new_folder()
		"properties":
			_open_properties()
		"eject":
			_eject_place()
		_:
			ShellLog.error("file menu item \"%s\" has no action" % id)


func _on_menu_closed() -> void:
	_close_menu.call_deferred()
	if _next_menu == "emptytrash":
		_confirm_empty_trash.call_deferred()
	_next_menu = ""


func _close_menu() -> void:
	if _menu == null:
		return
	var menu := _menu
	_menu = null
	remove_child(menu)
	menu.queue_free()
	# Rename and New folder open the keyboard from the chosen handler, and
	# Properties opens a panel; when they did, that surface owns input and focus
	# until it closes, and re-enabling here would let B reach this screen
	# THROUGH it.
	if _keyboard != null or _properties != null or _viewer != null or _browser != null or _installer != null:
		return
	set_process_unhandled_input(true)
	if _transfer != null:
		return

	# ONLY IF THE CHOICE DID NOT ALREADY PLACE THE CURSOR. Splitting the view
	# grabs focus in the pane it just opened, and this running afterwards --
	# deferred, so it always does -- would drag the cursor back to a name
	# remembered from the pane the person was in BEFORE the split. Asking the
	# viewport is the reliable test: the menu's own row held focus until it was
	# freed, so anything focused inside this screen now was put there
	# deliberately by the action.
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and is_ancestor_of(owner):
		_refresh_chrome()
		return

	if _menu_place.is_empty():
		_pane().grab_pane_focus(_return_focus_name)
	else:
		_places.grab_places_focus()
	_refresh_chrome()


# ---------------------------------------------------------------------------
# The clipboard
# ---------------------------------------------------------------------------

func _arm_clipboard(cut: bool) -> void:
	var paths: Array = []
	for entry in _menu_targets:
		paths.append(str(entry.get("path", "")))
	if paths.is_empty():
		return
	_clipboard = {"paths": paths, "cut": cut}

	var what: String = str(paths[0]).get_file() if paths.size() == 1 \
		else "%d items" % paths.size()
	_say("%s %s -- Paste puts it in the folder you are in"
		% ["Cut" if cut else "Copied", what])
	ShellLog.info("files: clipboard armed (%s) for %d path(s)"
		% ["cut" if cut else "copy", paths.size()])
	# The things just copied stop being selected: the selection's next job is
	# choosing where they go, and leaving it armed makes the following Delete
	# act on the source of a copy that has not landed yet.
	_pane().clear_selection()


## Paste everything armed into a directory. Copy leaves the clipboard armed --
## pasting the same thing into three folders is a legitimate afternoon -- and
## cut clears it, because the sources it names no longer exist.
##
## EACH ITEM IS INDEPENDENT. One failure reports itself and the rest continue,
## which is the opposite of the rule INSIDE a single recursive copy (that stops
## at the first error). The difference is what a partial result means: half a
## directory tree is a corrupt copy, and three of four files is three files.
func _paste_into(dest_dir: String) -> void:
	var armed: Array = _clipboard.get("paths", [])
	if armed.is_empty() or dest_dir.is_empty() or _transfer != null:
		return
	_transfer_destination = dest_dir
	_transfer_cut = bool(_clipboard.get("cut", false))
	_transfer = FileTransfer.new()
	_transfer.begin(armed, dest_dir, _transfer_cut)
	_operation_focus = get_viewport().gui_get_focus_owner()
	if _operation_focus != null:
		_operation_focus.release_focus()
	_say("Preparing %s -- Circle: cancel" % ("move" if _transfer_cut else "copy"))
	_refresh_hints()
	set_process_unhandled_input(true)

func _process(_delta: float) -> void:
	if _transfer == null:
		return
	_transfer.step()
	if _transfer.running:
		_status.text = "%s %s -- %s%s" % ["Moving" if _transfer_cut else "Copying", _transfer.current_name,
			FileItem.human_size(_transfer.copied_bytes),
			" -- finishing move" if _transfer.committing else " -- Circle: cancel"]
		return
	var results := _transfer.completed
	var was_cancelled := _transfer.cancelling
	var problems := _transfer.errors
	var skipped := _transfer.skipped_links
	if _transfer_cut:
		var remaining: Array = _clipboard.get("paths", []).duplicate()
		for result in results:
			remaining.erase(result["source"])
		_clipboard = {"paths": remaining, "cut": true} if not remaining.is_empty() else {}
	_transfer = null
	var line := "%s %d item(s)" % ["Moved" if _transfer_cut else "Copied", results.size()]
	if was_cancelled:
		line += " -- cancelled; unfinished copy removed"
	if skipped > 0:
		line += " -- %d link(s) skipped" % skipped
	if not problems.is_empty():
		line += " -- " + str(problems[0])
	_say(line, not problems.is_empty())
	_refresh_panes_showing(_transfer_destination, str(results.back()["name"]) if not results.is_empty() else "")
	for result in results:
		_refresh_panes_showing(str(result["source"]).get_base_dir(), "")
	_pane().grab_pane_focus()
	_refresh_chrome()

func _exit_tree() -> void:
	if _transfer != null:
		_transfer.finish_cleanup()
	if picker_mode and not _picker_done:
		files_picked.emit(PackedStringArray())


func _exists(path: String) -> bool:
	return FileTransfer.exists(path)


# ---------------------------------------------------------------------------
# Naming things: rename, and new folder
# ---------------------------------------------------------------------------

## The wifi screen's keyboard pattern, with the entry prefilled: renaming is an
## edit, and starting from an empty field would make every rename a full retype
## of the part being kept.
func _open_rename() -> void:
	if _menu_targets.size() != 1:
		return
	var target_name := str(_menu_targets[0].get("name", ""))
	if target_name.is_empty():
		return
	_open_keyboard("rename", "Rename %s" % target_name, target_name)


## The same keyboard, asked a different question. EMPTY rather than prefilled
## with "New folder": a suggested name is only a saving if it is the one you
## wanted, and clearing a 5x10 grid one backspace at a time from a sofa costs
## more than typing the name did.
func _open_new_folder() -> void:
	_open_keyboard("newfolder", "New folder in %s" % _pane().path.get_file(), "")


## One keyboard, one slot, one purpose at a time. `_keyboard_purpose` is what
## the submit handler branches on; without it the two questions would need two
## signal connections onto the same node and the second would have to remember
## to disconnect the first.
func _open_keyboard(purpose: String, title: String, initial: String) -> void:
	if _keyboard != null:
		return
	_keyboard_purpose = purpose
	_keyboard = Keyboard.new()
	_keyboard.title_text = title
	# A file name is not a secret; masking it would hide the one thing the
	# screen exists to show.
	_keyboard.masked = false
	_keyboard.initial_text = initial
	_keyboard.submitted.connect(_on_name_submitted)
	_keyboard.cancelled.connect(_on_name_cancelled)
	add_child(_keyboard)
	set_process_unhandled_input(false)


func _close_keyboard() -> void:
	if _keyboard == null:
		return
	var keyboard := _keyboard
	_keyboard = null
	_keyboard_purpose = ""
	remove_child(keyboard)
	keyboard.queue_free()
	set_process_input(true)
	set_process_unhandled_input(true)
	_pane().grab_pane_focus(_return_focus_name)


func _on_name_submitted(text: String) -> void:
	# Read BEFORE the close, which clears it.
	var purpose := _keyboard_purpose
	_close_keyboard()
	match purpose:
		"rename":
			_rename_to(text)
		"newfolder":
			_make_folder(text)
		"search":
			_pane().set_search(text)
		"location":
			var destination := text.strip_edges().simplify_path()
			if not destination.is_absolute_path() or not DirAccess.dir_exists_absolute(destination):
				_say("Folder path is unavailable", true)
			else:
				_point_pane(_pane(), "/", "Filesystem")
				_pane().show_directory(destination)
		_:
			ShellLog.error("files: a name arrived with no question attached")


func _on_name_cancelled() -> void:
	_close_keyboard()


## The rules every new name goes through, both questions sharing one gate:
## empty is not a name, and a slash is a path. Returns the cleaned name, or
## empty when it said why on the status line and there is nothing to do.
func _clean_name(text: String) -> String:
	var name := text.strip_edges()
	if name.is_empty():
		_say("A name cannot be empty", true)
		return ""
	if name.contains("/") or name.contains("\\") or name.contains(String.chr(0)) or name.contains("\n") or name.contains("\r"):
		# A slash is a move wearing a costume, and the costume ends in a file
		# created somewhere the screen is not showing.
		_say("A name cannot contain /", true)
		return ""
	if name == "." or name == "..":
		# Not a name at all: mkdir refuses both, and rename would either refuse
		# or do something nobody meant.
		_say("That is not a name", true)
		return ""
	return name


## mkdir, one level, in the folder on screen. Never recursive: a name with a
## slash in it is already refused above, so there is no second component to
## create, and make_dir_recursive_absolute would silently succeed on a path
## that already existed -- which is the one answer this must not give.
func _make_folder(text: String) -> void:
	var name := _clean_name(text)
	if name.is_empty():
		return
	var pane := _pane()
	if pane.path.is_empty():
		return

	var path := pane.path.path_join(name)
	if _exists(path):
		_say("Something called %s is already here" % name, true)
		return

	var err := DirAccess.make_dir_absolute(path)
	if err != OK:
		_say("Could not make %s (%s)" % [name, error_string(err)], true)
		ShellLog.error("files: mkdir of %s failed (%s)" % [path, error_string(err)])
		return

	_say("Made %s" % name)
	ShellLog.info("files: created folder %s" % path)
	_refresh_panes_showing(pane.path, name)


func _rename_to(text: String) -> void:
	if _menu_targets.size() != 1:
		return
	var old_path := str(_menu_targets[0].get("path", ""))
	var old_name := str(_menu_targets[0].get("name", ""))
	var new_name := _clean_name(text)

	if new_name.is_empty() or new_name == old_name:
		return

	var new_path := old_path.get_base_dir().path_join(new_name)
	if _exists(new_path):
		# Same rule as paste: never overwrite. rename_absolute would clobber an
		# existing file without a murmur.
		_say("Something called %s is already here" % new_name, true)
		return

	var err := DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		_say("Could not rename %s (%s)" % [old_name, error_string(err)], true)
		ShellLog.error("files: rename of %s to %s failed (%s)"
			% [old_path, new_path, error_string(err)])
		return

	# The clipboard may name the path that just stopped existing; follow it.
	var armed: Array = _clipboard.get("paths", [])
	for index in armed.size():
		if str(armed[index]) == old_path:
			armed[index] = new_path

	_say("Renamed %s to %s" % [old_name, new_name])
	ShellLog.info("files: renamed %s to %s" % [old_path, new_path])
	_refresh_panes_showing(old_path.get_base_dir(), new_name)


# ---------------------------------------------------------------------------
# Delete
# ---------------------------------------------------------------------------

## OS.move_to_trash, and NOTHING ELSE on failure. The trash is the honest
## reversible delete -- freedesktop trash, recoverable from any desktop that
## mounts the drive -- and a "helpful" fallback to permanent deletion would mean
## the exact same button press destroys data or does not depending on conditions
## the person cannot see. If the trash refuses, the file stays and the screen
## says so.
##
## Each item independently, for _paste_into's reason: three of four trashed is
## three files gone and one still there, which is a true and useful outcome.
func _delete_targets() -> void:
	if _menu_targets.is_empty():
		return

	var done := 0
	var first_error := ""
	var where := ""
	for entry in _menu_targets:
		var path := str(entry.get("path", ""))
		var target_name := str(entry.get("name", ""))
		if path.is_empty():
			continue
		if where.is_empty():
			where = path.get_base_dir()

		var err := FileTrash.trash(path)
		if err != OK:
			ShellLog.error("files: trash of %s failed (%s)" % [path, error_string(err)])
			if first_error.is_empty():
				first_error = "Could not move %s to the wastebasket (%s)" \
					% [target_name, error_string(err)]
			continue

		done += 1
		ShellLog.info("files: trashed %s" % path)
		# A clipboard naming a trashed path would paste an error later; disarm
		# it now, while the connection between the two is still on screen.
		var armed: Array = _clipboard.get("paths", [])
		if armed.has(path):
			_clipboard = {}

	if not first_error.is_empty():
		_say(first_error, true)
	elif done == 1:
		_say("Moved %s to the wastebasket" % str(_menu_targets[0].get("name", "")))
	else:
		_say("Moved %d items to the wastebasket" % done)

	_refresh_panes_showing(where, "")
	_refresh_trash()


# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------

func _open_properties() -> void:
	if _menu_targets.size() != 1 or _properties != null:
		return
	_properties = FileProperties.new()
	_properties.entry = _menu_targets[0]
	_properties.closed.connect(_on_properties_closed, CONNECT_ONE_SHOT)
	add_child(_properties)
	set_process_unhandled_input(false)


func _on_properties_closed() -> void:
	_close_properties.call_deferred()


func _close_properties() -> void:
	if _properties == null:
		return
	var panel := _properties
	_properties = null
	remove_child(panel)
	panel.queue_free()
	set_process_input(true)
	set_process_unhandled_input(true)
	_pane().grab_pane_focus(_return_focus_name)


# ---------------------------------------------------------------------------
# Eject
# ---------------------------------------------------------------------------

## Ask for the drive to be unmounted. THE SHELL DOES NOT UNMOUNT: umount(2)
## needs root, the shell runs as player, and every other privileged thing this
## appliance does goes through a request file that a root service consumes --
## see media.gd and /usr/lib/marwanos/usbmount. So this writes and waits.
func _eject_place() -> void:
	var path := str(_menu_place.get("path", ""))
	var place_name := str(_menu_place.get("name", ""))
	if path.is_empty():
		return

	# A pane still inside the drive would be showing a listing of a filesystem
	# that is about to go. Walk both of them home first, so the unmount is not
	# refused by the shell's own open directory handles.
	for pane in _panes:
		if pane.path == path or pane.path.begins_with(path + "/"):
			_send_home(pane)

	var armed: Array = _clipboard.get("paths", [])
	for source in armed:
		if str(source).begins_with(path + "/"):
			_clipboard = {}
			break

	Media.request_eject(path)
	# Said now rather than when the state file changes, for the store page's
	# reason: the request is consumed within half a second, and a screen that
	# does not change for two seconds is a screen that did not hear the press.
	# The outcome arrives on _on_media_state_changed and overwrites this.
	_say("Finishing writes to %s" % place_name)


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------

## Re-list every pane that is looking at a directory an operation just changed.
##
## BOTH PANES, and that is the whole reason this is a function. In a split view
## the destination of a paste is very often the folder the OTHER pane is
## showing -- that is what split view is for -- and a pane that did not redraw
## would be a directory listing that is quietly wrong about what is in it.
func _refresh_panes_showing(dir_path: String, focus_name: String) -> void:
	if dir_path.is_empty():
		_refresh_chrome()
		return
	var active := _active
	var owner := get_viewport().gui_get_focus_owner()
	for pane in _panes:
		if pane.path != dir_path:
			continue
		# The cursor is only aimed in the pane the person is in. The other one
		# redraws in place and keeps its own cursor, which is what makes a
		# paste into the far side of a split view not steal the selection you
		# were building on this side.
		pane.refresh(focus_name if pane == _panes[active] else "")
	_set_active(active)
	if is_instance_valid(owner) and owner.is_visible_in_tree():
		owner.grab_focus()
	_refresh_chrome()


## Every outcome, on screen and in the journal, always together: the person on
## the couch reads the line, and the person on the other end of ssh reads the
## journal, and neither should ever know more than the other.
func _say(text: String, alert: bool = false) -> void:
	if _status != null:
		_status.text = text
		_status.visible = not text.is_empty()
		_status.add_theme_color_override("font_color",
			TvTheme.TEXT_ALERT if alert else TvTheme.TEXT_SECONDARY)
	ShellLog.info("files: %s" % text)


func _choose_picker_entries(entries: Array) -> void:
	var paths := PackedStringArray()
	for entry in entries:
		var path := str(entry.get("path", ""))
		if bool(entry.get("is_dir", false)):
			continue
		if not picker_extensions.is_empty() and not picker_extensions.has(path.get_extension().to_lower()):
			continue
		if FileAccess.open(path, FileAccess.READ) != null:
			paths.append(path)
		if not picker_multiple and not paths.is_empty():
			break
	if paths.is_empty():
		_say("Choose a readable file", true)
		return
	_finish_picker(paths)

func _finish_picker(paths: PackedStringArray) -> void:
	if _picker_done:
		return
	_picker_done = true
	files_picked.emit(paths)
	closed.emit()

func _open_trash() -> void:
	_close_menu()
	_on_place_chosen({"name": "Trash bin", "path": FileTrash.LOCATION,
		"root": FileTrash.LOCATION, "root_label": "Trash bin"})


func _open_trash_actions() -> void:
	var items: Array = []
	_menu_place = _places.focused_place() if _places.has_focus_inside() else {}
	_menu_targets = [] if not _menu_place.is_empty() else _pane().target_entries()
	_return_focus_name = _pane().focused_name()
	if not _menu_place.is_empty():
		items.append({"id": "opentrash", "label": "Open trash bin", "icon": "trash"})
	elif not _menu_targets.is_empty():
		items.append({"id": "restoretrash", "label": _count_label("Restore", _menu_targets), "icon": "folder-open"})
	if FileTrash.has_contents():
		items.append({"id": "emptytrash", "label": "Empty trash bin", "icon": "trash"})
	if _menu_place.is_empty():
		for option in _view_options():
			if str(option["id"]) in ["refresh", "mode", "sort", "order", "split", "clearsearch", "selectall"]:
				items.append(option)
	_open_menu(items, "Trash bin", "Restore returns items to their original folders.")


func _confirm_empty_trash() -> void:
	if not FileTrash.has_contents():
		_say("Trash bin is empty")
		return
	_open_menu([
		{"id": "cancel", "label": "Cancel", "icon": "close"},
		{"id": "emptytrashconfirmed", "label": "Empty trash bin", "icon": "trash"}],
		"Empty trash bin?", "Permanently delete everything in the trash bin. This cannot be undone.")


func _restore_trash_entries(entries: Array) -> void:
	var restored := 0
	var first_error := ""
	for entry in entries:
		var result := FileTrash.restore(str(entry.get("trash_id", "")))
		if bool(result.get("ok", false)):
			restored += 1
			_refresh_panes_showing(str(result["path"]).get_base_dir(), str(result["path"]).get_file())
		elif first_error.is_empty():
			first_error = str(result["message"])
	_refresh_trash()
	_say(first_error if not first_error.is_empty() else "Restored %d item%s" % [restored, "" if restored == 1 else "s"], not first_error.is_empty())


func _refresh_trash() -> void:
	var active := _active
	var owner := get_viewport().gui_get_focus_owner()
	for pane in _panes:
		if pane.path == FileTrash.LOCATION:
			pane.refresh()
	_places.refresh_trash()
	_set_active(active)
	if is_instance_valid(owner) and owner.is_visible_in_tree():
		owner.grab_focus()
	elif not _modal_open() and _pane().path == FileTrash.LOCATION:
		_pane().grab_pane_focus()
