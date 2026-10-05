extends Control

## The launching state -- what the TV shows between "A was pressed" and the
## launched application's first frame.
##
## That gap used to be nothing at all: launch_started hides the rail, the
## spawned client takes seconds to map a window, and the machine spent them
## showing the clear colour. On a console that reads as a crash, and on THIS
## machine -- where the desktop Steam client could stay windowless forever --
## it read as a crash that never ended. Consoles solve it with a splash: the
## app's identity, big, immediately, so the press is acknowledged in the same
## second it happens. This is that splash, shell-drawn from what the entry
## already carries (accent, title, icon path) because nothing better exists
## until the application's own pixels arrive to replace it.
##
## ONLY THE REAL-PROCESS BRANCH SHOWS IT. The placeholder branch is its own
## fullscreen scene with its own text; a splash over it would be two screens
## claiming the same moment. Launcher._spawn is the one call site.
##
## TWO STATES, AND THE SECOND IS THE HONEST ONE. "Starting" holds while the
## launch watchdog (see Launcher) still expects a window. If the deadline
## passes with the shell still the focused window and the pid still alive, the
## splash stops promising and says what is actually true: the process runs,
## nothing is on screen, the journal knows more, and B closes it. That state
## exists because the alternative was the shell insisting "open" about an
## application the TV plainly did not show -- the exact bug that pointed the
## desktop Steam client at this stack found.
##
## The failure state is only ever entered on the watchdog's word, and the
## watchdog only speaks where gamescope's root properties exist. On a desk run
## or under the Xvfb harness the answer is "unknown" and this stays in its
## plain state until launch_finished -- a splash that cried failure on every
## headless run would train everyone to ignore it.
##
## Phase 1 keeps the idea and moves the trigger: marwand's launch events show
## and clear this instead of the pid-watch spike. The drawing does not change.

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

## Set by Launcher before the node enters the tree.
var entry: Dictionary = {}

## How often the "Starting" line grows a dot. Slow enough to read as patience
## rather than activity it cannot prove, fast enough that the screen is
## visibly alive. A Timer and four strings; deliberately not a shader on a
## machine that renders on llvmpipe.
const ELLIPSIS_SECONDS := 0.4

## The icon's box. The rail's focused card size, so the identity mark on this
## screen is exactly as large as the card the person just pressed -- the
## splash reads as that card taking over the TV, not as a new place.
const ICON_SIZE := TvTheme.CARD_FOCUSED_SIZE

