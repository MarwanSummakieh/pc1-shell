extends RefCounted

## The frame the appliance shows when the shell has crashed too many times to
## keep restarting it.
##
## WHAT IT REPLACES. marwanos-session's supervision loop gives the client five
## crashes inside sixty seconds and then stops respawning it. Until now that left
## the compositor up with nothing drawn: a black TV, indefinitely, on a machine
## that by design has no console, no getty and no visible text of any kind. Every
## other failure in this project announces itself in the journal; this was the one
## that announced itself as furniture.
##
## D6 SAYS NO TEXT, AND THIS IS TEXT. That is not a contradiction being smuggled
## past: D6 forbids a *reachable terminal* and console spew on the happy path. A
## deliberate, designed error frame drawn by the shell is the opposite of a
## console leaking -- it is the appliance saying one sentence, on purpose, in its
## own typeface, at a moment where the alternative is saying nothing at all.
##
## IT IS DRAWN BY THE SAME BINARY THAT JUST CRASHED, and that limitation is real
## rather than hidden. The bet is that crashes live in shell logic -- a scene, a
## catalogue entry, a launch handler -- and not in engine startup, so a frame that
## touches none of that survives what killed the home screen. Nothing here builds
## the rail, reads the catalogue, instantiates a card or talks to the launcher; it
## is labels on a ColorRect. What it cannot survive is a binary that fails before
## GDScript runs at all -- a corrupt export, a missing library, a driver that will
## not initialise. In that case the session falls back to holding, exactly as it
## did before, and the journal still has the reason.
##
## If that residual case ever bites, the stronger version is a frame drawn by
## something with no Godot in it. That is more machinery than this milestone
## justifies for a failure nobody has hit yet.

const TvTheme = preload("res://src/tv_theme.gd")

## Read by shell_root.gd. Set by marwanos-session, and by nothing else -- the
## same shape as MARWANOS_SHELL_WINDOWED in kiosk.gd: a variable that exists only
## because something deliberately set it, not a state a machine can drift into.
const ERROR_ENV := "MARWANOS_SHELL_ERROR_SCREEN"


static func requested() -> bool:
	return not OS.get_environment(ERROR_ENV).is_empty()


## Builds the whole frame. Returns a Control the caller adds to the tree.
##
## Deliberately a static function returning plain Controls rather than a scene or
## a class with state: the fewer moving parts between "the shell is broken" and
## "something is on screen", the better this does its one job.
static func build() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	# The same TV-safe inset the home screen uses. An error frame that overscans
	# off the edge of the TV is the one screen where being unreadable costs the
	# most.
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	root.add_child(safe)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)

	# The wordmark stays, and it is doing work. A screen with the product's name
	# on it reads as the product having a bad day; a bare sentence on black reads
	# as the television being broken, which sends the person to the wrong device.
	column.add_child(_label("MarwanOS", TvTheme.SIZE_WORDMARK, TvTheme.TEXT_SECONDARY))

	column.add_child(_label(
		"Something went wrong",
		TvTheme.SIZE_WORDMARK, TvTheme.TEXT_PRIMARY))

	# The alert colour is the third channel, after size and position. Colour alone
	# is never load-bearing here for the same reason it is not on the focus ring.
	column.add_child(_label(
		"The interface stopped responding and could not be restarted.",
		TvTheme.SIZE_BODY, TvTheme.TEXT_ALERT))

	# The only action available to the person in the room. There is no menu to
	# reach, no terminal to drop to and no button that fixes this -- so the frame
	# says the true thing rather than an encouraging one.
	column.add_child(_label(
		"Hold the power button until the machine switches off, then start it again.",
		TvTheme.SIZE_BODY, TvTheme.TEXT_PRIMARY))

	# For whoever opens it later rather than for the couch. Supplemental size and
	# secondary colour put it below the instruction in the reading order.
	column.add_child(_label(
		"If this keeps happening:  journalctl -b -t marwanos-session",
		TvTheme.SIZE_SUPPLEMENTAL, TvTheme.TEXT_SECONDARY))

	return root


static func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrapping rather than clipping: this text must survive a narrower output than
	# the design surface, and a truncated instruction is worse than a wrapped one.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
