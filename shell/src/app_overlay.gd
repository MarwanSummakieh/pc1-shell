extends Control

## The home-button menu: what you get while an application is running.
##
## THE APPLICATION KEEPS THE WHOLE SCREEN. This draws nothing behind its own
## panel -- the background is transparent, gamescope composites this window on
## top of the running application, and what shows around the menu is the
## application itself, live and at full size. There is no screenshot, no
## thumbnail and no capture.
##
## That is possible because of one X property. gamescope reads
## GAMESCOPE_EXTERNAL_OVERLAY on a window and, when set, composites that window
## over the focused application instead of replacing it -- the same mechanism
## Steam's overlay uses on a Deck. Kiosk.set_overlay() sets and clears it; see
## there for how, and for what happens if it does not take.
##
## WHY A MENU AND NOT THE FRAMED CARD IT REPLACES. The first version of this
## screen drew a frame around the application, shrank the visible area to 72% of
## the height and put two circular buttons in the strip underneath. It worked,
## and it cost the application most of the screen to offer two choices -- so the
## thing you pressed home to look at was the thing that got covered. A menu is
## the same two presses, keeps the application whole behind it, and has somewhere
## obvious to put the third and fourth entries when they arrive.
##
## MENU_ITEMS IS THE EXTENSION SEAM: adding a line there and a case to
## _on_item_chosen is the entire change. The menu still ships with only what it
## can actually do.
##
## Accessible native editors open the keyboard automatically through
## text_input.gd. Type remains the fallback for custom app controls that do not
## expose their fields to AT-SPI: focus the field, press home, choose Type,
## write, Done. This draft is then delivered through the existing XTEST bridge.
##
## WHILE THE KEYBOARD IS UP THIS OVERLAY IS STILL AN OVERLAY. The menu panel
## hides and the keyboard takes its place on the same surface, so
## Kiosk.set_overlay stays on, the scrim hides, the pad bridge stays
## paused, and the application stays visible behind the keys with its cursor
## still sitting in the field being filled. Swapping in a separate shell screen
## would have covered the app -- and the field a person is typing into is the
## one thing they must be able to see.
##
## Minimize keeps the process alive and restores the previous shell surface.
## Its library card and the processes menu resume that same process.
##
## Navigation is the settings list's, verbatim: one axis, hard stops,
## perpendicular pointed at self. B closes the menu and returns to the
## application.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const AppMenuRow = preload("res://src/app_menu_row.gd")
const Keyboard = preload("res://src/keyboard.gd")
const VolumePopup = preload("res://src/volume_popup.gd")

## The menu, in order. Adding an entry here and a branch in _on_item_chosen is
## the whole of adding a menu item -- the panel sizes itself and the focus chain
## is wired from this list.
##
## TYPE IS FIRST BECAUSE CLOSE IS THE DESTRUCTIVE ONE. The cursor opens on the
## first row, so whichever entry leads is the one an impatient home-then-A lands
## on -- and that press should not be the one that kills the application and
## whatever was unsaved in it. Typing is also simply the entry someone reaches
## for more often: closing happens once per session, filling in an address bar
## happens all through it.
const MENU_ITEMS := [
	{"id": "type", "label": "Type", "icon": "keyboard"},
	{"id": "audio", "label": "Audio", "icon": "speaker"},
	{"id": "minimize", "label": "Minimize", "icon": "home"},
	{"id": "close", "label": "Close", "icon": "close"},
]

## How far the scrim dims the application behind the menu. Enough that a white
## storefront cannot wash out the panel's edge, light enough that the
## application is plainly still there -- which is the whole reason this is an
## overlay rather than a screen.
const SCRIM_ALPHA := 0.55

var entry: Dictionary = {}

var _rows: Array = []
## The left-edge panel's container, kept so Type can hide it while retaining
## the overlay surface. Typed as Control rather than
## as the concrete container: this was a CenterContainer until the menu moved to
## the left edge, and nothing here should have to change again if it moves back.
var _menu: Control = null
var _keyboard: Keyboard = null
var _volume_popup: VolumePopup = null
var _typing_pid := -1
var _typing_error: Label = null
var _scrim: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build()
	_wire_focus_neighbours()

	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("app menu up for %s" % str(entry.get("title", "<unknown>")))


