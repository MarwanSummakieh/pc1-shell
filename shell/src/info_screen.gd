extends Control

## Info: everything the machine can say about itself, on one page, all of it
## read-only.
##
## WHY THIS EXISTS. The settings screen had grown to fourteen rows, and nine of
## them answered a question rather than doing anything -- System, Engine,
## Display server, Surface, Renderer, Controller, Network, Connection, Address.
## Scrolling past nine facts to reach the five rows that act is the wrong shape
## for the screen somebody opens BECAUSE something is wrong, and the sheer
## length made two real duplicates hard to see: three rows about the picture
## (Display server, Surface, Renderer) sitting above a Display row that changes
## it, and three rows about the network (Network, Connection, Address) sitting
## above a Wi-Fi row that joins one.
##
## So the facts moved here, behind one row, and the duplicates were merged on
## the way rather than carried across:
##
##   Display server + Surface   one line. Both were about the window the
##                              compositor handed the shell; two rows made a
##                              person cross-reference a size against a screen
##                              number, which is precisely the comparison the
##                              value can do itself.
##   Network + Connection       one line. "Online" and "Wi-Fi -- HomeNet" are
##                              the same sentence broken in half; either alone
##                              is the half somebody has to ask again about.
##
## STILL READ-ONLY, and that is the whole contract of this page rather than a
## Phase 0 apology. Everything that ACTS stayed on the settings screen: Display,
## Steam, Wi-Fi, Updates, Terminal. A person can read this page in a photograph
## and press nothing, which is exactly what "send me a picture of the info
## screen" needs to be worth asking for.
##
## AND IT ABSORBED THE LAST DUPLICATE. The quick settings panel behind the bar's
## wifi corner carried its own Network row -- the same two facts, worded a third
## way, on a panel that also duplicated the settings screen and the process menu.
## That panel is deleted; this page is where the network is described, and the
## corner it used to drop from is now this page's door.
##
## A PEER SURFACE, NOT A CHILD OF SETTINGS. It used to be a page WITHIN settings,
## opened by a row at the top of that screen and returning to it on B. The menu
## rewrite of 2026-08-12 gave it its own seam (info.gd) and its own door, so it
## now opens over the home rail exactly as settings, stores, power and files do,
## and B returns to the rail. What did NOT change is this file: it builds rows
## and emits `closed`, and it never knew what was underneath it.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const SettingsRow = preload("res://src/settings_row.gd")

var _rows: Array = []
var _scroll: ScrollContainer = null
var _controller_row: SettingsRow = null
var _network_row: SettingsRow = null
var _address_row: SettingsRow = null


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
	heading.text = "Info"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	# Scrolls for the settings screen's reason, unchanged by the move: the rows
	# plus their gaps are taller than the safe area once the heading and the hint
	# row have taken their share, and a focus chain does not care about the
	# viewport -- so without this the last rows are reachable and invisible.
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)

	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)
	var notifications_heading := Label.new()
	notifications_heading.text = "Notifications"
	notifications_heading.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	list.add_child(notifications_heading)
	if Notifications.entries.is_empty():
		_add_row(list, "Notifications", "No notifications")
	else:
		var recent: Array = Notifications.entries.duplicate()
		recent.reverse()
		for index in mini(recent.size(), 10):
			var entry: Dictionary = recent[index]
			_add_row(list, str(entry.get("summary", "")), "%s · %s" % [str(entry.get("app", "")), str(entry.get("body", ""))])

	_add_row(list, "System", _system_value())
	_add_row(list, "Engine", _engine_value())
	# The merged picture row -- server, window size and whether that window
	# matches a real screen, which is the comparison somebody was making by eye
	# across two rows. See the header.
	_add_row(list, "Display server", _display_value())
	_add_row(list, "Renderer", RenderingServer.get_video_adapter_name())
	_controller_row = _add_row(list, "Controller", _controller_value())
	# The merged network row: state and link in one sentence.
	_network_row = _add_row(list, "Network", _network_value())
	# Kept as its own row rather than folded into the one above, and it earned
	# that: the bench came up on 2026-08-08 having joined nothing, and finding it
	# meant sweeping a /24 from another machine. An address is what somebody
	# photographs and types somewhere else, so it gets its own line to read.
	_address_row = _add_row(list, "Address", _address_value())

	column.add_child(_build_hints())

	TvTheme.wire_column(_rows)
	for row in _rows:
		row.focus_entered.connect(_on_row_focused.bind(row))

	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	PlayerOne.player_one_present.connect(_on_player_one_present)
	PlayerOne.player_one_absent.connect(_on_player_one_absent)
	SystemStatus.network_changed.connect(_on_network_changed)
	SystemStatus.network_info_changed.connect(_on_network_info_changed)

	ShellLog.info("info screen up with %d rows" % _rows.size())


## Keep the focused row on screen. Deferred because the first call arrives from
## the grab_focus above, before the scroll container has been laid out.
func _on_row_focused(row: Control) -> void:
	if _scroll == null:
		return
	_scroll.ensure_control_visible.call_deferred(row)


