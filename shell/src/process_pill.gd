extends Button

## The processes pill: the bar's left-hand corner, and the door to what is
## running in the background.
##
## IT REPLACED TWO THINGS, AND THAT IS THE POINT. The bar's left used to carry
## the drawn "M.OS" wordmark and, beside it, a notification bell. The wordmark
## was furniture that said the same thing on every screen forever, and the bell
## named a surface the shell has never had -- there are no notifications, and
## there was no plan for any that this menu was waiting on. What the bell
## actually opened was the list of background processes. So the mark is gone,
## the bell is gone, and the one control left is named for what is behind it
## (the owner's request, 2026-08-12).
##
## A PILL, NOT A CIRCLE, and it is the status corner's shape mirrored: the bar
## now ends in a pill at each edge -- processes on the left, network and clock
## on the right -- with the round icon cluster between them. Two pills reading
## as a matched pair is what makes the bar's two ends legible as "the machine's
## state" rather than as two more icons.
##
## A Button for icon_button.gd's reason: FOCUS_ALL and ui_accept-to-pressed come
## free. It is leftmost in the bar's focus chain, so left off the store lands
## on it.
##
## THE PILL DOES NOT DIM. A control drawn dim reads as disabled -- the exact lie
## a focusable thing must not tell -- so state lives in the dot, exactly as the
## bell carried it:
##
##   no dot        every process is running; nothing needs attention
##   grey dot      this shell asked for a change and the supervisor has not
##                 confirmed it yet -- the press's acknowledgement
##   amber dot     something is stopped, crashed or unreported; worth opening
##
## Pending outranks stopped, because acknowledging the person's own press
## matters more than restating the state they just acted on.

const TvTheme = preload("res://src/tv_theme.gd")
const Glyphs = preload("res://src/glyphs.gd")

signal activated()

## How much wider than tall the pill is. Enough that the rounded box reads as a
## pill rather than as a slightly squashed circle, and no wider -- the glyph is
## still the only thing in it, and a pill with acres of empty field beside one
## mark reads as a control that failed to load its label.
const PILL_ASPECT := 1.55

## The badge dot's geometry, in design px. Inset from the pill's top-right so
## the dot sits on the face rather than clipped by the rounded edge; the radius
## is the smallest that still reads as a deliberate mark at three metres.
const BADGE_RADIUS := 7.0
const BADGE_INSET := 16.0

## Transparent alpha means no badge; _draw tests it rather than a second flag,
## so the colour and the decision to draw cannot disagree.
var _badge := Color(0, 0, 0, 0)

var _idle_box: StyleBoxFlat
var _focus_box: StyleBoxFlat


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(
		TvTheme.TOPBAR_ICON_SIZE * PILL_ASPECT, TvTheme.TOPBAR_ICON_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text = ""

	# The bar's own boxes. Their corner radius is half TOPBAR_ICON_SIZE, so on a
	# box this wide it rounds the ends and leaves the middle straight -- which is
	# what makes one stylebox family serve both the round icons and both pills.
	_idle_box = TvTheme.topbar_circle_box(false)
	_focus_box = TvTheme.topbar_circle_box(true)
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	add_theme_stylebox_override("pressed", TvTheme.topbar_circle_box(true))
	add_theme_stylebox_override("disabled", _idle_box)
	add_theme_stylebox_override("focus", TvTheme.topbar_circle_ring())
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)

	# The stack glyph -- layers, i.e. things running underneath what is on
	# screen. Sized and placed against the pill's HEIGHT rather than its full
	# rect, because Glyphs fills the shorter axis of the box it is given: an
	# anchored full-rect glyph on a box 1.55 as wide as it is tall would centre
	# correctly and still be sized by the height, so the explicit square is the
	# honest way to say what is already happening.
	var glyph := Glyphs.new()
	glyph.kind = "stack"
	glyph.color = TvTheme.TEXT_PRIMARY
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = (custom_minimum_size.x - TvTheme.TOPBAR_ICON_SIZE) * 0.5 \
		+ TvTheme.TOPBAR_ICON_PAD
	glyph.offset_right = -glyph.offset_left
	glyph.offset_top = TvTheme.TOPBAR_ICON_PAD
	glyph.offset_bottom = -TvTheme.TOPBAR_ICON_PAD
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glyph)

	pressed.connect(_on_pressed)
	Services.services_changed.connect(refresh)
	Launcher.minimized.connect(func(_entry: Dictionary): refresh())
	Launcher.launch_finished.connect(func(_entry: Dictionary): refresh())
	# Visibility depends on what is installed -- see refresh -- so the pill has
	# to re-answer when the installed list does.
	Installed.apps_changed.connect(_on_installed_changed)
	refresh()


func _on_installed_changed(_apps: Array) -> void:
	refresh()


## Re-answer visibility and the badge from the seam. Cheap on every change: it
## is one loop over a short list, and the redraw is a dot.
func refresh() -> void:
	var services: Array = Services.visible_services()
	# NOTHING INSTALLED IS NOT AN EMPTY PILL. A pill over zero processes would
	# be a door onto "nothing runs here"; hiding it also takes it out of the
	# neighbour chain, which shell_root's pill-membership wiring handles.
	visible = Launcher.is_minimized() or not services.is_empty()
	if not visible:
		return

	var any_pending := false
	var any_down := false
	for service in services:
		if not Services.pending_of(str(service.get("id", ""))).is_empty():
			any_pending = true
		elif str(service.get("state", "")) != "running":
			any_down = true

	if any_pending:
		_badge = TvTheme.TEXT_SECONDARY
	elif any_down:
		_badge = TvTheme.TEXT_ALERT
	else:
		_badge = Color(0, 0, 0, 0)
	queue_redraw()


## The badge dot, over the pill's top-right shoulder. Drawn here rather than as
## a child node because it is one circle whose only property is a colour -- a
## node would be scene-tree bookkeeping for a single draw call.
func _draw() -> void:
	if _badge.a <= 0.0:
		return
	draw_circle(Vector2(size.x - BADGE_INSET, BADGE_INSET), BADGE_RADIUS, _badge)


## The lit-while-focused swap, matching icon_button exactly: the ring alone is
## not enough separation on a bar this dark, so the plate lights too.
func _on_focus_entered() -> void:
	add_theme_stylebox_override("normal", _focus_box)
	add_theme_stylebox_override("hover", _focus_box)


func _on_focus_exited() -> void:
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)


func _on_pressed() -> void:
	ShellLog.info("processes pill pressed")
	activated.emit()
