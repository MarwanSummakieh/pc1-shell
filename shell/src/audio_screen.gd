extends Control

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")

var _scroll: ScrollContainer
var _list: VBoxContainer
var _status: Label
var _rows: Array = []
var _controls: Dictionary = {}
var _topology := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_X)
	for edge in ["top", "bottom"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_Y)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)
	var heading := Label.new()
	heading.text = "Audio"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	column.add_child(heading)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 40
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	_scroll.add_child(_list)
	# Reserve feedback space beside the controller hints so requests do not
	# move the focused row or leave an empty subtitle beneath the heading.
	column.add_child(_status)
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select / mute"))
	hints.add_child(TvTheme.hint("← →", "Volume"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)
	Audio.changed.connect(_refresh)
	_refresh()


func _add_row(key: String, title: String, value: String, callback: Callable) -> void:
	var row := ActionRow.new()
	row.setup(title, value)
	row.set_meta("audio_key", key)
	row.activated.connect(callback)
	row.focus_entered.connect(func(): _scroll.ensure_control_visible.call_deferred(row))
	_list.add_child(row)
	# Application names come from clients and can be much longer than fixed labels.
	row._name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row._name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row._name.custom_minimum_size.x = 120
	_rows.append(row)
	_controls[key] = row


func _section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	label.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_list.add_child(label)


func _refresh() -> void:
	_status.text = Audio.error if not Audio.error.is_empty() else ("Applying…" if Audio.pending else "")
	# Values update in place; only device/stream topology rebuilds the focus chain.
	var topology: Array = [Audio.available]
	for kind in ["output", "input"]:
		var item := Audio.selected(kind)
		topology.append([kind, item.get("name", ""), item.get("ports", [])])
	for stream in Audio.streams:
		topology.append([stream.get("id", ""), stream.get("serial", ""), stream.get("label", "")])
	var signature := JSON.stringify(topology)
	if signature != _topology:
		_topology = signature
		var focus_key := ""
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null:
			focus_key = str(focus.get_meta("audio_key", ""))
		for child in _list.get_children():
			_list.remove_child(child)
			child.queue_free()
		_rows.clear()
		_controls.clear()
		if Audio.available:
			_build_devices("output", "Output")
			_build_devices("input", "Microphone")
			_section("Applications")
			if Audio.streams.is_empty():
				_section("No apps playing audio")
			for stream in Audio.streams:
				var key := "stream:" + str(stream.get("id", ""))
				_add_row(key, str(stream.get("label", "Application")), "", _mute.bind("stream", key))
		else:
			_section("Audio unavailable. Check your device, then retry.")
		_add_row("retry", "Refresh", "", _retry)
		TvTheme.wire_column(_rows)
		var restore: Control = _controls.get(focus_key, _rows[0])
		restore.grab_focus()
	for kind in ["output", "input"]:
		var item := Audio.selected(kind)
		_set_value(kind, str(item.get("label", "No device")))
		_set_value(kind + ":volume", _volume_text(item))
		var port_label := str(item.get("port", ""))
		for port in item.get("ports", []):
			if port.get("name") == item.get("port"):
				port_label = str(port.get("label", ""))
		_set_value(kind + ":port", port_label)
	for stream in Audio.streams:
		_set_value("stream:" + str(stream.get("id", "")), _volume_text(stream))


func _build_devices(kind: String, title: String) -> void:
	_section(title)
	_add_row(kind, "Device", "", _cycle_device.bind(kind))
	var item := Audio.selected(kind)
	if item.is_empty():
		return
	if item.get("ports", []).size() > 1:
		_add_row(kind + ":port", "Port", "", _cycle_port.bind(kind))
	_add_row(kind + ":volume", "Volume", "", _mute.bind(kind, kind + ":volume"))


func _volume_text(item: Dictionary) -> String:
	return "%d%%%s" % [int(item.get("volume", 0)), " · Muted" if item.get("muted", false) else ""]


func _set_value(key: String, value: String) -> void:
	if _controls.has(key):
		_controls[key].set_value(value)


func _item(kind: String, key: String) -> Dictionary:
	if kind != "stream":
		return Audio.selected(kind)
	for stream in Audio.streams:
		if "stream:" + str(stream.get("id", "")) == key:
			return stream
	return {}


func _mute(kind: String, key: String) -> void:
	var item := _item(kind, key)
	Audio.request(kind, "mute", item, not bool(item.get("muted", false)))


func _cycle_device(kind: String) -> void:
	var items: Array = Audio.outputs if kind == "output" else Audio.inputs
	if items.is_empty():
		return
	var current := Audio.selected(kind)
	var index := items.find(current)
	Audio.request(kind, "default", items[(index + 1) % items.size()])


func _cycle_port(kind: String) -> void:
	var item := Audio.selected(kind)
	var ports: Array = item.get("ports", [])
	for index in ports.size():
		if ports[index].get("name") == item.get("port"):
			Audio.request(kind, "port", item, ports[(index + 1) % ports.size()].get("name"))
			return
	if not ports.is_empty():
		Audio.request(kind, "port", item, ports[0].get("name"))


func _retry() -> void:
	Audio.request("", "refresh", {})


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel") or (InputMap.has_action("ui_shell_home") and event.is_action_pressed("ui_shell_home")):
		get_viewport().set_input_as_handled()
		closed.emit()
		return
	var delta := 0
	if event.is_action_pressed("ui_left", true):
		delta = -5
	elif event.is_action_pressed("ui_right", true):
		delta = 5
	if delta == 0:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not is_ancestor_of(focus):
		return
	get_viewport().set_input_as_handled()
	var key := str(focus.get_meta("audio_key", ""))
	if key.ends_with(":volume") or key.begins_with("stream:"):
		var kind := "stream" if key.begins_with("stream:") else key.get_slice(":", 0)
		var item := _item(kind, key)
		Audio.request(kind, "volume", item, clampi(int(item.get("volume", 0)) + delta, 0, 100))