func _add_row(list: Control, name_text: String, value_text: String) -> SettingsRow:
	var row := SettingsRow.new()
	row.setup(name_text, value_text)
	list.add_child(row)
	_rows.append(row)
	return row


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	# NO "A" HINT. Nothing on this page does anything, so advertising a button
	# that logs "read-only" would be the settings screen's old lie with fewer
	# rows around it. B is the only move and it is the only glyph.
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


# ---------------------------------------------------------------------------
# Values
# ---------------------------------------------------------------------------

## PRETTY_NAME from os-release, which on the appliance is the image name and
## version the build stamped -- the same string that identifies a stick in the
## handoff notes. On a desk run it truthfully names whatever the container is.
func _system_value() -> String:
	var file := FileAccess.open("/etc/os-release", FileAccess.READ)
	if file == null:
		return "Unknown"
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("PRETTY_NAME="):
			return line.trim_prefix("PRETTY_NAME=").trim_prefix("\"").trim_suffix("\"")
	return "Unknown"


func _engine_value() -> String:
	var info := Engine.get_version_info()
	return "Godot %s.%s.%s" % [info.get("major", 0), info.get("minor", 0), info.get("patch", 0)]


## Server, window size, and the surface verdict, in one line.
##
## THE MISMATCH CASE IS THE WHOLE POINT and it is why this merge is not merely
## shorter. SSH to the bench has been down for days at a time and the journal is
## unreachable without it, so the diagnostic that keeps mattering -- did the
## compositor hand the shell a window the size of a real screen, or something
## else -- has to be readable in a photograph. Two rows made that a comparison
## somebody performed by eye between a size here and a size there; one row makes
## it a sentence that already knows the answer. get_name() says X11 under
## gamescope's XWayland; see the README's display-driver section for why that is
## not evidence about the compositor.
func _display_value() -> String:
	var window_size := DisplayServer.window_get_size()
	var count := DisplayServer.get_screen_count()
	var head := "%s, %d x %d" % [DisplayServer.get_name(), window_size.x, window_size.y]
	if count == 0:
		return "%s -- no screens reported" % head
	for index in count:
		if DisplayServer.screen_get_size(index) == window_size:
			return "%s -- matches screen %d of %d" % [head, index, count]
	var first := DisplayServer.screen_get_size(0)
	return "%s -- MISMATCH, screen 0 is %d x %d" % [head, first.x, first.y]


func _controller_value() -> String:
	if PlayerOne.has_controller():
		return PlayerOne.pad_name
	return "Not connected"


## Reachability and the link that carries it, in one sentence -- the two halves
## the Network and Connection rows used to hold separately. "Online" alone never
## said over what, and "Wi-Fi -- HomeNet" alone never said whether anything
## answered; either row on its own was the half somebody had to ask about again.
func _network_value() -> String:
	var link := _link_value()
	match SystemStatus.network:
		"online":
			return "Online -- %s" % link if not link.is_empty() else "Online"
		"offline":
			return "Offline -- %s" % link if not link.is_empty() else "Offline"
		_:
			return "Unknown -- the system has not said"


## netcheck's one-line link description, made readable: "wifi HomeNet" becomes
## "Wi-Fi HomeNet". The raw first word decides the family; everything after it is
## the connection's name and passes through untouched.
func _link_value() -> String:
	var info := SystemStatus.network_info
	# The address rides after a tab; the link description is everything before.
	if info.contains("\t"):
		info = info.get_slice("\t", 0)
	if info.is_empty():
		return ""
	var kind := info.get_slice(" ", 0)
	var link_name := info.substr(kind.length()).strip_edges()
	match kind:
		"wifi":
			return "Wi-Fi %s" % link_name if not link_name.is_empty() else "Wi-Fi"
		"ethernet":
			return "Ethernet %s" % link_name if not link_name.is_empty() else "Ethernet"
		"link":
			return "link on %s" % link_name if not link_name.is_empty() else "link up"
		"none":
			return "no link"
		_:
			return info


## The address netcheck reports for whichever device carries the link, or a
## plain statement that there is none -- which on a fresh install is the true
## answer and the one that tells someone to go and join a network.
func _address_value() -> String:
	var info := SystemStatus.network_info
	if not info.contains("\t"):
		return "Not connected"
	var address := info.substr(info.find("\t") + 1).strip_edges()
	return address if not address.is_empty() else "No address"


func _refresh_network_rows() -> void:
	if _network_row != null:
		_network_row.set_value(_network_value())
	if _address_row != null:
		_address_row.set_value(_address_value())


func _on_network_changed(_state: String) -> void:
	_refresh_network_rows()


func _on_network_info_changed(_info: String) -> void:
	_refresh_network_rows()


func _refresh_controller() -> void:
	if _controller_row != null:
		_controller_row.set_value(_controller_value())


func _on_player_one_present(_device: int, _pad_name: String) -> void:
	_refresh_controller()


func _on_player_one_absent() -> void:
	_refresh_controller()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
