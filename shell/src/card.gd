extends Button

## One entry on the home rail, whatever it came from.
##
## THE REPLACEMENT FOR tile.gd, and deliberately about a third of its size. The
## old card carried its own artwork-candidate search, a Steam-specific art cache
## and a wash colour derived from the picture it had chosen -- roughly 300 of
## its 537 lines existed to feed the full-bleed hero background behind the rail.
## That background is gone (ADR 0012), so the search that fed it is gone too and
## a card is once more the thing its name says: an icon, a title, and a press.
##
## THE SOURCE IS DRAWN, and it is the one thing this card does that tile.gd did
## not. A library that mixes Steam, a standalone Windows game and an emulated
## title has to say which is which, or the first time two entries share a name
## the person cannot tell them apart. It is a small caption rather than a logo
## because the sources are open-ended -- a badge set that has to gain an image
## per source is a badge set that will be wrong the first time one is added.
##
## WHERE THE SOURCE COMES FROM: the id prefix, not a new column. appscan already
## namespaces what it writes (`steam.570`, a flatpak id for an application), so
## the information is in the seam and adding a seventh TSV field to restate it
## would be two sources of truth for one fact. See SOURCES.

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

## Focus moved onto this card. The rail listens so it can scroll, and so the
## bar's `down` neighbour keeps pointing at whatever is selected.
signal selected(entry: Dictionary)

## A press that is not a launch: A on an installed card launches, and this is
## everything else that wants a card's identity without acting on it.
signal details_requested()

## id prefix -> what to call it on screen. Longest match wins, so a future
## `steam.workshop.` can sit alongside `steam.` without reordering anything.
##
## An id that matches nothing is an application rather than a game -- that is
## what a bare flatpak id means here -- and applications say nothing, because
## "Application" under an application's own name is a row of noise.
const SOURCES := {
	"steam.": "Steam",
	"win.": "Windows",
	"managed.": "Windows",
	"epic.": "Epic",
	"gog.": "GOG",
	"rom.": "Emulated",
}

var entry: Dictionary = {}

var _icon_rect: TextureRect = null
var _title_label: Label = null
var _source_label: Label = null


## Set before add_child, like every other constructed control here.
func setup(new_entry: Dictionary) -> void:
	entry = new_entry


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# BY HAND, and it is not a style preference. Godot ignores the
	# _get_minimum_size virtual on Button, so a Button whose children are
	# anchored lays out zero-wide and the whole rail collapses into a point.
	# This repo has paid for that lesson once already.
	custom_minimum_size = Vector2(TvTheme.CARD_SIZE, TvTheme.CARD_SIZE)

	# Paint the accent in the rounded button itself. A full-size ColorRect
	# child covers the rounded corners and hides the pressed background.
	var accent := TvTheme.accent_for_id(str(entry.get("id", "")))
	var surface := TvTheme.card_art_box(accent)
	add_theme_stylebox_override("normal", surface)
	add_theme_stylebox_override("hover", surface)
	add_theme_stylebox_override("pressed", TvTheme.card_art_box(
		accent.lerp(TvTheme.SURFACE_PRESSED, 0.35)))
	add_theme_stylebox_override("focus", TvTheme.card_focus_ring())

	_build_contents()

	focus_entered.connect(_on_focus_entered)
	pressed.connect(_on_pressed)


func _build_contents() -> void:
	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_rect.offset_left = TvTheme.CARD_ICON_INSET
	_icon_rect.offset_top = TvTheme.CARD_ICON_INSET
	_icon_rect.offset_right = -TvTheme.CARD_ICON_INSET
	_icon_rect.offset_bottom = -TvTheme.CARD_ICON_INSET
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)
	_load_icon()

	# The caption block sits UNDER the card rather than inside it, so a long
	# title cannot eat the artwork. Anchored to the bottom edge and allowed to
	# overflow downward; the rail reserves room for it.
	var caption := VBoxContainer.new()
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = 8
	caption.offset_bottom = 88
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_constant_override("separation", 0)
	add_child(caption)

	_title_label = Label.new()
	_title_label.text = str(entry.get("title", ""))
	_title_label.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_title_label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_child(_title_label)

	_source_label = Label.new()
	_source_label.text = source_name()
	_source_label.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL - 6)
	_source_label.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_source_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_source_label.visible = not _source_label.text.is_empty()
	caption.add_child(_source_label)

	# A pending card says what it is waiting for instead of where it came from:
	# "Downloading -- 1240 MB fetched" outranks "Steam" on a card nobody can
	# press yet. installed.gd has already chosen that wording.
	if not is_installed():
		_source_label.text = str(entry.get("subtitle", ""))
		_source_label.visible = not _source_label.text.is_empty()
		modulate.a = 0.55


func _load_icon() -> void:
	for kind in ["cover", "icon"]:
		var path := str(entry.get(kind, ""))
		if path.is_empty():
			continue
		var image := Icons.load_icon_image(path)
		if image != null:
			_icon_rect.texture = ImageTexture.create_from_image(image)
			return


## What to call this entry's source on screen, or empty for an application.
func source_name() -> String:
	var id := str(entry.get("id", ""))
	var best := ""
	var label := ""
	for prefix in SOURCES:
		if id.begins_with(prefix) and prefix.length() > best.length():
			best = prefix
			label = SOURCES[prefix]
	return label


## Only an installed entry can be launched. A pending one is a card somebody
## can see and cannot press -- see appscan, which writes no exec for one.
func is_installed() -> bool:
	return str(entry.get("state", "")) == "installed"


## Start this entry, or say why not. Called by the rail on A and by anything
## else that wants this card's press without simulating an input event.
func activate() -> void:
	if not is_installed():
		ShellLog.info("card %s is not installed yet; nothing to launch"
			% str(entry.get("id", "")))
		return
	Launcher.launch(entry)


## Grow the selected card and shrink the rest. Size rather than scale, so the
## rail's HBox lays the neighbours out around it instead of letting a scaled
## card overlap them.
func set_selected_size(is_selected: bool) -> void:
	var side := TvTheme.CARD_FOCUSED_SIZE if is_selected else TvTheme.CARD_SIZE
	custom_minimum_size = Vector2(side, side)


func _on_focus_entered() -> void:
	selected.emit(entry)


func _on_pressed() -> void:
	activate()


func _gui_input(event: InputEvent) -> void:
	# DOWN on a focused card asks for its details rather than moving focus --
	# there is nothing below the rail to move to. Kept as a signal rather than
	# acted on here so the rail owns the details screen and focus restoration.
	if event.is_action_pressed("ui_down"):
		accept_event()
		details_requested.emit()
