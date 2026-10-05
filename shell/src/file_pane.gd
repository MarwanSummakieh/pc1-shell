extends PanelContainer

## ONE VIEW PANE: a breadcrumb and a directory, in one of Dolphin's three view
## modes, with its own path, its own sort order and its own selection.
##
## THIS FILE EXISTS SO THERE CAN BE TWO OF THEM. Split view is the reason --
## Dolphin's two-pane mode, and on a controller it is not a nicety but the
## single biggest thing the screen gained: copying a folder from a stick to
## Home stops being "copy, walk out to Places, walk into Home, walk down two
## levels, paste" and becomes "point the other side at Home once, then copy and
## paste with both ends visible". Everything a pane knows is therefore per-pane
## and nothing is global: two panes can be in different folders, sorted
## differently, in different view modes, with different things selected, and
## neither can reach into the other.
##
## NAVIGATION IS THE SETTINGS LIST'S TABLE, GROWN A SECOND AXIS. One explicit
## neighbour table, hard stops at every edge, and the two edges that are NOT
## stops are the ones the screen sets: left out of the leftmost column and right
## out of the rightmost go to whatever the screen put there (the Places column,
## or the other pane). Nothing is left to Control's geometric search, which is
## the rule that has kept every screen in this shell predictable.
##
## THE BREADCRUMB IS FOCUSABLE, and it is not decoration. Dolphin's is
## clickable; on a pad it is how you get from
## /run/media/player/USB/Photos/2024/June back to the drive in two presses
## instead of four B's. Up from the first row of items lands on it.
##
## WHAT IS DELIBERATELY NOT HERE: the clipboard, the file operations, the
## options menu and the status line. A pane renders a directory and reports
## what happened to it; files_screen owns every consequence. That is what lets
## the same four hundred lines be the left pane and the right pane without
## either of them knowing the other exists.

const TvTheme = preload("res://src/tv_theme.gd")
const FileItem = preload("res://src/file_item.gd")
const FileThumbs = preload("res://src/file_thumbs.gd")

## A on an item. The screen decides what opening means -- descend, view, launch
## or explain -- because only it knows about the launch seam and the viewer.
signal activated(entry: Dictionary)

## Anything inside this pane took focus. The screen uses it to move the active
## frame and to re-aim the hint row, which is per-pane.
signal became_active()

## The listing changed under the cursor, or the cursor moved to a different
## item, or the selection did. One signal for all three: every consumer (the
## hint row, the status line, the active-pane header) re-reads the whole pane
## anyway, and three signals would only mean three places to forget one.
signal view_changed()

## B at the pane's floor -- see PLACE_ROOT below. The screen turns it into
## "focus the Places column", because a pane cannot know what is beside it.
signal exit_up()

const MODE_DETAILS := FileItem.MODE_DETAILS
const MODE_ICONS := FileItem.MODE_ICONS
const MODE_COMPACT := FileItem.MODE_COMPACT

## Sort keys, matching what the view menu offers. "type" sorts by extension and
## then by name, which is what makes it useful at all -- grouping every .jpg
## together and then leaving them in arrival order would be half a sort.
const SORT_NAME := "name"
const SORT_SIZE := "size"
const SORT_DATE := "date"
const SORT_TYPE := "type"

## How many columns the grid modes use. Icons is sized so a cell plus its gap
## divides the pane at the design width in a split view and still gives four
## across when the pane has the screen to itself -- computed rather than fixed,
## because the design surface is 1920 on a 16:9 panel and ~2580 on the owner's
## ultrawide (see project.godot's stretch note), and a hard-coded column count
## would leave a stripe of empty pane on one of them.
const GRID_MIN_COLUMNS := 1

# --- what this pane is showing -------------------------------------------

var path: String = ""

