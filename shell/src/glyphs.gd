extends Control

## An icon that draws itself to whatever size its parent gives it.
##
## THE API SURVIVED ITS OWN IMPLEMENTATION. This started as hand-drawn
## primitives -- arcs for the wifi fan, rectangles for the store bag -- which
## was right for five glyphs and wrong for a full icon language (see icons.gd
## for that argument). The `kind` + `color` interface is unchanged, so the
## rework touched no call site: the same node that drew arcs now draws a
## Phosphor glyph, and consumers cannot tell.
##
## Kept as a _draw control rather than replaced by Icons.label at every call
## site, because several consumers size the glyph by the box they give it (the
## icon buttons, the overlay circles, the wifi indicator) -- a font Label sizes
## the box by the glyph, which is backwards for all of them.

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

## An icon name from icons.gd. Anything unknown draws nothing, which on a TV is
## better than drawing the wrong claim; icons.gd logs the miss.
var kind: String = "":
	set(value):
		kind = value
		queue_redraw()

var color: Color = TvTheme.TEXT_PRIMARY:
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	if kind.is_empty():
		return
	var glyph := Icons.glyph(kind)
	if glyph.is_empty():
		return

	# The glyph fills the shorter axis of the box. Phosphor is drawn on a
	# square em with its shapes reaching close to the edges, so font_size ==
	# box height renders at the size the caller laid out for.
	var font: Font = Icons.font()
	var font_size := int(minf(size.x, size.y))
	if font_size <= 0:
		return

	# Centred by measurement rather than by alignment flags: draw_string's
	# alignment centres horizontally, but vertical centring needs the ascent,
	# and doing both by hand keeps them from disagreeing.
	var glyph_size := font.get_string_size(
		glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var position := Vector2(
		(size.x - glyph_size.x) * 0.5,
		(size.y - glyph_size.y) * 0.5 + font.get_ascent(font_size))

	draw_string(font, position, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
