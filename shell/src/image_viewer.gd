extends Control

## A picture, fullscreen, with the pad to walk through the folder it is in.
##
## WHY THE SHELL DRAWS THIS ITSELF rather than handing a .jpg to an application.
## A photograph on a stick is the most likely thing anyone opens on this screen,
## and it is the one format where the alternative is absurd: launching a
## multi-gigabyte media centre, waiting for it to map a window under gamescope,
## and quitting it again -- to look at one picture the shell has already decoded
## a thumbnail of. Everything this needs is in the binary already (Image,
## TextureRect, the same loader tile.gd uses), so the cost of a viewer is a
## background, a rect and a focus-free input handler.
##
## LEFT AND RIGHT WALK THE FOLDER, which is the thing that makes a viewer a
## viewer rather than a preview. The list arrives from the pane -- already
## sorted the way the person is looking at it -- so "next picture" means the
## next one down the screen they came from, not the next one alphabetically by
## some rule the viewer invented.
##
## NO ZOOM AND NO PAN, deliberately. Both need a second cursor on a device whose
## only pointer is a stick the pad bridge reserves for desktop applications, and
## a picture letterboxed into a 4K panel is already larger than the thing it is
## a picture of. B closes.
##
## NOTHING HERE IS FOCUSABLE. The screen underneath keeps its focus owner and
## gets it back untouched when this closes -- the same arrangement the launch
## splash uses, and the reason closing a picture lands the cursor back on the
## file rather than at the top of the directory.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

## The pictures in the folder, in the pane's own order, and which one is up.
## Set before add_child.
var paths: Array = []
var index: int = 0

var _picture: TextureRect = null
var _caption: Label = null
var _status: Label = null

## Decoded pictures by path. Small on purpose -- three is enough to make
## left-right-left instant without holding a folder of camera JPEGs in memory
## at full size, which is exactly what this viewer refuses to do (see _show).
const CACHE_MAX := 3
var _cache: Dictionary = {}
var _order: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Opaque, edge to edge, and NOT the shell's background colour: a picture is
	# looked at, and the surround should be the darkest thing the palette allows
	# so nothing competes with it. Still inside RGB 16-235 -- see tv_theme.gd's
	# header for why nothing on this machine is pure black.
	var background := ColorRect.new()
	background.color = Color(0.062745, 0.062745, 0.062745, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# FULL BLEED, past the TV-safe inset, because this is a picture and not
	# text: background may overscan. The caption below is inset like everything
	# else that has to be read.
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# KEEP_ASPECT, not COVERED: a viewer crops nothing. A portrait photograph on
	# a 21:9 panel gets bars, which is the correct answer -- the alternative is
	# showing the middle of somebody's picture and calling it the picture.
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)

	# The caption band sits over the picture's bottom edge, on the same gradient
	# the home screen uses to keep text off artwork -- for the same reason, and
	# it is the same texture.
	var scrim := TextureRect.new()
	scrim.texture = TvTheme.hero_gradient()
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scrim.anchor_top = 0.76
	scrim.offset_top = 0.0
	scrim.offset_bottom = 0.0
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	add_child(safe)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_END
	safe.add_child(column)

	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_caption.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_caption)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_status)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	# The left/right hint is only true when there is somewhere to go. A legend
	# advertising a press that is correctly ignored is the exact shape of
	# "broken input" on a machine with no other feedback.
	if paths.size() > 1:
		hints.add_child(TvTheme.hint("A", "Next"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)

	_show(index)


## Put picture `at` on screen. Out-of-range is clamped rather than wrapped: the
## ends of a folder are hard stops for the same reason the rail's are, and a
## selection that teleports to the other end when you lean on the stick reads
## as a glitch.
func _show(at: int) -> void:
	if paths.is_empty():
		_caption.text = "Nothing to show"
		return
	index = clampi(at, 0, paths.size() - 1)
	var path := str(paths[index])

	_caption.text = path.get_file()
	_status.text = "%d of %d" % [index + 1, paths.size()]

	var texture := _texture_for(path)
	if texture == null:
		# The picture is on screen as a name and a failure rather than as a
		# black rectangle. A file that will not decode is a real thing to find
		# on a stick, and it must not look like the viewer is broken.
		_picture.texture = null
		_status.text = "%s -- this file would not open as a picture" % _status.text
		_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
		ShellLog.warn("image viewer: %s would not decode" % path)
		return

	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_picture.texture = texture
	ShellLog.info("image viewer: showing %s (%d of %d)" % [path, index + 1, paths.size()])


## FULL RESOLUTION HERE, unlike the thumbnails -- this is the picture being
## looked at, and 256 px stretched across a television is what the thumbnail
## cache is for, not what a viewer shows. The three-entry cache is the ceiling
## that keeps that affordable: walking a folder holds the current picture and
## its neighbours, not the folder.
func _texture_for(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]

	var image := Icons.load_icon_image(path)
	if image == null:
		return null

	var texture := ImageTexture.create_from_image(image)
	_cache[path] = texture
	_order.append(path)
	while _order.size() > CACHE_MAX:
		_cache.erase(_order.pop_front())
	return texture


## _input, NOT _unhandled_input, and this is the one place in the shell that
## needs the difference. Nothing in this viewer is focusable -- deliberately,
## so the listing underneath keeps its cursor -- which means the focus owner
## while a picture is up is still a row in that listing. The viewport's GUI
## layer turns ui_left and ui_right into FOCUS NAVIGATION for whatever holds
## focus and consumes them before unhandled input ever runs, so a viewer built
## on _unhandled_input showed its first picture and then ignored every press
## while quietly walking the cursor down the list behind it. _input runs ahead
## of the GUI layer; every branch consumes what it takes, so the listing sees
## nothing.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_show(index + 1)
		return
	if event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_show(index - 1)
		return
	if event.is_action_pressed("ui_cancel"):
		# Consumed so the file manager underneath never sees the same press and
		# walks up a directory behind the closing viewer.
		get_viewport().set_input_as_handled()
		closed.emit()
