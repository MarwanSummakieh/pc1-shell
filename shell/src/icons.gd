extends RefCounted

## The shell's icon language: Phosphor, one font, these codepoints.
##
## WHY A FONT AND NOT MORE DRAWN PRIMITIVES. The first five glyphs were arcs
## and rectangles in glyphs.gd, and that was right for five: reviewable text,
## no assets. "Clean icons on everything" is not five -- it is dozens, across
## the explorer, the power menu, the hint row -- and hand-drawing plateaus at
## "geometric" while each new icon is bespoke code. A single MIT-licensed TTF
## trades one vendored binary (pinned by hash -- see assets/phosphor/
## PROVENANCE.md) for a complete, consistent set that scales and recolors like
## text.
##
## CODEPOINTS ARE DECLARED, NOT DISCOVERED. Phosphor ships ligature support, so
## `Label.text = "wifi-high"` with the right font feature would also work --
## and would break silently the day a name changes, with the icon degrading to
## literal text. A wrong codepoint degrades to a visible tofu box, which is a
## failure someone notices. Every value below is from the same commit as the
## vendored TTF; PROVENANCE.md says why they must be re-checked together.

## Runtime load(), and both rejected alternatives failed a real check, which
## is why the reasoning is spelled out rather than assumed:
##
##   preload()            needs the import cache at PARSE time. The build's
##                        --import pass compiles scripts and imports resources
##                        in the same run, so the preload raced the importer
##                        and parse-failed, taking every dependent script down.
##                        The smoke gate caught that build.
##   load_dynamic_font()  needs the RAW ttf bytes at RUNTIME. The export's
##                        all_resources filter packs the imported .fontdata
##                        and deliberately drops the source file (an
##                        include_filter does not override that -- it exists
##                        for files the importer ignores, and .ttf is
##                        claimed). Every icon rendered as tofu, and a
##                        verification round caught it because the binary had
##                        grown by less than the font it supposedly carried.
##
## load() at runtime resolves through the pack's remap to the imported
## .fontdata -- the artefact the build demonstrably packs.
static var _font: Font = null


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/phosphor/Phosphor.ttf") as Font
		# Guard on the RESULT, not a return code: load_dynamic_font returned
		# OK while its file read failed, so the old check reported a healthy
		# shell over a screen full of tofu. Probing a codepoint the table
		# actually uses is the check that cannot be lied to.
		if _font == null or not _font.has_char(0xe470):
			ShellLog.error("icon font missing or unreadable; icons will be blank")
			if _font == null:
				_font = FontFile.new()  # blank glyphs beat a null-call crash
	return _font

