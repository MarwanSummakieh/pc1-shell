extends Button

## One thing in a file pane -- a folder or a file -- in whichever of the three
## view modes the pane is showing.
##
## ONE CLASS, THREE MODES, and that is the load-bearing decision in this file.
## Dolphin's Icons, Compact and Details are three layouts of the same object,
## and the temptation is three classes. It would be the wrong split: what has to
## be identical across the three is not the layout, it is the BEHAVIOUR --
## focus, the selection toggle, the check mark, the press, and the four boxes
## that encode selected-and-focused. Three classes would be three places for
## "selected looks focused" to creep back in, on the screen where a delete acts
## on the selection rather than on the cursor.
##
## A Button, for tile.gd's and settings_row.gd's reason: FOCUS_ALL and
## ui_accept-to-pressed come free, and a Panel would default to FOCUS_NONE and
## be unreachable from a pad.
##
## SELECTION IS TWO CHANNELS, never one. The box changes hue (see
## TvTheme.file_item_box) AND a check mark appears on the item. Colour alone is
## unreliable on a television -- the same argument the focus ring's three
## channels rest on -- and here the cost of misreading it is deleting the wrong
## thing.

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

## Toggled by X, emitted so the pane can keep the count and the status line.
signal selection_toggled(item: Button)

## The three layouts. Strings rather than an enum because the pane stores the
## mode in a plain variable that the view menu writes by id, and an enum would
## need a translation table at every edge.
const MODE_DETAILS := "details"
const MODE_ICONS := "icons"
const MODE_COMPACT := "compact"

## {path, name, is_dir, size, modified, is_link}. Set before add_child.
var entry: Dictionary = {}
var mode: String = MODE_DETAILS

## Which of the details view's right-hand columns this row has room for, and
## the floor the NAME keeps whatever happens. Decided by the pane, because only
## the pane knows how wide it is -- see FilePane._detail_columns.
##
## THE NAME WINS, ALWAYS, and that is the rule this exists to enforce. A Label
## with overrun trimming reports a 1 px minimum width, so an HBoxContainer will
## happily squeeze the expanding name down to nothing to satisfy two fixed
## columns -- which in a split view rendered every row in a folder of
## photographs as the word "ph". A name with no size beside it is a file
## manager; a size with no name is not.
var show_size := true
var show_date := true
var name_floor := 260

var _selected := false
var _thumb_rect: TextureRect = null
var _glyph: Label = null
var _check: Label = null


func setup(new_entry: Dictionary, view_mode: String) -> void:
	entry = new_entry
	mode = view_mode


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	text = ""

	match mode:
		MODE_ICONS:
			custom_minimum_size = Vector2(TvTheme.FILES_ICON_CELL, TvTheme.FILES_ICON_CELL_HEIGHT)
			size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		MODE_COMPACT:
			custom_minimum_size = Vector2(TvTheme.FILES_COMPACT_WIDTH, TvTheme.FILES_COMPACT_HEIGHT)
			size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_:
			custom_minimum_size = Vector2(0, TvTheme.FILES_DETAILS_HEIGHT)
			size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_apply_boxes()
	# Pressed is left equal to the focused box on purpose, unlike a settings
	# row: a press here always changes the screen (a folder opens, a file opens
	# or says why it cannot), so the box does not have to be the acknowledgement.
	add_theme_stylebox_override("focus", TvTheme.card_focus_ring())

	match mode:
		MODE_ICONS:
			_build_icon_cell()
		MODE_COMPACT:
			_build_compact_row()
		_:
			_build_details_row()

	focus_entered.connect(_apply_boxes)
	focus_exited.connect(_apply_boxes)


func _apply_boxes() -> void:
	var focused := has_focus()
	var box := TvTheme.file_item_box(_selected, focused)
	add_theme_stylebox_override("normal", box)
	# Hover matches normal for the rail's reason: there is no pointer on this
	# machine, and a mouse that wandered in should not light an item up.
	add_theme_stylebox_override("hover", box)
	add_theme_stylebox_override("pressed", TvTheme.file_item_box(_selected, true))
	add_theme_stylebox_override("disabled", box)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func is_selected() -> bool:
	return _selected


## Set without emitting -- for the pane's Select all / Clear, which changes
## hundreds of items and wants to count them once at the end rather than take
## a signal per item.
func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_apply_boxes()
	if _check != null:
		_check.visible = _selected


func toggle_selected() -> void:
	set_selected(not _selected)
	selection_toggled.emit(self)


# ---------------------------------------------------------------------------
# The three layouts
# ---------------------------------------------------------------------------

## Details: the mark, the name, then size and date on the right. Dolphin's
## default, and the one that answers "which of these is the big one" without
## opening anything.
func _build_details_row() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.SETTINGS_ROW_PAD)
	pad.add_theme_constant_override("margin_right", TvTheme.SETTINGS_ROW_PAD)
	add_child(pad)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", TvTheme.HINT_GLYPH_GAP)
	pad.add_child(row)

	row.add_child(_build_check())
	row.add_child(_build_mark(TvTheme.FILES_ROW_GLYPH_SIZE))

	var name_label := _label(_display_name(), TvTheme.SIZE_BODY, TvTheme.TEXT_PRIMARY)
	# THE NAME IS THE EXPANDING CHILD, settings_row.gd's lesson: a Label with
	# overrun trimming reports a 1 px minimum width, so a spacer taking the
	# slack would lay every name out one pixel wide. The floor is the other
	# half of that lesson -- see name_floor.
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(name_floor, 0)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	# Size then date, each in its own fixed-width column so the numbers line up
	# down the list rather than ragging against the name's length. Either can be
	# absent in a narrow pane; the date goes first, because "how big" is the
	# question a file manager gets asked and "when" is the one it gets asked
	# about the folder rather than about the row.
	if show_size:
		var size_label := _label(_size_text(), TvTheme.SIZE_SUPPLEMENTAL,
			TvTheme.TEXT_SECONDARY)
		size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		size_label.custom_minimum_size = Vector2(150, 0)
		row.add_child(size_label)

	if show_date:
		var date_label := _label(_date_text(), TvTheme.SIZE_SUPPLEMENTAL,
			TvTheme.TEXT_SECONDARY)
		date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		date_label.custom_minimum_size = Vector2(230, 0)
		row.add_child(date_label)


