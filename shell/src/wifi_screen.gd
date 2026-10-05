extends Control

## The Wi-Fi screen: what is in range, and how to join it.
##
## The first screen in this shell that CHANGES something. Everything it changes
## goes through Wifi (the seam), which writes a request file that
## marwanos-wifi acts on -- see wifi.gd's header for why the shell still does
## not touch NetworkManager itself.
##
## THE STATES THIS HAS TO RENDER ARE THE POINT, not the list. On this hardware
## the interesting outcome is frequently "there is no wifi device at all"
## (Windows Fast Startup leaves the CNVi radio claimed; iwlwifi's probe times
## out with ETIMEDOUT -- docs/handoff.md). A screen that answered that with an
## empty list would send someone to stand closer to the router for a problem
## that lives in another operating system. So no-device and rf-killed are
## first-class renderings with their own text, and an empty list only ever
## means "the radio looked and found nothing".
##
## Navigation is the settings list's: one axis, hard stops, perpendicular
## pointed at self. B closes. A on a network joins it -- via the keyboard if it
## is secured, straight away if it is open.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")
const Keyboard = preload("res://src/keyboard.gd")

## How the seam's state words read on a television. "unknown" doubles as the
## fallback so a word from a newer service renders as something rather than
## nothing.
const STATE_TEXT := {
	"no-device": "No Wi-Fi adapter found",
	"rf-killed": "Wi-Fi is switched off in hardware",
	"idle": "",
	"scanning": "Looking for networks",
	"connecting": "Connecting",
	"connected": "Connected",
	"failed": "Could not connect",
	"unknown": "Starting up",
}

## States where there is nothing to list and the screen should explain instead
## of showing an empty column.
const DEAD_STATES := ["no-device", "rf-killed"]

var _list: VBoxContainer = null
var _status: Label = null
var _explain: Label = null
var _rows: Array = []
var _keyboard: Keyboard = null
var _pending_ssid: String = ""
var _last_signature: String = ""

## Which row a Y press has armed for deletion, if any. Cleared by moving the
## selection, by the delete happening, and by any state change that rewrites
## the status line -- so an arming can never outlive the sentence explaining it.
var _forget_armed_ssid: String = ""


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
	heading.text = "Wi-Fi"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_status)

	# The long-form explanation for the states that are not about networks at
	# all. Wraps, unlike the status line, because "your other operating system
	# is holding the radio" does not fit on one.
	_explain = Label.new()
	_explain.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_explain.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explain.visible = false
	_explain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_explain)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	column.add_child(_list)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	column.add_child(_build_hints())

	Wifi.state_changed.connect(_on_state_changed)
	Wifi.networks_changed.connect(_on_networks_changed)

	# Ask for a fresh look the moment the screen opens: the service keeps the
	# list warm, but the reason someone opened this screen is usually that
	# something just changed in the room.
	Wifi.request_scan()

	_rebuild()
	_on_state_changed(Wifi.state, Wifi.detail)

	ShellLog.info("wifi screen up: state %s, %d network(s)" % [Wifi.state, Wifi.networks.size()])


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Join"))
	hints.add_child(TvTheme.hint("Y", "Forget"))
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


# ---------------------------------------------------------------------------
# The list
# ---------------------------------------------------------------------------

## Signal strength as four bars' worth of blocks. Text rather than a drawn
## meter because it costs nothing, scales with the font, and is legible at
## three metres -- and because a row is a settings row, whose value is a string.
func _bars(signal_strength: int) -> String:
	var filled := 1
	if signal_strength >= 75:
		filled = 4
	elif signal_strength >= 50:
		filled = 3
	elif signal_strength >= 25:
		filled = 2
	return "█".repeat(filled) + "░".repeat(4 - filled)


func _row_value(network: Dictionary) -> String:
	var parts := PackedStringArray()
	if bool(network.get("in_use", false)):
		parts.append("Connected")
	if str(network.get("security", "open")) == "open":
		parts.append("Open")
	parts.append(_bars(int(network.get("signal", 0))))
	return "  ".join(parts)