const CODEPOINTS := {
	# The shell's existing marks
	"store": 0xe470,        # storefront
	"steam": 0xead4,        # steam-logo
	"speaker": 0xe44a,      # speaker-high
	"gear": 0xe270,
	"user": 0xe4c2,        # user
	# The processes pill at the bar's left corner (process_pill.gd): layers,
	# i.e. things running underneath what is on screen. It replaced the
	# notification bell that used to sit there (0xe0ce, dropped with the menu
	# rewrite of 2026-08-12 -- the shell has no notifications and the surface
	# behind it was always the process list).
	#
	# VERIFIED BY RENDERING, not by reading a table. The post table in this
	# build is format 3 and carries no glyph names, so the cross-check that
	# caught nothing here was the one that could not fail: the codepoint was
	# rasterised out of the vendored TTF and looked at. 0xe2a0 -- hard-drives,
	# already declared below -- was rendered in the same pass as a control, so
	# the sweep's numbering is known to line up with this table.
	"stack": 0xe466,
	"browser": 0xe288,     # globe
	"globe": 0xe288,
	"bookmark": 0xe0e8,
	"search": 0xe30c,
	"youtube": 0xe4fc,
	"github": 0xe576,
	"puzzle": 0xe596,
	"wifi": 0xe4ea,         # wifi-high
	"wifi-off": 0xe4f2,     # wifi-slash
	"close": 0xe4f6,        # x
	"minimize": 0xe32a,     # minus

	# The pad's face buttons, PS5-shaped. Named for the SHAPE, not the action:
	# tv_theme.hint maps logical buttons (A/B/X/Y) onto these, and that mapping
	# is the one place that knows cross means confirm.
	"cross": 0xe4f6,        # x -- same mark, both meanings
	"circle": 0xe18a,
	"square": 0xe45e,
	"triangle": 0xe4b0,

	# The power menu
	"power": 0xe3da,
	"restart": 0xe094,      # arrows-clockwise
	"sleep": 0xe330,        # moon

	# The updater
	"download": 0xe20c,     # download-simple
	"check": 0xe182,

	# The file explorer
	"folder": 0xe24a,
	"folder-open": 0xe256,
	"file": 0xe230,
	"arrow-left": 0xe058,
	"arrow-up": 0xe08e,
	"trash": 0xe4a6,
	"copy": 0xe1ca,
	"cut": 0xeae0,          # scissors
	"rename": 0xe3b4,       # pencil-simple
	"drive": 0xe2a0,        # hard-drives
	"usb": 0xe956,
	"home": 0xe2c2,         # house
	"eject": 0xe212,
	"more": 0xe1fe,         # dots-three
	"caret-right": 0xe13a,
	"caret-left": 0xe138,

	# Elsewhere in settings
	"controller": 0xe26e,   # game-controller
	"display": 0xe32e,      # monitor
	"terminal": 0xeae8,     # terminal-window
	"keyboard": 0xe2d8,
}


## The glyph for a name, as a one-character String, or empty for a name this
## table does not know -- which renders as nothing rather than as a tofu box,
## because a missing name is a shell bug and the failure that points at it is
## the log line, not a broken rectangle on the TV.
static func glyph(name: String) -> String:
	if not CODEPOINTS.has(name):
		ShellLog.warn("no icon named \"%s\"" % name)
		return ""
	return String.chr(int(CODEPOINTS[name]))


## A ready-made icon Label: the font, the glyph, a size and a colour. The
## caller owns layout; this owns nothing but appearance.
static func label(name: String, size: int, color: Color) -> Label:
	var icon := Label.new()
	icon.text = glyph(name)
	icon.add_theme_font_override("font", font())
	icon.add_theme_font_size_override("font_size", size)
	icon.add_theme_color_override("font_color", color)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## How large an SVG is rasterised before anything scales it down. A card icon
## drawn from a 32 px raster and then enlarged is the one artefact a three-metre
## viewing distance makes obvious, so the raster is generous and the scaling is
## always downward.
const ICON_RASTER_PX := 512


## An Image from a file on disk, rasterising SVG at a size worth scaling down
## from. Returns null if the file cannot be read or decoded.
##
## This lived on tile.gd, which is gone with the rest of the old home rail. It
## was never about cards: it is the only place in the shell that knows SVG needs
## measuring before it is rasterised, and every future source of artwork -- a
## store's logo, an emulator's system icon -- wants the same answer. So it moves
## here, to the file that already owns "turn a name into something drawable",
## rather than moving with the presentation that happened to host it.
static func load_icon_image(path: String) -> Image:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if path.get_extension().to_lower() != "svg":
		return Image.load_from_file(path)

	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null

	# Measure first: load_svg_from_buffer takes a SCALE, not a target size, so
	# the natural dimensions have to be known before a useful scale exists.
	var probe := Image.new()
	if probe.load_svg_from_buffer(bytes, 1.0) != OK:
		return null
	var longest := maxi(probe.get_width(), probe.get_height())
	if longest <= 0:
		return null
	if longest >= ICON_RASTER_PX:
		return probe

	var full := Image.new()
	if full.load_svg_from_buffer(bytes, float(ICON_RASTER_PX) / float(longest)) != OK:
		# The measured pass already succeeded, so something small is better than
		# a card with no logo on it.
		return probe
	return full