func _build() -> void:
	# The dim covers the whole screen, unlike the strip it replaces. With the
	# application no longer framed there is no region the menu is deliberately
	# keeping clear, so a partial dim would just be an edge with no meaning.
	var scrim := ColorRect.new()
	_scrim = scrim
	scrim.color = Color(TvTheme.BACKGROUND.r, TvTheme.BACKGROUND.g, TvTheme.BACKGROUND.b, SCRIM_ALPHA)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var panel := preload("res://src/edge_panel.gd").new()
	add_child(panel)
	_menu = panel

	# No full-rect preset here any more: inside a PanelContainer the child is
	# laid out by the container, and presetting anchors would fight it.
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 32)
	pad.add_theme_constant_override("margin_right", 32)
	pad.add_theme_constant_override("margin_top", 32)
	pad.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	pad.add_child(column)

	# The application's name, not "Menu". Which application this is about is the
	# one thing a person needs before pressing Close, and the menu is opened
	# from inside the application rather than from a list that already said so.
	var title := Label.new()
	title.text = str(entry.get("title", ""))
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var items := VBoxContainer.new()
	items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	column.add_child(items)

	for item in MENU_ITEMS:
		var row := AppMenuRow.new()
		row.setup_item(str(item["id"]), str(item["label"]), str(item["icon"]))
		row.chosen.connect(_on_item_chosen)
		items.add_child(row)
		row._value.hide()
		row._name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row._name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_rows.append(row)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back to app"))
	column.add_child(hints)


## The shared one-axis table (TvTheme.wire_column), which this file's comment
## already described as "the settings list's table, verbatim". Vertical here
## where the circles were horizontal, which is the one navigational consequence
## of the menu having replaced them.
func _wire_focus_neighbours() -> void:
	TvTheme.wire_column(_rows)


func _on_item_chosen(id: String) -> void:
	ShellLog.info("app menu: %s chosen" % id)
	match id:
		"audio":
			_open_audio()
		"type":
			# NO closed.emit() ON THIS BRANCH, and that is the difference between
			# it and every other entry. Closing the overlay would clear
			# GAMESCOPE_EXTERNAL_OVERLAY and unpause the pad bridge -- so the
			# keyboard would come up either instead of the application or with the
			# stick typing arrows into it. The overlay stays exactly as it is and
			# only its contents change.
			_open_keyboard()
		"close":
			Launcher.close_current()
			# The menu goes away immediately; the rail comes back when the launch
			# seam's poll notices the process is gone, which is the same path a
			# normal exit takes. Waiting here would leave the menu on screen over
			# a dying application.
			closed.emit()
		"minimize":
			Launcher.minimize_current()
			closed.emit()
		_:
			# Unreachable while MENU_ITEMS and this match agree, which is exactly
			# why it is logged: the failure it catches is an entry added to the
			# list and not to the switch, and on this machine a press that does
			# nothing silently is indistinguishable from broken input.
			ShellLog.error("app menu item \"%s\" has no action" % id)


# ---------------------------------------------------------------------------
# Typing into the application
# ---------------------------------------------------------------------------

func _open_audio() -> void:
	if _volume_popup != null:
		return
	_volume_popup = VolumePopup.new()
	for row in _rows:
		if row.id == "audio":
			_volume_popup.anchor_control = row
	_volume_popup.closed.connect(_close_audio.call_deferred, CONNECT_ONE_SHOT)
	add_child(_volume_popup)


func _close_audio() -> void:
	if _volume_popup == null:
		return
	var screen := _volume_popup
	_volume_popup = null
	screen.dismiss()
	_menu.show()
	for row in _rows:
		if row.id == "audio":
			row.grab_focus()
			break

## Swaps the menu panel for the keyboard on this same surface. See the header
## for why it is a swap and not a screen.
func _open_keyboard() -> void:
	if _keyboard != null:
		# A second press while it is up is a bounced button, the same rule the
		# card menu and the other surfaces enforce.
		return

	var title := str(entry.get("title", ""))

	_keyboard = Keyboard.new()
	# Named, because the keyboard is drawn over the application rather than
	# instead of it and "Enter password" would be the wrong sentence entirely --
	# this says which window the characters are about to land in.
	_keyboard.title_text = "Type into %s" % title
	if title.is_empty():
		_keyboard.title_text = "Type"
	# NOT MASKED. A passphrase is hidden because the room can see the TV; an
	# address or a search term is the opposite case -- the person cannot see the
	# field they are filling in (it is behind the keys, in another application,
	# possibly scrolled out of view) so this entry line is the only readback
	# they get before the string is committed.
	_keyboard.masked = false
	# The app keeps showing at full brightness around the floating keyboard.
	_keyboard.background_alpha = 0.0
	_keyboard.submitted.connect(_on_typed)
	_keyboard.cancelled.connect(_on_typing_cancelled)
	# Hidden before the keyboard is built, so the focus its _ready grabs is not
	# immediately fought over by a menu row that is still on screen.
	_menu.hide()
	add_child(_keyboard)
	_scrim.hide()