## Rebuilt only when the list actually differs, and compared by a signature
## rather than by node count: this screen is polled every two seconds, and a
## rebuild on every poll would drop focus continuously while someone is trying
## to move down the list.
func _rebuild() -> void:
	# The seam's signals outlive remove_child -- a connection is only severed by
	# free, and settings_screen removes this node a frame before queue_free
	# flushes. A poll landing in that gap would reach get_viewport() on a node
	# with no viewport and take the whole shell down with a null instance call.
	if not is_inside_tree():
		return

	var signature := ""
	for network in Wifi.networks:
		signature += "%s|%s|%s;" % [
			network.get("ssid", ""), network.get("in_use", false),
			_bars(int(network.get("signal", 0)))]
	if signature == _last_signature:
		return
	_last_signature = signature

	var focused_ssid := ""
	var owner := get_viewport().gui_get_focus_owner()
	for row in _rows:
		if row == owner:
			focused_ssid = str(row.get_meta("ssid", ""))

	for row in _rows:
		_list.remove_child(row)
		row.queue_free()
	_rows.clear()

	for network in Wifi.networks:
		var row := ActionRow.new()
		row.setup(str(network.get("ssid", "")), _row_value(network))
		row.set_meta("ssid", str(network.get("ssid", "")))
		row.set_meta("secured", str(network.get("security", "open")) != "open")
		row.activated.connect(_on_row_pressed.bind(row))
		# Moving the selection disarms a pending forget: the confirmation
		# sentence names one network, and it must not still be armed once the
		# eye has moved to a different row.
		row.focus_entered.connect(_on_row_focused)
		_list.add_child(row)
		_rows.append(row)

	_wire_focus_neighbours()

	# Restore by SSID, not by index: the list is sorted by signal strength and
	# reorders on its own between scans, so an index would move the selection
	# to a different network while someone was reading it.
	var restored: Control = null
	for row in _rows:
		if str(row.get_meta("ssid", "")) == focused_ssid:
			restored = row
			break
	if restored == null and not _rows.is_empty() and _keyboard == null:
		restored = _rows[0]
	if restored != null and _keyboard == null:
		restored.grab_focus()


## The shared one-axis table -- see TvTheme.wire_column. Kept as a named
## function because this screen rebuilds its list on every scan and calls it
## from more than one place.
func _wire_focus_neighbours() -> void:
	TvTheme.wire_column(_rows)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

func _on_state_changed(state: String, detail: String) -> void:
	var text := str(STATE_TEXT.get(state, STATE_TEXT["unknown"]))
	if state == "connected" and not detail.is_empty():
		text = "Connected to %s" % detail
	elif state == "connecting" and not detail.is_empty():
		text = "Connecting to %s" % detail
	elif state == "failed" and not detail.is_empty():
		text = "Could not connect -- %s" % detail
	_status.text = text
	_status.add_theme_color_override("font_color",
		TvTheme.TEXT_ALERT if state == "failed" or DEAD_STATES.has(state)
		else TvTheme.TEXT_SECONDARY)

	# The two conditions that are not about networks get the long explanation
	# and no list at all.
	_explain.visible = DEAD_STATES.has(state)
	if state == "no-device":
		_explain.text = ("The system reports no Wi-Fi adapter. On this machine that"
			+ " is usually Windows Fast Startup holding the radio: shut Windows down"
			+ " with Restart rather than Shut down, or run powercfg /h off there."
			+ " Ethernet works meanwhile.")
	elif state == "rf-killed":
		_explain.text = ("The radio is switched off in hardware. Look for a Wi-Fi key"
			+ " on the keyboard, or enable it in the firmware setup.")

	if state == "connected":
		# A successful join changes what every row should say (one of them is
		# now the connected one), and the service has already rewritten the
		# list -- but the signature guard would keep the old rows if only the
		# in-use flag moved. Clearing it forces the redraw.
		_last_signature = ""
		_rebuild()


