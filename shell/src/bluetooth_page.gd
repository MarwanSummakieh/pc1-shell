extends Control

signal closed()
const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")
var _column: VBoxContainer
var _rows: Array = []
var _code := "000000"
var _digit := 0
var _prompt_token := ""
var _forget_armed := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_X)
	for edge in ["top", "bottom"]:
		safe.add_theme_constant_override("margin_" + edge, TvTheme.SAFE_MARGIN_Y)
	add_child(safe)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	safe.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 24)
	scroll.add_child(_column)
	Bluetooth.changed.connect(_rebuild)
	_rebuild()


func _label(text: String, large: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK if large else TvTheme.SIZE_BODY)
	_column.add_child(label)


func _row(key: String, title: String, subtitle: String, action: Callable) -> void:
	var row := ActionRow.new()
	row.setup(title, subtitle)
	row.set_meta("bluetooth_key", key)
	row.activated.connect(action)
	_column.add_child(row)
	_rows.append(row)


func _rebuild() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	var selected := str(owner.get_meta("bluetooth_key", "")) if owner != null else ""
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	_rows.clear()
	_label("Bluetooth", true)
	var state: Dictionary = Bluetooth.snapshot
	var prompt: Dictionary = state.get("prompt", {})
	var token := str(prompt.get("token", ""))
	if token != _prompt_token:
		_prompt_token = token
		_code = "0000" if prompt.get("kind", "") == "pin" else "000000"
		_digit = 0
		selected = ""
	if not Bluetooth.error.is_empty():
		_label(Bluetooth.error)
	if state.get("status", "") == "no-adapter":
		_label("No Bluetooth adapter found. Plug in your USB dongle to pair controllers.")
	elif not state.get("available", false):
		_label("Waiting for the Bluetooth service.")
	elif not prompt.is_empty():
		var kind := str(prompt.get("kind", ""))
		if kind in ["pin", "passkey"]:
			_label("Enter the pairing code shown by your device. Left/right chooses a digit; up/down changes it.")
			if kind == "pin":
				_label("L1 removes a digit; R1 adds a digit.")
			_label(_code.left(_digit) + "[" + _code.substr(_digit, 1) + "]" + _code.substr(_digit + 1), true)
			_row("submit-code", "Confirm code", "", func(): Bluetooth.request("respond", "", {"token": token, "approved": true, "value": _code}))
		elif kind == "display":
			_label("Enter this code on the device: " + str(prompt.get("value", "")))
		else:
			_label("Does this code match your device? " + str(prompt.get("value", "")) if kind == "confirm" else "Allow pairing with the selected device?")
			_row("approve", "Yes, pair", "", func(): Bluetooth.request("respond", "", {"token": token, "approved": true}))
		_row("reject", "Cancel pairing", "", func(): Bluetooth.request("respond", "", {"token": token, "approved": false}))
	else:
		var busy := str(state.get("busy", ""))
		if not busy.is_empty():
			_label("Bluetooth change in progress…")
			_row("cancel", "Cancel", "", func(): Bluetooth.request("cancel"))
		else:
			for adapter in state.get("adapters", []):
				var id := str(adapter.id)
				_row("power:" + id, "Turn Bluetooth off" if adapter.get("powered", false) else "Turn Bluetooth on", "", func(): Bluetooth.request("power", id, {"value": not adapter.get("powered", false)}))
				_row("scan:" + id, "Stop scanning" if adapter.get("discovering", false) else "Find controllers", str(adapter.get("label", "Bluetooth")), func(): Bluetooth.request("stop-scan" if adapter.get("discovering", false) else "scan", id))
			for device in state.get("devices", []):
				var id := str(device.id)
				var connected := bool(device.get("connected", false))
				var paired := bool(device.get("paired", false))
				_row(id, str(device.get("label", "Device")), "Connected" if connected else ("Paired · press to reconnect" if paired else "Press to pair"), func(): Bluetooth.request("disconnect" if connected else ("connect" if paired else "pair"), id))
				if _forget_armed == id:
					_row("forget:" + id, "Forget this device?", "A to remove its saved pairing", func(): Bluetooth.request("remove", id); _forget_armed = "")
			_label("Put your controller in pairing mode. Paired controllers reconnect automatically when available.")
	_label("A Select · B Back / cancel pairing · X Trust / untrust · Y Forget selected device")
	TvTheme.wire_column(_rows)
	for row in _rows:
		if row.get_meta("bluetooth_key") == selected:
			row.grab_focus()
			return
	if not _rows.is_empty():
		_rows[0].grab_focus()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var prompt: Dictionary = Bluetooth.snapshot.get("prompt", {})
	if prompt.get("kind", "") in ["pin", "passkey"]:
		var changed := true
		if event.is_action_pressed("ui_left"):
			_digit = posmod(_digit - 1, _code.length())
		elif event.is_action_pressed("ui_right"):
			_digit = posmod(_digit + 1, _code.length())
		elif prompt.get("kind", "") == "pin" and event.is_action_pressed("ui_shell_l1") and _code.length() > 1:
			_code = _code.left(_code.length() - 1)
			_digit = mini(_digit, _code.length() - 1)
		elif prompt.get("kind", "") == "pin" and event.is_action_pressed("ui_shell_r1") and _code.length() < 16:
			_code += "0"
		elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
			var number := posmod(int(_code.substr(_digit, 1)) + (1 if event.is_action_pressed("ui_up") else -1), 10)
			_code = _code.left(_digit) + str(number) + _code.substr(_digit + 1)
		else:
			changed = false
		if changed:
			get_viewport().set_input_as_handled()
			_rebuild()
			return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not prompt.is_empty() or not str(Bluetooth.snapshot.get("busy", "")).is_empty():
			Bluetooth.request("cancel")
		else:
			closed.emit()
	elif event.is_action_pressed("ui_shell_y"):
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null:
			_forget_armed = str(owner.get_meta("bluetooth_key", ""))
			_rebuild()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_shell_x"):
		var owner := get_viewport().gui_get_focus_owner()
		var selected := str(owner.get_meta("bluetooth_key", "")) if owner != null else ""
		for device in Bluetooth.snapshot.get("devices", []):
			if str(device.id) == selected and device.get("paired", false):
				Bluetooth.request("trust", selected, {"value": not device.get("trusted", false)})
				get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(get_node_or_null("/root/Bluetooth")):
		Bluetooth.request("close")
