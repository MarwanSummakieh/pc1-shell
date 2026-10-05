extends Button

## The bar's right-hand corner -- the wifi glyph and the clock -- made
## focusable: press A on the corner that shows the system's state and the Info
## page opens, which is everything else the machine can say about itself.
##
## WHAT IT USED TO OPEN, AND WHY THAT WENT. A "quick settings" panel dropped
## from here: network, display, one row per background process, and off /
## restart / sleep. Every one of those was a copy. The network row restated the
## Info page's, the display row restated the settings screen's, the process rows
## restated the menu behind the bell, and the three power verbs restated the
## power screen -- four surfaces' worth of duplicate, on the panel a person was
## most likely to reach first. The menu rewrite of 2026-08-12 deleted it and
## pointed this corner at the one page nothing else owns.
##
## INFO IS THE RIGHT DESTINATION rather than an arbitrary one left over from the
## deletion: this control's whole face is system state -- is there a network, and
## what time is it -- so A on it asking "what else does the machine know" is the
## same question at more length. It is also the reading that keeps the corner a
## control at all; the alternative was demoting it back to furniture.
##
## THE INDICATORS MOVED IN HERE RATHER THAN GAINING A SIBLING BUTTON. The wifi
## fan and the clock used to be loose Labels at the bar's end, explicitly "not
## controls"; a separate icon next to them would have been a second thing in the
## same corner answering the same question. GNOME's shape is the defensible one:
## the status cluster IS the button, so the thing you look at for the system's
## state is the thing you press.
##
## A PILL, and its twin is at the other end of the bar: the processes pill
## (process_pill.gd) wears the same box for the same reason, so the bar reads as
## a state pill at each edge with the round icon cluster between them.
##
## A Button for icon_button.gd's reason: FOCUS_ALL and ui_accept-to-pressed
## come free. Last in the bar's focus chain, because it is rightmost.
##
## The wifi rules are the ones shell_root enforced when it owned the glyph,
## carried whole: visible only once the system has made a claim, because a
## struck fan on a machine that merely has not answered yet is the indicator
## lying in the direction that causes cable-wiggling.

const TvTheme = preload("res://src/tv_theme.gd")
const Glyphs = preload("res://src/glyphs.gd")

signal activated()

var _wifi: Glyphs = null
var _clock: Label = null
## The padded content, held because _get_minimum_size answers from it: an
## anchored child contributes NOTHING to a Button's own minimum, so without
## this the corner is a zero-width control whose wifi fan and clock spill past
## the bar's right edge -- which is exactly how it first rendered, clock
## guillotined by the window edge, caught on the Xvfb screenshot.
var _pad: MarginContainer = null

var _idle_box: StyleBoxFlat
var _focus_box: StyleBoxFlat


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	# The bar's own boxes. On a wide button the circle radius rounds the box
	# into a pill, which is how the old service tray already wore them -- one
	# family of round controls, whatever their width.
	_idle_box = TvTheme.topbar_circle_box(false)
	_focus_box = TvTheme.topbar_circle_box(true)
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	add_theme_stylebox_override("pressed", TvTheme.topbar_circle_box(true))
	add_theme_stylebox_override("disabled", _idle_box)
	add_theme_stylebox_override("focus", TvTheme.topbar_circle_ring())
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)

	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The width is refreshed from the content once it exists -- see
	# _refresh_min_size, called at the end of this function and on every
	# change to what the corner shows.
	custom_minimum_size = Vector2(0, TvTheme.SIZE_TOPBAR + 18)
	text = ""

	_pad = MarginContainer.new()
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.add_theme_constant_override("margin_left", 18)
	_pad.add_theme_constant_override("margin_right", 18)
	add_child(_pad)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_pad.add_child(row)

	_wifi = Glyphs.new()
	_wifi.custom_minimum_size = Vector2(TvTheme.SIZE_TOPBAR + 10, TvTheme.SIZE_TOPBAR + 10)
	_wifi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wifi.visible = false
	_wifi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_wifi)

	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	_clock.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_clock)

	pressed.connect(_on_pressed)
	_refresh_min_size()


## See _pad: the content decides how wide the pill is, because Button will not
## ask an anchored child. Written into custom_minimum_size rather than the
## _get_minimum_size virtual, because Button overrides get_minimum_size in
## C++ and never consults the script hook -- tried, and the corner laid out
## zero-wide with the clock spilling past the screen edge, exactly as if the
## override were not there. The old service tray's explicit-width approach is
## the one that demonstrably works in this engine.
func _refresh_min_size() -> void:
	if _pad == null:
		return
	var content := _pad.get_combined_minimum_size()
	custom_minimum_size = Vector2(content.x, maxf(content.y, TvTheme.SIZE_TOPBAR + 18))


## The network's answer as a glyph. "unknown" draws nothing -- see the header.
func set_network(state: String) -> void:
	if _wifi == null:
		return
	match state:
		"online":
			_wifi.visible = true
			_wifi.kind = "wifi"
			_wifi.color = TvTheme.TEXT_SECONDARY
		"offline":
			_wifi.visible = true
			_wifi.kind = "wifi-off"
			_wifi.color = TvTheme.TEXT_ALERT
		_:
			_wifi.visible = false
	# The glyph appearing or leaving changes how wide the pill needs to be.
	_refresh_min_size()


func set_clock(text_value: String) -> void:
	if _clock != null:
		_clock.text = text_value
	_refresh_min_size()


func _on_focus_entered() -> void:
	add_theme_stylebox_override("normal", _focus_box)
	add_theme_stylebox_override("hover", _focus_box)


func _on_focus_exited() -> void:
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)


func _on_pressed() -> void:
	ShellLog.info("status corner pressed")
	activated.emit()