var _status: Label = null
var _column: VBoxContainer = null
var _dots: Timer = null
var _dot_count := 0
var _failed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The entry's accent as a full-bleed wash, dimmed exactly the way the home
	# rail dims its hero -- same blend, same constant -- so launching reads as
	# a continuation of the selection rather than a scene change to somewhere
	# new. Background furniture, so it may overscan; the text below may not.
	var wash := ColorRect.new()
	wash.color = _washed(_accent())
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

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

	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	centre.add_child(_column)

	_build_icon()

	var title := Label.new()
	title.text = str(entry.get("title", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A minimum width wide enough for the longest form, so the label does not
	# re-centre itself a few pixels every time a dot appears -- text jitter on
	# a splash reads as instability, the one thing this screen exists to deny.
	_status.custom_minimum_size = Vector2(360, 0)
	_column.add_child(_status)
	_refresh_dots()

	_dots = Timer.new()
	_dots.wait_time = ELLIPSIS_SECONDS
	_dots.autostart = true
	_dots.timeout.connect(_on_dots_tick)
	add_child(_dots)

	ShellLog.info("launch splash up for %s" % str(entry.get("id", "<unknown>")))


## The card's own icon, at focused-card size. Same loader as the card (see
## tile.gd's load_icon_image for why it is static) and the same silent
## fallback: an entry with no icon path, or a file gone since the scan, simply
## shows no icon -- the wash and the title still say what is starting.
func _build_icon() -> void:
	var path := str(entry.get("icon", ""))
	if path.is_empty():
		return

	var image := Icons.load_icon_image(path)
	if image == null:
		ShellLog.warn("could not load icon %s for the launch splash" % path)
		return

	var icon := TextureRect.new()
	icon.texture = ImageTexture.create_from_image(image)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(icon)


func _accent() -> Color:
	var stated := str(entry.get("accent", ""))
	if not stated.is_empty():
		return TvTheme.accent(stated)
	return TvTheme.accent_for_id(str(entry.get("id", "")))


## The rail's hero blend, verbatim: accent pulled toward the background by
## HERO_DIM. Copied arithmetic rather than a shared helper because it is three
## lines and shell_root's copy is inside a tween -- the CONSTANT is what keeps
## the two screens the same colour, and that is already shared.
func _washed(accent: Color) -> Color:
	return Color(
		accent.r * TvTheme.HERO_DIM + TvTheme.BACKGROUND.r * (1.0 - TvTheme.HERO_DIM),
		accent.g * TvTheme.HERO_DIM + TvTheme.BACKGROUND.g * (1.0 - TvTheme.HERO_DIM),
		accent.b * TvTheme.HERO_DIM + TvTheme.BACKGROUND.b * (1.0 - TvTheme.HERO_DIM),
		1.0)


func _on_dots_tick() -> void:
	_dot_count = (_dot_count + 1) % 4
	_refresh_dots()


func _refresh_dots() -> void:
	_status.text = "Starting" + ".".repeat(_dot_count)


## The watchdog's verdict: the process is alive and the shell still has the
## screen past the deadline. Stop promising and say so, with the one hint that
## actually helps on a machine whose only diagnostic surface is the journal,
## and the one button that actually does something.
func show_failure() -> void:
	if _failed:
		return
	_failed = true
	_dots.stop()

	_status.text = "PC1 could not confirm that %s is ready." \
		% str(entry.get("title", "It"))
	_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)

	var journal := Label.new()
	journal.text = "Close the application and try opening it again."
	journal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	journal.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	journal.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	journal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(journal)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hints.add_child(TvTheme.hint("B", "Close"))
	_column.add_child(hints)

	ShellLog.warn("launch splash showing failure for %s" % str(entry.get("id", "<unknown>")))


## THE SPLASH EATS THE STICK, in both states, and it has to be _input to do
## it. The screen this covers is still alive underneath -- the rail or the
## stores grid, focus intact -- and the shell keeps reading the pad while
## another client draws (stores_screen's deafness note). Focus navigation is
## driven from the GUI pass, so a ui_left that reaches it walks the hidden
## grid, and a ui_accept there presses a card nobody can see -- reviewing
## found A starting a background install from under a "Starting" splash.
## player_one.gd's rule applies: _input dispatches before the GUI pass, and
## set_input_as_handled() from here is what keeps the event from reaching it.
## The home button survives because its action is not in the consumed list --
## deliberately, not by omission: the app menu over a hung launch is how a
## person discovers Close exists before the deadline says so.
##
## B closes the windowless application -- in the FAILURE state only. While
## the splash is still promising, B doing anything would make an impatient
## press kill a launch that was one second from its first frame; consuming it
## silently is the correct reading of "the machine heard you, and no". The
## close goes through the seam's own close path, so the rail comes back the
## same way it does for every other exit.
##
## AND IT STANDS DOWN WHILE THE APP MENU IS UP, which is the other half of that
## same promise. Letting home through was pointless on its own: the menu opened,
## and then the splash ate the A that would have chosen anything on it, so a
## person watching a launch that never drew got a menu with a dead button --
## exactly the state the paragraph above claims to prevent. The overlay is a
## SHELL surface with its own focus, so nothing needs eating while it is there;
## shell_root pauses this the same way and in the same two places it pauses the
## pad bridge. Verified under Xvfb, where the watchdog never answers and the
## splash is therefore up for the whole run.
const CONSUMED_ACTIONS := [
	"ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "ui_cancel",
]

var _paused := false


## Set by Launcher on shell_root's behalf while the app menu is over this
## splash. See the note above the action list.
func set_paused(value: bool) -> void:
	_paused = value


func _input(event: InputEvent) -> void:
	if _paused:
		return
	var consumed := false
	for action in CONSUMED_ACTIONS:
		if event.is_action(action):
			consumed = true
			break
	if not consumed:
		return
	get_viewport().set_input_as_handled()

	if _failed and event.is_action_pressed("ui_cancel"):
		ShellLog.info("B on the failed launch splash; closing the app")
		Launcher.close_current()