func _on_networks_changed(_networks: Array) -> void:
	_rebuild()


func _on_row_focused() -> void:
	if _forget_armed_ssid.is_empty():
		return
	_forget_armed_ssid = ""
	# Put the real status back, so the armed sentence cannot linger over a row
	# it no longer applies to.
	_on_state_changed(Wifi.state, Wifi.detail)


# ---------------------------------------------------------------------------
# Joining
# ---------------------------------------------------------------------------

func _on_row_pressed(row: Control) -> void:
	var ssid := str(row.get_meta("ssid", ""))
	if ssid.is_empty():
		return

	# Defaults to SECURED when the flag is missing or the security field was
	# empty. Erring that way costs a password prompt nobody needed; erring the
	# other way sends an open-network join at a secured AP and reports a
	# failure whose cause is invisible.
	if not bool(row.get_meta("secured", true)):
		# Open network: nothing to type.
		ShellLog.info("wifi: joining open network \"%s\"" % ssid)
		Wifi.request_connect(ssid, "")
		return

	_pending_ssid = ssid
	_open_keyboard(ssid)


func _open_keyboard(ssid: String) -> void:
	if _keyboard != null:
		return
	_keyboard = Keyboard.new()
	_keyboard.title_text = "Password for %s" % ssid
	_keyboard.masked = true
	_keyboard.submitted.connect(_on_password_submitted)
	_keyboard.cancelled.connect(_on_password_cancelled)
	# Added to this screen rather than to the root, so closing the wifi screen
	# can never leave a keyboard orphaned over the rail.
	add_child(_keyboard)
	# Deaf while the keyboard is up: its own _unhandled_input owns B, and both
	# handlers would otherwise see the same press.
	set_process_unhandled_input(false)


func _close_keyboard() -> void:
	if _keyboard == null:
		return
	var keyboard := _keyboard
	_keyboard = null
	remove_child(keyboard)
	keyboard.queue_free()
	set_process_unhandled_input(true)
	# The keyboard held focus; hand it back to the network that was being
	# joined rather than to the top of the list.
	for row in _rows:
		if str(row.get_meta("ssid", "")) == _pending_ssid:
			row.grab_focus()
			return
	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()


func _on_password_submitted(text: String) -> void:
	var ssid := _pending_ssid
	_close_keyboard()
	if ssid.is_empty():
		return
	# Length only -- never the passphrase itself. See wifi.gd.
	ShellLog.info("wifi: password entered for \"%s\" (%d characters)" % [ssid, text.length()])
	Wifi.request_connect(ssid, text)


func _on_password_cancelled() -> void:
	ShellLog.info("wifi: password entry cancelled")
	_close_keyboard()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
		return

	# Forget, on the same button the keyboard uses for delete. A network saved
	# with the wrong passphrase otherwise fails on every boot with no way to
	# clear it from the couch -- which is the exact class of problem this whole
	# screen exists to remove.
	#
	# CONFIRMED BY A SECOND PRESS, because the first version was one button,
	# irreversible, and adjacent to A ("join") on both pad layouts -- so a
	# thumb landing one button over would silently delete the profile for the
	# network it was connected through, on the screen whose purpose is getting
	# a machine back online. The second press must land on the same row; moving
	# the selection cancels.
	if InputMap.has_action("ui_shell_y") and event.is_action_pressed("ui_shell_y"):
		var owner := get_viewport().gui_get_focus_owner()
		if owner == null or not _rows.has(owner):
			return
		get_viewport().set_input_as_handled()
		var ssid := str(owner.get_meta("ssid", ""))

		if _forget_armed_ssid != ssid:
			_forget_armed_ssid = ssid
			_status.text = "Press Y again to forget %s" % ssid
			_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
			ShellLog.info("wifi: forget armed for \"%s\"" % ssid)
			return

		_forget_armed_ssid = ""
		Wifi.request_forget(ssid)