## THE FLOOR. B walks up one level until it reaches this, and then leaves the
## pane entirely rather than continuing into /home or /run/media/<user>. Those
## are plumbing, and B walking into them would put the whole filesystem one
## held button away from the couch -- the rule the single-pane version had, and
## the reason a pane is always inside a "place" rather than adrift at /.
var place_root: String = ""

## What to call `place_root` in the breadcrumb. Set by the screen alongside it,
## because the pane must not re-derive it: the root of the Home place is
## /var/home/player, which is not a name to put on a television, and working
## out that it should read "Home" means knowing the same $HOME fallback chain
## the Places column already owns. One copy of that chain, in the object that
## builds the places.
var place_label: String = ""

var mode: String = MODE_DETAILS
var sort_key: String = SORT_NAME
var sort_descending: bool = false
var show_hidden: bool = false
var search_text := ""
var file_extensions := PackedStringArray()
var _history: Array = []
var _history_index := -1
var _history_jump := false

## Is this pane sharing the screen with the other one? Set by the screen when
## the split opens or closes. It is the only input to the details view's column
## budget -- see _detail_columns.
var narrow := false

# --- what it is made of ---------------------------------------------------

var _crumb_bar: HBoxContainer = null
var _crumb_scroll: ScrollContainer = null
var _scroll: ScrollContainer = null
var _grid: GridContainer = null
var _empty: Label = null
var _crumbs: Array = []
var _items: Array = []
var _columns: int = 1

var _thumbs: FileThumbs = FileThumbs.new()
var _active := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", TvTheme.pane_frame(false))

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.FILES_PANE_PAD)
	pad.add_theme_constant_override("margin_right", TvTheme.FILES_PANE_PAD)
	pad.add_theme_constant_override("margin_top", TvTheme.FILES_PANE_PAD)
	pad.add_theme_constant_override("margin_bottom", TvTheme.FILES_PANE_PAD)
	add_child(pad)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	pad.add_child(column)

	# The breadcrumb scrolls HORIZONTALLY and nothing else does. A deep path has
	# more crumbs than fit, and the alternative -- eliding the path to a string
	# -- is what the single-pane version did and what made walking back up a
	# guess. follow_focus keeps the focused crumb on screen.
	_crumb_scroll = ScrollContainer.new()
	_crumb_scroll.follow_focus = true
	_crumb_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_crumb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_crumb_scroll.custom_minimum_size = Vector2(0, TvTheme.FILES_COMPACT_HEIGHT)
	_crumb_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_crumb_scroll)

	_crumb_bar = HBoxContainer.new()
	_crumb_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crumb_bar.add_theme_constant_override("separation", 6)
	_crumb_scroll.add_child(_crumb_bar)

	_scroll = ScrollContainer.new()
	# The settings screen's scrolling, for the settings screen's reason: a long
	# directory reaches below the safe area, the focus chain does not care, and
	# a focused row off the bottom of a TV is a screen that silently ends early.
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = 1
	_grid.add_theme_constant_override("h_separation", TvTheme.SETTINGS_ROW_GAP)
	_grid.add_theme_constant_override("v_separation", TvTheme.SETTINGS_ROW_GAP)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_grid)

	# The honest empty state, in the pane rather than on the screen: with two
	# panes up, "Nothing in this folder" has to say WHICH folder by being drawn
	# inside it.
	_empty = Label.new()
	_empty.text = "Nothing in this folder"
	_empty.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_empty.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_empty.visible = false
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_empty)

	# THE GRID MODES DEPEND ON THE PANE'S WIDTH, and the width changes twice in
	# a session for reasons that are not a listing: the first layout pass (when
	# the pane's rect is still zero and _column_count has to fall back to one),
	# and the split opening or closing, which halves it. Re-wiring on resize is
	# what keeps a four-column icon grid from staying four columns in half the
	# space. Details mode is a single column at any width and short-circuits.
	resized.connect(_on_resized)

	# Thumbnail decoding is budgeted per RENDERED frame -- see FileThumbs. The
	# pane only processes while it has something queued, so an idle pane costs
	# nothing per frame.
	set_process(true)


