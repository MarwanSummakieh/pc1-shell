extends Control

## THE options menu: a titled panel of rows over a dimmed screen, one axis, B
## closes. Used for a rail card, a store card and a file, and there is no
## fourth kind waiting to be special.
##
## THIS FILE IS card_menu.gd AND file_menu.gd, WHICH WERE THE SAME FILE TWICE.
## Both built the same scrim, the same CenterContainer, the same PanelContainer
## at the same 720, the same padding, the same title label, the same row box,
## the same optional note, the same two hints and the same focus table -- about
## a hundred lines that differed in a log string. file_menu's own header argued
## the fork was right ("card_menu knows about applications... threading 'unless
## it is a file' through it would cost more lines than this file is"), and that
## was true of the version it was looking at, because card_menu hard-coded its
## one item and acted on it internally. The fix was not to thread a condition
## through: it was to take card_menu's decisions OUT -- the items arrive as
## data, the choice leaves as an id -- at which point the two files were
## textually the same object and one of them was deleted.
##
## THE MENU DECIDES NOTHING, which is file_menu's rule and now everyone's. The
## caller owns the items, the consequences and the wording: shell_root and
## stores_screen pass Uninstall and price the re-download, files_screen passes
## whatever the clipboard state allows. That is what lets one panel serve
## "options on this application" and "paste into this empty folder" without
## knowing the difference between them.

signal closed()
signal chosen(id: String)

const TvTheme = preload("res://src/tv_theme.gd")
const AppMenuRow = preload("res://src/app_menu_row.gd")

const MENU_WIDTH := 720

## Heavier than the app overlay's scrim, and for the reason card_menu gave: no
## live application is underneath worth keeping visible -- only the rail or the
## file list the person just came from and is about to come back to. The app
## overlay is the one that must stay see-through, and it is a different file
## because it is composited over a running client by gamescope.
const SCRIM_ALPHA := 0.82

## What the menu is about -- an application title, a file name. Set before
## add_child.
var title_text: String = ""

## The rows, as [{id, label, icon}] dictionaries. Set before add_child. Which
## items exist is the caller's call: Paste only when the clipboard is armed,
## Uninstall only for something actually installed.
var items: Array = []

## One optional sentence under the rows -- the slot the card menu prices a
## re-download in. Empty means none.
var note_text: String = ""

var _rows: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build()
	TvTheme.wire_column(_rows)

	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("menu up for %s with %d item(s)" % [title_text, _rows.size()])


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(TvTheme.BACKGROUND.r, TvTheme.BACKGROUND.g, TvTheme.BACKGROUND.b, SCRIM_ALPHA)
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
	panel.custom_minimum_size = Vector2(MENU_WIDTH, 0)
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
	title.text = title_text
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(items.size() * 72.0, 500.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var item_box := VBoxContainer.new()
	item_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_box.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	scroll.add_child(item_box)

	for item in items:
		var row := AppMenuRow.new()
		row.setup_item(str(item["id"]), str(item["label"]), str(item["icon"]))
		row.chosen.connect(_on_item_chosen)
		item_box.add_child(row)
		_rows.append(row)

	if not note_text.is_empty():
		var note := Label.new()
		note.text = note_text
		note.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
		note.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(note)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)


func _on_item_chosen(id: String) -> void:
	ShellLog.info("menu: %s chosen" % id)
	# The choice first, the close second: the files screen's handler may open the
	# keyboard (Rename), and its close handler checks for that to decide who gets
	# input back.
	chosen.emit(id)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