## What was typed goes into the application underneath.
##
## THE STRING IS ONE ARGV ELEMENT AND THERE IS NO SHELL, and on this engine
## exactly one call has that property: OS.create_process, whose argv goes to
## execvp literally. OS.execute does NOT -- with or without an output array,
## 4.7.1's core_bind always hands it to popen, a real /bin/sh with the
## arguments merely wrapped in double quotes and nothing escaped inside them
## (measured against the pinned engine during review: `touch "A_$(id -u)"`
## through OS.execute created A_0 both ways; through create_process it
## created the literal filename). A person typing a `$`, a backtick or `$(`
## into a search box would be writing shell syntax that runs as the session
## user. So: create_process, argv, no shell -- and `--` ends xdotool's own
## options for the same reason pad_keys.gd passes it before a negative
## mousemove: a search term that starts with a dash is a word, not a flag.
##
## THE PRICE IS THE EXIT STATUS. create_process returns the forked pid before
## execvp has had a chance to fail, so on Linux a missing xdotool still comes
## back as a positive pid and the warn below is close to unreachable -- the
## same honesty note pad_keys.gd carries. The real guarantee lives in the
## Containerfile, which asserts xdotool into the image; the warn stays for
## the desk-run case where spawning fails outright.
##
## NO TRAILING RETURN, DELIBERATELY. Submitting belongs to the application:
## half the time the person wants to read back what the entry line shows, fix a
## character, or add to it -- and an Enter sent from here would have committed a
## half-typed address with no way to take it back. Whatever that application
## binds submission to, the person presses it themselves once the overlay is
## gone and the pad is talking to the app again.
func _on_typed(text: String) -> void:
	if _typing_pid > 0:
		return
	var title := str(entry.get("title", "<unknown>"))

	if text.is_empty():
		# Done on an empty line is a person changing their mind at the last key.
		# Spawning xdotool to type nothing would still be a process and still be
		# a journal line claiming something was typed.
		ShellLog.info("nothing typed; returning to %s" % title)
		closed.emit()
		return

	# The LENGTH, not the text, for wifi_screen's reason turned down a notch:
	# this is not a secret, but a search term is nobody's business and the
	# journal is read by whoever is debugging the machine.
	ShellLog.info("typing into %s (%d characters)" % [title, text.length()])

	if not Kiosk.focus_app_keyboard():
		_keyboard.title_text = "App window unavailable. Press B to return."
		if not is_instance_valid(_typing_error):
			_typing_error = Label.new()
			_typing_error.text = "App window unavailable. Press B to return."
			_typing_error.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
			_typing_error.position = Vector2(TvTheme.SAFE_MARGIN_X, TvTheme.SAFE_MARGIN_Y)
			_keyboard.add_child(_typing_error)
		ShellLog.warn("app keyboard focus unavailable; no text injected")
		return
	var pid := OS.create_process("xdotool", ["type", "--clearmodifiers", "--delay", "0", "--", text])
	_typing_pid = pid
	if pid <= 0:
		# Best effort only -- see the header for why this rarely fires on
		# Linux. Naming the binary once and handing the screen back is the
		# whole failure path: a desk run without xdotool must return to the
		# application, not take the shell down.
		ShellLog.warn("could not spawn xdotool; nothing was typed into %s" % title)
	while pid > 0 and OS.is_process_running(pid):
		await get_tree().create_timer(0.05).timeout
	_typing_pid = -1

	# Whether or not the injection took, the person is done with the keyboard and
	# the application should have the screen back. shell_root's _close_overlay is
	# what actually clears the gamescope overlay and unpauses the pad bridge.
	closed.emit()


func _on_typing_cancelled() -> void:
	if _typing_pid > 0:
		OS.kill(_typing_pid)
		_typing_pid = -1
	# B out of the keyboard types nothing at all -- not an empty string, not a
	# stray keystroke. The application is exactly as it was left.
	ShellLog.info("typing cancelled; nothing typed into %s"
		% str(entry.get("title", "<unknown>")))
	closed.emit()


func _exit_tree() -> void:
	if _typing_pid > 0:
		OS.kill(_typing_pid)


func _unhandled_input(event: InputEvent) -> void:
	if _volume_popup != null:
		return
	# THE KEYBOARD OWNS B WHILE IT IS UP. It consumes ui_cancel for its own
	# cancel signal, and this handler must not treat the same press as a second
	# dismissal -- checked explicitly rather than left to dispatch order, which
	# is the assumption that breaks silently when a node is reparented.
	#
	# Home is still a way out from here, and it is the only one this node can
	# offer: shell_root's home handler returns early while an overlay exists, so
	# without this the button that opened all of it would do nothing on the one
	# screen where a person is most likely to press it again. It types nothing --
	# home means "get me out of this", never "commit what I have".
	if _keyboard != null:
		if InputMap.has_action("ui_shell_home") and event.is_action_pressed("ui_shell_home"):
			get_viewport().set_input_as_handled()
			_on_typing_cancelled()
		return

	# B returns to the application. The home button does the same, so the button
	# that opened the menu also dismisses it -- which is what every console does
	# and what a person will try first.
	if event.is_action_pressed("ui_cancel") \
			or (InputMap.has_action("ui_shell_home") and event.is_action_pressed("ui_shell_home")):
		get_viewport().set_input_as_handled()
		ShellLog.info("app menu dismissed; returning to the app")
		closed.emit()