## Only the GRID modes care about the pane's width, and only for how many
## columns to flow into -- which is a re-wiring, not a rebuild, so it is safe
## to do here. Details rows are decided by `narrow`, not by measurement; see
## _detail_columns for why that distinction was paid for.
func _on_resized() -> void:
	if mode == MODE_DETAILS or _items.is_empty():
		return
	var wanted := _column_count()
	if wanted == _columns:
		return
	_columns = wanted
	_grid.columns = wanted
	# The items themselves are unchanged -- only which of them are neighbours.
	_wire_focus()


func _process(_delta: float) -> void:
	_thumbs.pump()


# ---------------------------------------------------------------------------
# Listing
# ---------------------------------------------------------------------------

## Point the pane at a directory. `focus_name` is the entry to land the cursor
## on -- how ascending puts the cursor back on the folder just left, and how an
## operation re-focuses the thing it touched.
##
## A FAILED OPEN CHANGES NOTHING. Returning false with the old listing still on
## screen beats clearing the pane: a failed descent that also lost the current
## view would be two failures for one press.
func show_directory(new_path: String, focus_name: String = "") -> bool:
	# `=` rather than `:=`, because _read returns Variant on purpose -- null is
	# how a failed open is reported, and that is the whole of the next two lines.
	# Inferring from it is a warning, this project treats warnings as errors, and
	# the result was an export whose Files, Settings, Stores and Power autoloads
	# all failed to compile in the editor's scan. The same idiom the storefront
	# already uses for JSON.parse_string, for the same reason.
	var previous_search := search_text
	if path != new_path:
		search_text = ""
	var listing = _read(new_path)
	if listing == null:
		search_text = previous_search
		return false

	if path != new_path:
		if not _history_jump:
			_history = _history.slice(0, _history_index + 1)
			_history.append(new_path)
			_history_index = _history.size() - 1
	path = new_path
	# Everything queued for the folder we are leaving is abandoned. Without
	# this, walking down through five folders of photographs leaves five
	# folders' worth of decodes running for pictures nobody is looking at.
	_thumbs.cancel()

	_build_crumbs()
	_build_items(listing)
	_focus_named(focus_name)

	ShellLog.info("files: pane at %s (%d entries, %s, by %s%s%s)"
		% [path, _items.size(), mode, sort_key,
			" descending" if sort_descending else "",
			", hidden shown" if show_hidden else ""])
	view_changed.emit()
	return true


## Re-list the same directory: after an operation changed it, or after a view
## setting changed what should be on screen or in what order.
func refresh(focus_name: String = "") -> void:
	if path.is_empty():
		return
	var keep := focus_name
	if keep.is_empty():
		keep = focused_name()
	# The selection is dropped on purpose. It names entries by path, and a
	# refresh happens exactly when those may have been renamed, moved or
	# deleted -- carrying a selection across it is how a bulk delete ends up
	# acting on something the person cannot see any more.
	show_directory(path, keep)


## Up one level, or out of the pane at the floor. See `place_root`.
func go_up() -> void:
	if path.is_empty() or path == place_root:
		exit_up.emit()
		return
	var leaving := path.get_file()
	show_directory(path.get_base_dir(), leaving)


