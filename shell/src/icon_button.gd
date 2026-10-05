extends Button

## A focusable icon in the top bar -- the store and the gear.
##
## A Button for tile.gd's reason: FOCUS_ALL and ui_accept-to-pressed come free,
## and anything else would need both hand-built. The look reuses the card's
## boxes and ring so the bar's icons, the rail's cards and the settings rows
## read as one product; like a settings row (and unlike a card) the ring can be
## the plain "focus" stylebox because there is no full-bleed art to bury it.
##
## Emits `activated` rather than opening anything itself: which surface an icon
## opens is shell_root's wiring, the same way a tile does not know what
## Launcher does with its entry.

const TvTheme = preload("res://src/tv_theme.gd")
const Glyphs = preload("res://src/glyphs.gd")

signal activated()

var _kind: String = ""
var _label: String = ""

var _idle_box: StyleBoxFlat
var _focus_box: StyleBoxFlat


func setup(kind: String, label_text: String) -> void:
	_kind = kind
	_label = label_text


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(TvTheme.TOPBAR_ICON_SIZE, TvTheme.TOPBAR_ICON_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text = ""

	# CIRCULAR, at the owner's request, and it reuses the overlay's circle
	# styles rather than growing a second set: those already round a box to a
	# circle by radius, and the top-bar icons are the same size class, so one
	# family of round controls now covers both the bar and the app overlay.
	_idle_box = TvTheme.topbar_circle_box(false)
	_focus_box = TvTheme.topbar_circle_box(true)

	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	add_theme_stylebox_override("pressed", TvTheme.topbar_circle_box(true))
	add_theme_stylebox_override("disabled", _idle_box)
	add_theme_stylebox_override("focus", TvTheme.topbar_circle_ring())

	var glyph := Glyphs.new()
	glyph.kind = _kind
	glyph.color = TvTheme.TEXT_PRIMARY
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = TvTheme.TOPBAR_ICON_PAD
	glyph.offset_top = TvTheme.TOPBAR_ICON_PAD
	glyph.offset_right = -TvTheme.TOPBAR_ICON_PAD
	glyph.offset_bottom = -TvTheme.TOPBAR_ICON_PAD
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glyph)

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)


func _on_focus_entered() -> void:
	add_theme_stylebox_override("normal", _focus_box)
	add_theme_stylebox_override("hover", _focus_box)


func _on_focus_exited() -> void:
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)


func _on_pressed() -> void:
	ShellLog.info("top bar \"%s\" pressed" % _label)
	activated.emit()
