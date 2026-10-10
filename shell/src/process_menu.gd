extends Control

## The processes menu: what is running in the background, and a row per process
## that turns it off or on.
##
## Opened from the pill at the bar's left corner (process_pill.gd). A panel over
## a dimmed screen, one axis, B closes -- the card menu's shape, because a person
## who has learned what a menu is on a rail card has learned this one. It hangs
## under the pill it came from, top-left: a panel that appears somewhere
## unrelated to the control that opened it makes a person hunt for the
## connection.
##
## THIS IS THE ONLY HOME FOR PROCESS CONTROL. It used to be one of two -- the
## quick settings panel behind the wifi corner carried its own copy of these
## rows, its own STATE_WORDS table and its own toggle, so the same Steam had two
## doors, two vocabularies and two chances to drift. That panel is deleted (see
## the menu rewrite of 2026-08-12) and this is what is left. ADR 0006's one
## thing, one home, applied to the one surface that had quietly stopped
## obeying it.
##
## ONE ROW PER PROCESS, and the row IS the switch. There is no separate Start and
## Stop pair: a process is running or it is not, so the row says which and A does
## the other thing. Two buttons where one state exists is how a menu grows a
## wrong answer somebody can press.
##
## THE ROW DOES NOT LIE WHILE IT WAITS. Writing the wish is instant; the session's
## supervisor notices within about two seconds and the client itself takes longer
## than that to go away. So a row that has been pressed says "Stopping" until the
## state file agrees, rather than flipping to "Stopped" and being wrong for the
## most visible seconds of the whole interaction. See Services.pending_of.
##
## NOTHING HERE CAN REMOVE ANYTHING. Stopping a process is a runtime state that
## the next boot forgets unless the wish file survives -- it lives on a tmpfs, so
## it does not. Uninstalling Steam is the store card's Options menu and stays
## there.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")

## What a row says on the right, by what the process is doing. The pending words
## are verbs because something is happening; the settled ones are states.
##
## THERE IS ONE COPY OF THIS TABLE NOW. There were two, and the drift they were
## warned about happened: `crashed` was added to this file alone, so the same
## crashed Steam read "Crashed" through the bell and "Not reported yet" -- the
## unknown fallback -- through the quick settings panel. The build asserted the
## two copies agreed because nothing at runtime could. Deleting the second copy
## deleted the class of bug; the Containerfile now asserts there is exactly one.
##
## "Crashed" is deliberately not softened: the supervisor is still retrying on
## a slow backoff, and A on the row retries immediately (crashed is not
## "running", so _on_row's toggle asks for a start). The word on the row is
## what sends a person to the journal instead of to the power button.
##
## THE ACCEPTED GAP: because crashed reads as not-running, A on a crashed row
## always means start, so a crashed process cannot be STOPPED from here. That is
## the cheaper half of the trade -- the supervisor's backoff reaches half an
## hour between attempts, so there is little left to stop -- and the expensive
## half would be a second action on a row that has one button.
const STATE_WORDS := {
	"running": "Running",
	"stopped": "Stopped",
	"crashed": "Crashed",
	"unknown": "Not reported yet",
}

var _rows: Array = []
var _ids: Array = []
var _panel: PanelContainer = null
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The dim, so the bar and the rail behind read as "still there, not
	# available" rather than being replaced. Same treatment as the card menu.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = preload("res://src/edge_panel.gd").new()
	add_child(_panel)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_right", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_top", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_bottom", TvTheme.STORE_ITEM_PAD * 2)
	_panel.add_child(pad)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	pad.add_child(_list)

	# "Running in the background", not "Background services". A service is what
	# the seam calls them because that is what systemd would; what a person sees
	# is Steam, and possibly Discord, quietly running while they are on the home
	# screen. The heading names the situation rather than the mechanism.
	var heading := Label.new()
	heading.text = "Running in the background"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(heading)

	_build_rows()

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Start or stop"))
	hints.add_child(TvTheme.hint("B", "Close"))
	_list.add_child(hints)

	# Live: the whole point of the menu is watching something change, so it has
	# to redraw when the seam says it did rather than when it is reopened.
	Services.services_changed.connect(_refresh_values)

	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("processes menu up with %d rows" % _rows.size())


func _build_rows() -> void:
	if Launcher.is_minimized():
		var entry := Launcher.current_entry()
		for action in ["resume", "close"]:
			var app_row := ActionRow.new()
			app_row.setup(("Resume " if action == "resume" else "Close ") + str(entry.get("title", "app")), "Running")
			app_row.activated.connect(func():
				if action == "resume":
					closed.emit()
					Launcher.resume_current.call_deferred()
				else:
					Launcher.close_current()
					closed.emit())
			_list.add_child(app_row)
			_rows.append(app_row)
			_ids.append("")
	var services: Array = Services.visible_services()
	if services.is_empty():
		# A real state on a machine with nothing installed, and it says so
		# rather than presenting an empty panel that looks like a failure.
		# Reachable only in theory today -- the pill hides itself when this list
		# is empty, so there is no door -- and kept because the pill's
		# visibility and this list are answered from the same seam a moment
		# apart, and the panel must not be the thing that assumes they agreed.
		var empty := Label.new()
		empty.text = "Nothing runs in the background on this machine yet"
		empty.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
		empty.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(empty)
		TvTheme.wire_column(_rows)
		return

	for service in services:
		var id := str(service.get("id", ""))
		var row := ActionRow.new()
		row.setup(str(service.get("label", "")), _value_for(id))
		row.activated.connect(_on_row.bind(id))
		_list.add_child(row)
		_rows.append(row)
		_ids.append(id)

	# The shared one-axis table -- hard stops at both ends, left and right
	# pointed at self so Control's geometric search cannot wander out of the
	# panel and into the bar behind it. See TvTheme.wire_column.
	TvTheme.wire_column(_rows)


## What the row says on the right. The pending words win, because they are the
## most recent true thing about the process -- see the header.
func _value_for(id: String) -> String:
	var pending := Services.pending_of(id)
	if pending == "stop":
		return "Stopping"
	if pending == "start":
		return "Starting"
	return str(STATE_WORDS.get(Services.state_of(id), STATE_WORDS["unknown"]))


func _refresh_values() -> void:
	for index in _rows.size():
		if str(_ids[index]).is_empty():
			continue
		var row: ActionRow = _rows[index]
		if is_instance_valid(row):
			row.set_value(_value_for(str(_ids[index])))


## A on a row: the other thing from whatever it is doing now.
##
## A process in an UNKNOWN state is treated as stopped, so A starts it. That is
## the useful direction: unknown means the supervisor has not reported, and on a
## machine where something has gone wrong the thing a person wants from this menu
## is to get it up.
func _on_row(id: String) -> void:
	if not Services.pending_of(id).is_empty():
		# Already asked. Pressing again cannot make it happen faster and a second
		# wish written over the first is how a toggle ends up fighting itself.
		return
	var running := Services.is_running(id)
	Services.set_wanted(id, not running)
	_refresh_values()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the rail underneath never sees the same press.
	get_viewport().set_input_as_handled()
	closed.emit()