## {dirs: [...], files: [...]} as entry dictionaries, or null when the
## directory will not open.
##
## THE STAT IS CONDITIONAL, and that is the one performance decision in here. A
## size costs an open() and a modified time costs a stat, per entry -- four
## hundred syscalls for a folder of two hundred. The details view shows both
## and the size and date sorts need both, so those pay; the icon and compact
## views sorted by name or type need neither and do not. A folder of photographs
## browsed as icons is the case this exists for, and it is also the biggest
## folder anyone will point this at.
func _read(dir_path: String) -> Variant:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		ShellLog.warn("files: could not open %s (%s)"
			% [dir_path, error_string(DirAccess.get_open_error())])
		return null

	# Dolphin's "show hidden files", and the shell's dotfile policy is simply
	# the default left alone: get_directories/get_files skip hidden entries
	# unless told otherwise. A television is not a shell prompt, so .config is
	# plumbing nobody navigates to from a couch -- until they say otherwise.
	dir.include_hidden = show_hidden

	var need_stat := mode == MODE_DETAILS or sort_key == SORT_SIZE or sort_key == SORT_DATE

	var dirs: Array = []
	for entry_name in dir.get_directories():
		if search_text.is_empty() or entry_name.to_lower().contains(search_text.to_lower()):
			dirs.append(_entry(dir, dir_path, entry_name, true, need_stat))
	var files: Array = []
	for entry_name in dir.get_files():
		if not search_text.is_empty() and not entry_name.to_lower().contains(search_text.to_lower()):
			continue
		if not file_extensions.is_empty() and not file_extensions.has(entry_name.get_extension().to_lower()):
			continue
		files.append(_entry(dir, dir_path, entry_name, false, need_stat))

	_sort(dirs)
	_sort(files)
	# FOLDERS FIRST, ALWAYS, which is Dolphin's default and not a preference
	# this screen offers to turn off: a directory is a place and a file is a
	# thing, and interleaving them by size puts a 4 KB folder between two
	# photographs for no reason anyone navigating has.
	return {"dirs": dirs, "files": files}


func _entry(dir: DirAccess, dir_path: String, entry_name: String,
		is_dir: bool, need_stat: bool) -> Dictionary:
	var full := dir_path.path_join(entry_name)
	var record := {
		"path": full,
		"name": entry_name,
		"is_dir": is_dir,
		# Asked of the PARENT directory, because DirAccess resolves the path
		# being opened but reports honestly about the names inside it.
		"is_link": dir.is_link(entry_name),
		"size": 0,
		"modified": 0,
	}
	if not need_stat:
		return record

	record["modified"] = FileAccess.get_modified_time(full)
	if not is_dir:
		# FileAccess.open + get_length stats the file without reading it;
		# get_file_as_bytes would pull the whole thing through memory to
		# measure it, which on a 40 GB rip is not a size query, it is an
		# accident. An unreadable file keeps a size of zero and still lists.
		var file := FileAccess.open(full, FileAccess.READ)
		if file != null:
			record["size"] = file.get_length()
	return record


func _sort(entries: Array) -> void:
	var key := sort_key
	var descending := sort_descending
	var by := func(a: Dictionary, b: Dictionary) -> bool:
		var result := false
		match key:
			SORT_SIZE:
				# Ties fall through to the name, so two 4 KB files are in a
				# stable, readable order rather than in whatever order the
				# filesystem happened to hand them over.
				if int(a["size"]) != int(b["size"]):
					result = int(a["size"]) < int(b["size"])
				else:
					result = _name_less(a, b)
			SORT_DATE:
				if int(a["modified"]) != int(b["modified"]):
					result = int(a["modified"]) < int(b["modified"])
				else:
					result = _name_less(a, b)
			SORT_TYPE:
				var ea := str(a["name"]).get_extension().to_lower()
				var eb := str(b["name"]).get_extension().to_lower()
				if ea != eb:
					result = ea < eb
				else:
					result = _name_less(a, b)
			_:
				result = _name_less(a, b)
		return not result if descending else result
	entries.sort_custom(by)


## Case-insensitive and natural, so "Downloads" and "docs" interleave the way a
## person alphabetises rather than the way ASCII does, and "Episode 9" comes
## before "Episode 10".
static func _name_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0


# ---------------------------------------------------------------------------
# The items
# ---------------------------------------------------------------------------

