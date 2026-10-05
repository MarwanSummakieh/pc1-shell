extends Control

## Dolphin's properties dialog, at reading distance: what this thing is, how
## big, when it changed, who may touch it, and where it actually lives.
##
## WHY IT EARNS ITS PLACE ON A TELEVISION. Every other answer this screen can
## give is a listing, and a listing has room for a name and two columns. The
## questions that need a panel are the ones a person asks when something has
## gone wrong -- why will this not copy, is this the 40 GB one, is this file
## actually on the stick or is it a link to something that was -- and on a
## machine with no terminal there is nowhere else to ask them.
##
## READ-ONLY, and that is a decision rather than an omission. Dolphin's dialog
## edits permissions and the open-with association; both are settings a slipped
## thumb should not be able to change on somebody else's files, neither can be
## undone from this screen, and neither is a thing anyone needs from a sofa.
## A FOLDER'S SIZE IS NOT COMPUTED for the same reason the details view does
## not show one: it means walking the whole tree, which on a stick is seconds
## of a frozen screen for a number nobody asked for. The panel says how many
## things are directly inside instead, which is one read and is usually the
## question anyway.
##
## The frame, the scrim and the row rhythm are card_menu's and file_menu's, so
## this reads as the same family of centred panels rather than as a dialog box
## that wandered in from a desktop.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const FileItem = preload("res://src/file_item.gd")
const FileOpen = preload("res://src/file_open.gd")

const PANEL_WIDTH := 900

## card_menu's scrim, for card_menu's reason: there is nothing live underneath
## worth keeping visible -- only the listing the person just came from.
const SCRIM_ALPHA := 0.82

## {path, name, is_dir, is_link, ...}. Set before add_child.
var entry: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var scrim := ColorRect.new()
	scrim.color = Color(TvTheme.BACKGROUND.r, TvTheme.BACKGROUND.g,
		TvTheme.BACKGROUND.b, SCRIM_ALPHA)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	# PanelContainer, not Panel, for the reason app_overlay.gd spells out: Panel
	# computes nothing from its children and would draw a zero-height background
	# under spilled content.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(panel)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_right", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_top", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_bottom", TvTheme.STORE_PAGE_PAD)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	pad.add_child(column)

	var title := Label.new()
	title.text = str(entry.get("name", ""))
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 10)
	column.add_child(rows)

	for row in _facts():
		rows.add_child(_fact_row(str(row[0]), str(row[1])))

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)

	ShellLog.info("files: properties of %s" % str(entry.get("path", "")))


## Everything the panel says, as label/value pairs, in the order a person asks
## them. Built as data rather than as a run of add_child calls so a fact that
## has no answer on this file simply is not in the list -- an empty row reads as
## a rendering failure, and "Contents: " with nothing after it is worse than no
## line at all.
func _facts() -> Array:
	var path := str(entry.get("path", ""))
	var is_dir := bool(entry.get("is_dir", false))
	var facts: Array = []

	facts.append(["Type", _type_text(path, is_dir)])

	if is_dir:
		var count := _child_count(path)
		if count >= 0:
			facts.append(["Contents", "%d item%s" % [count, "" if count == 1 else "s"]])
	else:
		var size := _size_of(path)
		if size >= 0:
			# Both forms, because they answer different questions: "4.2 GB" is
			# whether it fits on the stick, and the exact byte count is whether
			# the copy that just finished produced the same file.
			facts.append(["Size", "%s  (%s bytes)"
				% [FileItem.human_size(size), _grouped(size)]])

	var modified := FileAccess.get_modified_time(path)
	if modified > 0:
		facts.append(["Modified", _timestamp(modified)])

	facts.append(["Permissions", _permissions_text(path)])
	# LAST AND IN FULL, never elided: the whole point of the line is telling
	# apart two files with the same name in different folders, which is exactly
	# the case an ellipsis would destroy. The panel wraps instead.
	facts.append(["Where", path])
	return facts


func _fact_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", TvTheme.HINT_GAP)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	label.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	label.custom_minimum_size = Vector2(240, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	value.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value)

	return row


## What this is, in words rather than in a MIME type. "video/x-matroska" is
## correct and tells a person on a sofa nothing; "Video (.mkv)" tells them why
## it reads as Media rather than as an opaque extension.
func _type_text(path: String, is_dir: bool) -> String:
	var link := bool(entry.get("is_link", false))
	if is_dir:
		return "Folder (link)" if link else "Folder"
	var ext := path.get_extension().to_lower()
	var kind := "File"
	if ext.is_empty():
		kind = "File (no extension)"
	else:
		kind = "%s (.%s)" % [_kind_for(ext), ext]
	return "%s -- link" % kind if link else kind


## The same families file_open.gd routes on, named for a person. Deliberately
## derived from the SAME extension lists rather than from a second table: a
## panel that called something a Video while A said something else about it would
## be the two disagreeing in the one place a person went to find out why.
func _kind_for(ext: String) -> String:
	if FileOpen.IMAGE_EXTENSIONS.has(ext):
		return "Picture"
	# Media is named from its own list rather than from a handler, because it
	# HAS no handler since Kodi left -- see FileOpen.MEDIA_EXTENSIONS. The
	# panel still calls a video a video; A on it is what says nothing opens it.
	if FileOpen.MEDIA_EXTENSIONS.has(ext):
		return "Media"
	var handler := str(FileOpen.HANDLERS.get(ext, ""))
	if handler == FileOpen.HANDLER_BROWSER:
		return "Document"
	return "File"


func _size_of(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return file.get_length()


## How many things are directly inside, hidden ones included -- the panel is
## where someone checks whether a copy landed complete, and the listing's
## dotfile policy is about what a couch needs to SEE, not about what is there.
## -1 for a directory that will not open, which is a real answer on a stick
## with a permissions problem and is why the caller drops the row.
func _child_count(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return -1
	dir.include_hidden = true
	return dir.get_directories().size() + dir.get_files().size()


## rwx for the three classes, the way `ls -l` writes it, because that is the
## form the answer is usually looked up in. Godot reports UNIX permissions as a
## bit field; anything it cannot answer (a filesystem with no POSIX modes --
## every FAT stick) says so rather than rendering as "---------", which would
## claim the file is unreadable when it is world-writable.
func _permissions_text(path: String) -> String:
	var bits := FileAccess.get_unix_permissions(path)
	if bits <= 0:
		return "not reported by this filesystem"
	var out := ""
	for shift: int in [6, 3, 0]:
		var group: int = (bits >> shift) & 0x7
		out += "r" if (group & 0x4) != 0 else "-"
		out += "w" if (group & 0x2) != 0 else "-"
		out += "x" if (group & 0x1) != 0 else "-"
	return "%s  (%o)" % [out, bits]


func _timestamp(unix_time: int) -> String:
	var parts := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d  %02d:%02d" % [
		int(parts.get("year", 0)), int(parts.get("month", 0)), int(parts.get("day", 0)),
		int(parts.get("hour", 0)), int(parts.get("minute", 0))]


## 1234567 as "1 234 567". Thin spaces rather than commas or dots, because both
## of those mean the decimal separator to somebody, and a size is the one number
## here that must not be misread by a factor of a thousand.
func _grouped(value: int) -> String:
	var digits := str(value)
	var out := ""
	var count := 0
	for index in range(digits.length() - 1, -1, -1):
		out = digits[index] + out
		count += 1
		if count % 3 == 0 and index > 0:
			out = " " + out
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