## Icons: a picture over a name. The mode thumbnails are FOR -- a folder of
## photographs is unreadable as a list of IMG_4417.JPG.
func _build_icon_cell() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	add_child(pad)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	pad.add_child(column)

	# The picture slot: the glyph and the thumbnail occupy the same box, one
	# visible at a time. Same box rather than a swap, so a thumbnail arriving
	# two frames later does not resize the cell and reflow the grid under the
	# cursor.
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(0, TvTheme.FILES_THUMB_SIZE)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(slot)

	_glyph = Icons.label(_mark_name(), TvTheme.FILES_THUMB_SIZE - 20, TvTheme.TEXT_PRIMARY)
	_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(_glyph)

	_thumb_rect = TextureRect.new()
	# KEEP_ASPECT_CENTERED and IGNORE_SIZE for tile.gd's reason: a picture that
	# is not square should letterbox inside the slot rather than stretch, and
	# the rect must be free to be smaller than its texture.
	_thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_thumb_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb_rect.visible = false
	slot.add_child(_thumb_rect)

	# The check rides over the picture's top-left in this mode -- there is no
	# row to put it at the start of, and a cell whose name is elided must still
	# be able to say it is selected.
	_check = Icons.label("check", 40, TvTheme.FOCUS_RING)
	_check.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_check.visible = _selected
	slot.add_child(_check)

	var name_label := _label(_display_name(), TvTheme.SIZE_SUPPLEMENTAL, TvTheme.TEXT_PRIMARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Two lines, then ellipsis. One line elides "Holiday photos 2024.jpg" down
	# to nothing useful; three would make the cell taller than the picture.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(name_label)


## Compact: the mark and the name, nothing else, in a narrow cell. Dolphin's
## third mode, and the one for a directory with two hundred things in it.
func _build_compact_row() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	add_child(pad)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	pad.add_child(row)

	row.add_child(_build_check())
	row.add_child(_build_mark(TvTheme.SIZE_BODY))

	var name_label := _label(_display_name(), TvTheme.SIZE_SUPPLEMENTAL, TvTheme.TEXT_PRIMARY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)


# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------

## The selection mark, and it occupies its width whether or not it is showing.
## A check that appeared and pushed the name sideways would make selecting
## things look like the list was moving.
func _build_check() -> Control:
	_check = Icons.label("check", TvTheme.SIZE_BODY, TvTheme.FOCUS_RING)
	_check.custom_minimum_size = Vector2(TvTheme.SIZE_BODY + 8, 0)
	_check.visible = _selected
	return _check


func _build_mark(size: int) -> Control:
	var mark := Icons.label(_mark_name(), size, TvTheme.TEXT_PRIMARY)
	mark.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return mark


func _mark_name() -> String:
	if bool(entry.get("is_dir", false)):
		return "folder"
	return "file"


## A LINK SAYS SO, because every verb on this screen treats one differently --
## the copy machinery refuses links outright -- and a link that looked like an
## ordinary file would make that refusal look arbitrary.
##
## Said in WORDS rather than with a mark, and that is a constraint rather than
## a preference: the vendored Phosphor build's post table carries no glyph
## names (see assets/phosphor/PROVENANCE.md), so a codepoint for a link icon
## would be a guess, and a wrong guess renders as a missing-glyph box on the
## one machine that matters. Three characters of text cannot be wrong.
func _display_name() -> String:
	var name := str(entry.get("name", ""))
	if bool(entry.get("is_link", false)):
		return "%s  (link)" % name
	return name


## A directory shows no size, tile-style: its size would be an entry count, and
## counting costs a directory read PER ROW. Fifty folders would be fifty extra
## reads to fill a column nobody asked for.
func _size_text() -> String:
	if bool(entry.get("is_dir", false)):
		return ""
	return human_size(int(entry.get("size", 0)))


func _date_text() -> String:
	var when := int(entry.get("modified", 0))
	if when <= 0:
		return ""
	var parts := Time.get_datetime_dict_from_unix_time(when)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(parts.get("year", 0)), int(parts.get("month", 0)), int(parts.get("day", 0)),
		int(parts.get("hour", 0)), int(parts.get("minute", 0))]


func _label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Bytes as a person reads them. Static and shared: the pane's status line and
## the properties panel say the same thing about the same file, and two copies
## of the rounding would disagree on the boundary.
static func human_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	var value := float(bytes)
	for unit in ["KB", "MB", "GB", "TB"]:
		value /= 1024.0
		if value < 1024.0 or unit == "TB":
			return "%.1f %s" % [value, unit]
	return ""


# ---------------------------------------------------------------------------
# Thumbnails
# ---------------------------------------------------------------------------

## Hand this item its picture. Only the icon mode has anywhere to put one --
## the other two draw a glyph at text size, where a 132 px photo scaled into a
## 30 px box is a smudge rather than a preview -- so the other two ignore it,
## and FileThumbs never asks for one it cannot use (see the pane).
func show_thumbnail(texture: Texture2D) -> void:
	if _thumb_rect == null or texture == null:
		return
	_thumb_rect.texture = texture
	_thumb_rect.visible = true
	if _glyph != null:
		_glyph.visible = false