func _build_items(listing: Dictionary) -> void:
	_empty.text = "Nothing in this folder" if search_text.is_empty() else "No matching files"
	for item in _items:
		_grid.remove_child(item)
		item.queue_free()
	_items.clear()

	_columns = _column_count()
	_grid.columns = _columns

	var entries: Array = []
	entries.append_array(listing["dirs"])
	entries.append_array(listing["files"])

	var columns := _detail_columns()

	for entry in entries:
		var item := FileItem.new()
		item.setup(entry, mode)
		item.show_size = bool(columns["size"])
		item.show_date = bool(columns["date"])
		item.name_floor = int(columns["floor"])
		item.pressed.connect(_on_item_pressed.bind(item))
		item.focus_entered.connect(_on_item_focused.bind(item))
		item.selection_toggled.connect(_on_selection_toggled)
		_grid.add_child(item)
		_items.append(item)

		# Only the icon view has anywhere to put a picture -- see
		# FileItem.show_thumbnail -- so the other modes never queue a decode.
		# This is what makes switching to details instant in a photo folder.
		if mode == MODE_ICONS and not bool(entry["is_dir"]) \
				and FileThumbs.can_preview(str(entry["name"])):
			_thumbs.request(str(entry["path"]), item)

	_empty.visible = _items.is_empty()
	_wire_focus()


## WHICH DETAILS COLUMNS THIS PANE CAN AFFORD, and the floor the name keeps.
##
## Dolphin resizes its columns with a mouse. There is no mouse, so the choice
## is made from `narrow`, which the SCREEN sets when it opens or closes the
## split -- see FilePane.set_narrow.
##
## MEASURING THE PANE'S OWN RECT WAS TRIED FIRST AND WAS WRONG, which is worth
## recording because it is the obvious implementation. A measured budget
## changes on a resize notification, a resize notification therefore has to
## rebuild the rows, and rebuilding rows deferred out of a layout pass meant
## the listing could be replaced under a press that was already in flight --
## which the Xvfb run caught as a Return that re-listed the current folder
## instead of entering the one under the cursor. The split state is the same
## information arriving a frame earlier, from the object that decided it, with
## no feedback loop through layout.
func _detail_columns() -> Dictionary:
	if narrow:
		# The date goes first, because "how big" is the question a file manager
		# gets asked and "when" is the one it gets asked about the folder rather
		# than about the row.
		return {"size": true, "date": false, "floor": 200}
	return {"size": true, "date": true, "floor": 260}


## How many columns fit. Measured off the pane's real width rather than off
## BASE_WIDTH: the design surface is wider on an ultrawide, and a split view
## halves whatever it is -- so the only honest source is the rect this pane was
## actually given. Before the first layout that rect is zero, which is what the
## floor of GRID_MIN_COLUMNS is for; the next listing corrects it.
func _column_count() -> int:
	if mode == MODE_DETAILS:
		return 1
	var cell := TvTheme.FILES_ICON_CELL if mode == MODE_ICONS else TvTheme.FILES_COMPACT_WIDTH
	var available := size.x - 2 * TvTheme.FILES_PANE_PAD - 2 * TvTheme.PANE_BORDER_WIDTH
	if available <= 0.0:
		return GRID_MIN_COLUMNS
	var gap := TvTheme.SETTINGS_ROW_GAP
	return maxi(GRID_MIN_COLUMNS, int((available + gap) / (cell + gap)))


