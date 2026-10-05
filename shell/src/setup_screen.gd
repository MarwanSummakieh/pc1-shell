extends Control

## First-run setup: who you are, and whether Steam should know you.
##
## WHY THIS IS FIRST BOOT AND NOT AN INSTALLER STEP. The owner asked for a
## sign-in "while installing". This appliance has no installer -- the raw-image
## route in ADR 0003 has none by design, which is why the stick offers no
## install option -- so the only moment that exists is the first time the shell
## comes up on a machine that has never been set up. Same intent, a moment that
## actually exists.
##
## NOTHING HERE IS LOAD-BEARING, and that is deliberate. Skipping every row must
## leave a completely working machine: the name is decoration, and Steam is an
## application on the rail whether or not anyone signed into it here. A setup
## screen that can strand somebody is worse than no setup screen, because the
## person it strands is looking at a television with no console and no keyboard.
##
## IT RUNS ONCE AND THEN NEVER NAGS. Finishing OR skipping both mark it done --
## a prompt that reappears until you obey it is a prompt people learn to fear.
## Settings carries the same two actions afterwards, which is the "sign in again
## after the OS is installed" half of the request.
##
## THE NAME IS NOT A USER ACCOUNT. The system identity stays `player`: greetd's
## autologin, sysusers' uid 1000, the tmpfiles tree, the session's runuser and
## some fifty other references are all built on it, and re-plumbing that at
## first boot is a refactor whose failure mode is a machine that cannot log in.
## This writes a display name and nothing else.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")
const Keyboard = preload("res://src/keyboard.gd")

var _rows: Array = []
var _name_row: ActionRow = null
var _keyboard: Keyboard = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	add_child(safe)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)

	var heading := Label.new()
	heading.text = "Welcome"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	var blurb := Label.new()
	blurb.text = "Set this up now, or skip -- everything here can be changed later in Settings."
	blurb.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(blurb)

	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	column.add_child(list)

	_name_row = _add(list, "Your name", Setup.display_name_or_default(),
		"keyboard", _on_name_pressed)
	_add(list, "Sign in to Steam", "Opens Steam -- press A", "steam", _on_steam_pressed)
	_add(list, "Done", "", "check", _on_done_pressed)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Skip"))
	column.add_child(hints)

	TvTheme.wire_column(_rows)
	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("setup screen up with %d rows" % _rows.size())


func _add(list: Control, name_text: String, value_text: String,
		icon_name: String, handler: Callable) -> ActionRow:
	var row := ActionRow.new()
	row.setup(name_text, value_text, icon_name)
	row.activated.connect(handler)
	list.add_child(row)
	_rows.append(row)
	return row


## The on-screen keyboard, unmasked -- this is a name, not a password, and
## masking it would make somebody check their own typing against dots.
func _on_name_pressed() -> void:
	if _keyboard != null:
		return
	_keyboard = Keyboard.new()
	_keyboard.title_text = "Your name"
	_keyboard.masked = false
	_keyboard.initial_text = Setup.display_name()
	_keyboard.submitted.connect(_on_name_submitted)
	_keyboard.cancelled.connect(_on_name_cancelled)
	add_child(_keyboard)


func _on_name_submitted(text: String) -> void:
	Setup.set_display_name(text)
	if _name_row != null:
		_name_row.set_value(Setup.display_name_or_default())
	_close_keyboard()


func _on_name_cancelled() -> void:
	_close_keyboard()


func _close_keyboard() -> void:
	if _keyboard == null:
		return
	var board := _keyboard
	_keyboard = null
	if is_instance_valid(board):
		remove_child(board)
		board.queue_free()
	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()


## Steam signs itself in -- this only opens it.
##
## THE QR FLOW IS NOT COMING BACK. This project wrote one and Valve's HTTPS
## token exchange refused the tokens it minted (eresult 63, measured
## 2026-08-12), which is what ADR 0010 died of. Steam's own UI is the only
## sign-in that works, so the honest thing is to open it and get out of the way.
##
## Handed to the Launcher rather than run here, for the reason every other
## launch in this shell is: the launcher owns the busy state, the splash and
## the return journey, and a second way to put something on the screen is the
## class of parallel path this shell has been bitten by before.
func _on_steam_pressed() -> void:
	ShellLog.info("setup: opening Steam to sign in")
	Setup.mark_done()
	closed.emit()
	Launcher.launch(Setup.STEAM_ENTRY)


func _on_done_pressed() -> void:
	ShellLog.info("setup: finished")
	Setup.mark_done()
	closed.emit()


## B SKIPS, and skipping marks setup done exactly as finishing does. A first-run
## prompt that comes back until it is obeyed teaches people to dread the boot.
func _unhandled_input(event: InputEvent) -> void:
	if _keyboard != null:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	ShellLog.info("setup: skipped")
	Setup.mark_done()
	closed.emit()
