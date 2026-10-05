extends Control

## Phase 0's stand-in for a running application.
##
## It covers the whole screen, says which tile asked for it, and goes away on B.
## That is the entire job: proving that the shell can hand the screen over and
## take it back with focus intact, which is the half of Phase 1's launch plumbing
## that can be tested without a daemon or a Flatpak.
##
## Phase 1 deletes this file. Launcher._run() stops instantiating it and starts
## sending `Launch` to marwand instead; the real application draws over the shell
## and marwand's `AppExited` takes the place of the closed signal.
##
## ui_cancel is deliberately the only way out. Adding ui_accept as a second exit
## would be forgiving, and would also mean M3's acceptance test ("A launches
## placeholder; B returns") could pass with B doing nothing at all -- which is
## exactly the silent failure the input map exists to prevent. If B does not
## return from here, that is a real finding and ShellInput's startup check will
## already have said so in the journal.

signal closed()

## Set by Launcher before the node enters the tree.
var entry: Dictionary = {}

const TvTheme = preload("res://src/tv_theme.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The TV-safe inset applies here too. A "press B" hint clipped by overscan is
	# a person stuck on a screen with no way back.
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	add_child(safe)

	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(centre)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	centre.add_child(column)

	column.add_child(_line(
		str(entry.get("title", "Placeholder")),
		TvTheme.SIZE_WORDMARK,
		TvTheme.TEXT_PRIMARY))
	column.add_child(_line(
		"Launching is a placeholder in Phase 0.",
		TvTheme.SIZE_BODY,
		TvTheme.TEXT_SECONDARY))
	column.add_child(_line(
		"Press B to go back.",
		TvTheme.SIZE_BODY,
		TvTheme.TEXT_SECONDARY))

	ShellLog.info("launch placeholder up for %s" % str(entry.get("id", "<unknown>")))


func _line(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the home rail underneath -- which is hidden, but only until
	# launch_finished -- never sees the same press as a second back-out.
	get_viewport().set_input_as_handled()
	closed.emit()