## The explicit neighbour table, on both axes, and EVERY EDGE OF THE PANE IS A
## HARD STOP -- pointed at self.
##
## Crossing into the Places column or the other pane is not done here, and the
## reason is a Godot mechanic worth naming. A focus_neighbor NodePath has to
## resolve to a focusable Control, and the things on either side of a pane are
## a CONTAINER (the Places column) whose focusable rows are rebuilt whenever a
## drive appears, and another pane whose rows are rebuilt on every listing --
## so any path stored here is a path to a node that will not exist shortly.
## Pointing at self instead means the viewport's GUI layer finds no neighbour
## and therefore does NOT consume the press, which drops it into
## files_screen._unhandled_input, where the region crossing is done by asking
## the regions what they currently contain. One mechanism, no stale paths.
func _wire_focus() -> void:
	var count := _items.size()
	for index in count:
		var item: Control = _items[index]
		var col := index % _columns
		var row := index / _columns

		var left: Control = item
		if col > 0:
			left = _items[index - 1]

		var right: Control = item
		if col + 1 < _columns and index + 1 < count:
			right = _items[index + 1]

		var up: Control = item
		if row > 0:
			up = _items[index - _columns]
		elif not _crumbs.is_empty():
			# The top row goes to the breadcrumb -- the LAST crumb, which is the
			# folder being shown, so up-then-down is a round trip.
			up = _crumbs[_crumbs.size() - 1]

		var down: Control = item
		if index + _columns < count:
			down = _items[index + _columns]
		elif row < (count - 1) / _columns:
			# The row below exists but is shorter than this column reaches: its
			# last item, rather than a dead press.
			down = _items[count - 1]

		item.focus_neighbor_left = item.get_path_to(left)
		item.focus_neighbor_right = item.get_path_to(right)
		item.focus_neighbor_top = item.get_path_to(up)
		item.focus_neighbor_bottom = item.get_path_to(down)

	_wire_crumb_focus()


# ---------------------------------------------------------------------------
# The breadcrumb
# ---------------------------------------------------------------------------

## One button per component of the path, from the place's root down. NEVER
## ABOVE THE ROOT: the crumbs stop where B stops, for the same reason -- /home
## and /run/media/<user> are plumbing, and a crumb for them would be a
## one-press door into the whole filesystem.
func _build_crumbs() -> void:
	for crumb in _crumbs:
		_crumb_bar.remove_child(crumb)
		crumb.queue_free()
	_crumbs.clear()

	var trail: Array = []
	var walk := path
	while true:
		trail.push_front(walk)
		if walk == place_root or walk.get_base_dir() == walk or walk.is_empty():
			break
		walk = walk.get_base_dir()

	for index in trail.size():
		var crumb_path := str(trail[index])
		# The root crumb is named for the PLACE -- "Home", "USB_DRIVE" -- not
		# for its directory, which is /var/home/player and means nothing.
		var label := crumb_path.get_file()
		if crumb_path == place_root and not place_label.is_empty():
			label = place_label
		_crumbs.append(_build_crumb(label, crumb_path, index == trail.size() - 1))

	for crumb in _crumbs:
		_crumb_bar.add_child(crumb)


func _build_crumb(label: String, crumb_path: String, is_last: bool) -> Button:
	var crumb := Button.new()
	crumb.text = "  %s  " % label
	crumb.focus_mode = Control.FOCUS_ALL
	crumb.custom_minimum_size = Vector2(0, TvTheme.FILES_COMPACT_HEIGHT - 8)
	crumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crumb.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	# The LAST crumb is where you are, and it is drawn as the lit one -- the
	# same "you are here" the path label used to carry as plain text.
	var idle := TvTheme.file_item_box(is_last, false)
	crumb.add_theme_stylebox_override("normal", idle)
	crumb.add_theme_stylebox_override("hover", idle)
	crumb.add_theme_stylebox_override("pressed", TvTheme.file_item_box(is_last, true))
	crumb.add_theme_stylebox_override("focus", TvTheme.card_focus_ring())
	crumb.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	crumb.add_theme_color_override("font_focus_color", TvTheme.TEXT_PRIMARY)
	crumb.add_theme_color_override("font_hover_color", TvTheme.TEXT_PRIMARY)
	crumb.add_theme_color_override("font_pressed_color", TvTheme.TEXT_PRIMARY)
	crumb.set_meta("crumb_path", crumb_path)
	crumb.pressed.connect(_on_crumb_pressed.bind(crumb))
	crumb.focus_entered.connect(_on_any_focus)
	return crumb


