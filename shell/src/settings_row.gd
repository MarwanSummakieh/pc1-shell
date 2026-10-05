extends Button

## One row on the settings screen: a name on the left, a value on the right.
##
## Built as a Button for the same reason a card is (tile.gd's header): Button
## already defaults to FOCUS_ALL and turns `ui_accept` into a `pressed` signal,
## and a row built on Panel would default to FOCUS_NONE and be unreachable from
## a pad. That a Phase 0 row has nothing to do when pressed does not change what
## it has to be to sit in a focus chain.
##
## Pressing A logs rather than doing nothing silently. A press that vanishes is
## indistinguishable from broken input on this machine, and the journal line
## also documents, at the moment someone reaches for it, that read-only is the
## designed state rather than a bug.
##
## The look reuses the card's boxes and ring -- see the settings section of
## tv_theme.gd for why rows carry two focus channels where cards carry three.

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

var _name_text: String = ""
var _value_text: String = ""
var _icon_name: String = ""
var _value: Label = null
## Held for the same reason _value is, one case later. Until the storefront's
## game page existed, no row's NAME ever changed once it was built -- a row was
## "Controller" or "Wi-Fi" forever and only the right-hand value moved. That
## page's primary row is a verb (Play, Install, Downloading) chosen from what
## the machine has, and it has to be able to change under a thumb resting on it.
var _name: Label = null

var _idle_box: StyleBoxFlat
var _focus_box: StyleBoxFlat


## The icon is optional and empty means none: the diagnostic rows have no
## natural mark and forcing one would be decoration for its own sake.
func setup(name_text: String, value_text: String, icon_name: String = "") -> void:
	_name_text = name_text
	_value_text = value_text
	_icon_name = icon_name


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, TvTheme.SETTINGS_ROW_HEIGHT)

	# Rows span the safe width, unlike cards: the settings list is a fixed
	# column, not a strip that slides, so there is no resting position to keep
	# constant and no reason to leave ragged right edges.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Button draws its own text centred, which is not the layout wanted here;
	# the name and value are children instead.
	text = ""

	_idle_box = TvTheme.card_idle_box()
	_focus_box = TvTheme.card_focus_box()

	# Hover matches idle for the rail's reason: there is no pointer on this
	# machine, and a mouse that wandered in should not light a row up.
	#
	# Pressed is DISTINCT from focus, unlike on a card, and the difference is
	# the header's argument made concrete: a press can only land on the focused
	# row, so a pressed box equal to the focus box would change zero pixels at
	# exactly the moment the header promises acknowledgement. A card gets away
	# with that overlap because its press opens a screen; a read-only row has no
	# downstream change, so the box itself is the feedback.
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	add_theme_stylebox_override("pressed", TvTheme.row_pressed_box())
	add_theme_stylebox_override("disabled", _idle_box)
	add_theme_stylebox_override("focus", TvTheme.card_focus_ring())

	_build_contents()

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)


func _build_contents() -> void:
	var padding := MarginContainer.new()
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", TvTheme.SETTINGS_ROW_PAD)
	padding.add_theme_constant_override("margin_right", TvTheme.SETTINGS_ROW_PAD)
	add_child(padding)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", TvTheme.HINT_GLYPH_GAP)
	padding.add_child(row)

	if not _icon_name.is_empty():
		var icon := Icons.label(_icon_name, TvTheme.SIZE_BODY + 6, TvTheme.TEXT_PRIMARY)
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(icon)

	var name_label := Label.new()
	name_label.text = _name_text
	name_label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	name_label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	# THE VALUE IS THE EXPANDING CHILD, NOT A SPACER, and the reason is a Godot
	# sizing rule worth naming: a Label with overrun trimming reports a minimum
	# width of 1 px, and an HBoxContainer gives a non-expanding child exactly its
	# minimum. A spacer taking the slack therefore lays every value out one pixel
	# wide -- five populated rows rendering as five blank ones, on the screen
	# whose whole job is showing the values. Expanding the label itself hands it
	# the slack, right alignment keeps the text against the row's right edge, and
	# the ellipsis engages only when a long adapter string actually runs out of
	# room rather than always.
	_value = Label.new()
	_value.text = _value_text
	_value.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_value.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The value gives way, not the name: a long adapter string should truncate
	# rather than shove the row's name off the left edge of the safe area.
	_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_value)
	_name = name_label


## Live rows (the controller) update in place rather than being rebuilt, so
## focus on the row survives the value changing under it.
func set_value(value_text: String) -> void:
	_value_text = value_text
	if _value != null:
		_value.text = value_text


## Change what the row is CALLED, in place.
##
## `set_name_text`, not `set_name`: this extends a Node, Node already has a
## `name` property with a `set_name` setter behind it, and shadowing that would
## rename the node in the scene tree instead of relabelling the row -- which
## would break every focus_neighbor path pointing at it, since those are
## NodePaths resolved by name.
##
## Safe before _ready, like setup(): the text is stored either way and
## _build_contents reads it when it runs.
func set_name_text(name_text: String) -> void:
	_name_text = name_text
	if _name != null:
		_name.text = name_text


func _on_focus_entered() -> void:
	add_theme_stylebox_override("normal", _focus_box)
	add_theme_stylebox_override("hover", _focus_box)


func _on_focus_exited() -> void:
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)


func _on_pressed() -> void:
	ShellLog.info("settings row \"%s\" is read-only in Phase 0" % _name_text)