func _wire_crumb_focus() -> void:
	var count := _crumbs.size()
	for index in count:
		var crumb: Control = _crumbs[index]
		var left: Control = crumb
		if index > 0:
			left = _crumbs[index - 1]
		var right: Control = crumb
		if index + 1 < count:
			right = _crumbs[index + 1]

		crumb.focus_neighbor_left = crumb.get_path_to(left)
		crumb.focus_neighbor_right = crumb.get_path_to(right)
		# Nothing above the crumb bar inside a pane; pointed at self so the
		# geometric search cannot wander into another pane's rows.
		crumb.focus_neighbor_top = crumb.get_path_to(crumb)
		crumb.focus_neighbor_bottom = crumb.get_path_to(
			_items[0] if not _items.is_empty() else crumb)


func _on_crumb_pressed(crumb: Button) -> void:
	var target := str(crumb.get_meta("crumb_path", ""))
	if target.is_empty() or target == path:
		return
	# Landing on the child we came out of, so pressing a crumb and then pressing
	# B is a round trip rather than a jump followed by a slow walk back.
	var came_from := path.get_file() if path.begins_with(target + "/") else ""
	show_directory(target, came_from)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

## Every selected entry, as its record. Order is the pane's own order, which is
## what makes a bulk copy land in a predictable sequence and the status line's
## "3 of 40" mean something.
func selected_entries() -> Array:
	var result: Array = []
	for item in _items:
		if item.is_selected():
			result.append(item.entry)
	return result


func selection_count() -> int:
	var count := 0
	for item in _items:
		if item.is_selected():
			count += 1
	return count


## THE VERBS ACT ON THE SELECTION IF THERE IS ONE, AND ON THE CURSOR IF NOT.
## That single rule is what keeps multi-select from being a mode: nothing has
## to be turned on, and X on nothing selected followed by a Delete does exactly
## what the same Delete would have done without the X.
func target_entries() -> Array:
	var chosen := selected_entries()
	if not chosen.is_empty():
		return chosen
	var here := focused_entry()
	return [] if here.is_empty() else [here]


func toggle_focused_selection() -> void:
	var item := _focused_item()
	if item == null:
		return
	item.toggle_selected()


## Select all, or clear -- one verb, because on a pad the same button should
## undo itself. Dolphin has Ctrl+A and Ctrl+Shift+A; this screen has one press
## that means "all" until everything is selected and "none" after that.
func toggle_select_all() -> void:
	var everything := selection_count() < _items.size()
	for item in _items:
		item.set_selected(everything)
	view_changed.emit()


func clear_selection() -> void:
	for item in _items:
		item.set_selected(false)
	view_changed.emit()


func _on_selection_toggled(_item: Button) -> void:
	view_changed.emit()


# ---------------------------------------------------------------------------
# Focus and the cursor
# ---------------------------------------------------------------------------

func focused_entry() -> Dictionary:
	var item := _focused_item()
	return {} if item == null else item.entry


func focused_name() -> String:
	return str(focused_entry().get("name", ""))


func _focused_item() -> Button:
	var owner := get_viewport().gui_get_focus_owner()
	for item in _items:
		if item == owner:
			return item
	return null


## Does anything inside this pane hold focus? Asked of the tree rather than
## tracked with a flag: focus can be moved by a neighbour table, by a grab
## anywhere else, or by a node being freed, and a flag would be wrong after any
## of the three.
func has_focus_inside() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null:
		return false
	return is_ancestor_of(owner)


## Put the cursor somewhere sensible in this pane. By NAME rather than by index,
## because every operation rebuilds the list and the replacement may be longer,
## shorter or reordered.
func grab_pane_focus(entry_name: String = "") -> void:
	if not _focus_named(entry_name):
		if not _crumbs.is_empty():
			var last: Control = _crumbs[_crumbs.size() - 1]
			last.grab_focus()


func _focus_named(entry_name: String) -> bool:
	if not entry_name.is_empty():
		for item in _items:
			if str(item.entry.get("name", "")) == entry_name:
				item.grab_focus()
				return true
	if not _items.is_empty():
		var first: Control = _items[0]
		first.grab_focus()
		return true
	return false


func _on_item_focused(item: Control) -> void:
	_on_any_focus()
	# Deferred for settings_screen's reason: the first call arrives from a
	# grab_focus before the scroll container has been laid out, and asking an
	# unsized viewport to reveal a control scrolls it nowhere.
	_reveal.call_deferred(item)
	view_changed.emit()


## THE DEFERRAL OUTLIVES THE ROW, which is why this is a guarded method rather
## than a deferred call straight to ensure_control_visible. A re-listing between
## the focus and the deferred call -- the split opening is one, and it happens
## exactly while focus is moving -- removes the item from the grid, and
## ScrollContainer refuses a control that is no longer inside it with "Must be
## an ancestor of the control" in the journal. Harmless, and precisely the kind
## of line that trains someone to ignore errors on a machine whose journal is
## the only witness.
func _reveal(item: Control) -> void:
	if _scroll == null or not is_instance_valid(item):
		return
	if not _scroll.is_ancestor_of(item):
		return
	_scroll.ensure_control_visible(item)


func _on_any_focus() -> void:
	became_active.emit()


func _on_item_pressed(item: Button) -> void:
	activated.emit(item.entry)


# ---------------------------------------------------------------------------
# What the screen sets
# ---------------------------------------------------------------------------

## Is the cursor on the leftmost column, or the rightmost? The screen asks
## before it crosses regions, because "left" inside a grid means the previous
## item until it means the previous REGION, and only the pane knows which.
## A crumb counts as neither edge except at the ends of the trail.
func at_left_edge() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	var index := _items.find(owner)
	if index != -1:
		return index % _columns == 0
	var crumb := _crumbs.find(owner)
	return crumb == 0


func at_right_edge() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	var index := _items.find(owner)
	if index != -1:
		return index % _columns == _columns - 1 or index == _items.size() - 1
	var crumb := _crumbs.find(owner)
	return crumb != -1 and crumb == _crumbs.size() - 1


## The coloured frame. Only one pane wears it, and it is the only thing on
## screen that says which side a paste would land in -- "the one with the focus
## ring in it" is not readable when the ring is on a row halfway down a list
## you are not looking at.
func set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	add_theme_stylebox_override("panel", TvTheme.pane_frame(value))


## Sharing the screen, or not. Re-lists only when the answer changed and only
## when there is something on screen to re-list -- the screen calls this on
## every re-wiring, including ones where nothing moved.
func set_narrow(value: bool) -> void:
	if narrow == value:
		return
	narrow = value
	if not path.is_empty():
		refresh()


## A view setting changed. All four go through one function because all four
## end in the same place -- re-read the directory and redraw -- and three of
## them (hidden, sort, sort direction) change what _read even collects.
func set_view(new_mode: String, key: String, descending: bool, hidden: bool) -> void:
	mode = new_mode
	sort_key = key
	sort_descending = descending
	show_hidden = hidden
	refresh()


## Every previewable picture in this listing, in the pane's own order, for the
## image viewer's left/right. Handed over rather than re-derived by the viewer
## so "next picture" means the next one down the screen the person is looking
## at, not the next one by some rule the viewer invented.
func image_paths() -> Array:
	var result: Array = []
	for item in _items:
		var entry: Dictionary = item.entry
		if bool(entry.get("is_dir", false)):
			continue
		if FileThumbs.can_preview(str(entry.get("name", ""))):
			result.append(str(entry.get("path", "")))
	return result


func set_search(query: String) -> void:
	search_text = query.strip_edges()
	refresh()

func history_move(direction: int) -> bool:
	var next := _history_index + direction
	if next < 0 or next >= _history.size():
		return false
	_history_jump = true
	var result := show_directory(str(_history[next]))
	_history_jump = false
	if result:
		_history_index = next
	return result
