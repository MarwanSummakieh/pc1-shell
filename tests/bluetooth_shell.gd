extends SceneTree

var failures := 0

func check(value: bool, label_text: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func _initialize() -> void:
	_run.call_deferred()

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func write_state(service: Node, data: Dictionary) -> void:
	data["updated_at"] = Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(service._folder)
	var file := FileAccess.open(service._folder.path_join("state.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	service._poll()

func request(service: Node) -> Dictionary:
	var path: String = service._folder.path_join("request.json")
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return result if result is Dictionary else {}

func labels(node: Node) -> String:
	var text := ""
	if node is Label:
		text += node.text
	for child in node.get_children():
		text += labels(child)
	return text

func _run() -> void:
	await process_frame
	var service := root.get_node("Bluetooth")
	service._folder = "/tmp/pc1-bluetooth-shell-%d" % OS.get_process_id()
	var data := {"available": true, "status": "no-adapter", "adapters": [], "devices": [], "prompt": {}, "error": "", "busy": ""}
	write_state(service, data)
	var page: Control = load("res://src/bluetooth_page.gd").new()
	root.add_child(page)
	await process_frame
	check(labels(page).contains("No Bluetooth adapter found"), "no-adapter explains missing dongle explicitly")
	var adapter := {"id": "/org/bluez/hci0", "label": "Dongle", "powered": true, "discovering": false}
	var device := {"id": "/org/bluez/hci0/dev_AA", "label": "Wireless Controller", "paired": false, "trusted": false, "connected": false}
	data.status = "ready"
	data.adapters = [adapter]
	data.devices = [device]
	write_state(service, data)
	await process_frame
	page._rows[2].grab_focus()
	await press("ui_accept")
	check(request(service).action == "pair" and request(service).target == device.id, "controller A sends exact selected device pairing request")
	data.prompt = {"token": "confirmation-token", "kind": "confirm", "value": "123456", "device": device.id}
	write_state(service, data)
	await process_frame
	check(labels(page).contains("123456") and page._rows[0].get_meta("bluetooth_key") == "approve", "pairing confirmation displays code and focuses Yes")
	await press("ui_accept")
	check(request(service).action == "respond" and request(service).token == "confirmation-token" and request(service).approved, "controller confirms token-bound pairing prompt")
	data.prompt = {"token": "numeric-token", "kind": "passkey", "value": "", "device": device.id}
	write_state(service, data)
	await process_frame
	await press("ui_up")
	await press("ui_right")
	await press("ui_up")
	check(page._code == "110000" and page._digit == 1, "controller-only numeric passkey editor")
	await press("ui_accept")
	check(request(service).value == "110000", "numeric editor submits passkey with leading zeros preserved")
	await press("ui_cancel")
	check(request(service).action == "cancel", "Back cancels pending pairing")
	data.prompt = {}
	data.devices[0].paired = true
	write_state(service, data)
	await process_frame
	page._rows[2].grab_focus()
	data.devices[0].connected = true
	write_state(service, data)
	await process_frame
	check(root.get_viewport().gui_get_focus_owner().get_meta("bluetooth_key") == device.id, "status update preserves selected device")
	await press("ui_shell_x")
	check(request(service).action == "trust" and request(service).value, "controller X enables trust")
	await press("ui_shell_y")
	check(page._rows.size() == 4 and page._rows[3].get_meta("bluetooth_key") == "forget:" + device.id, "Forget requires separate confirmation row")
	page._rows[3].grab_focus()
	await press("ui_accept")
	check(request(service).action == "remove" and request(service).target == device.id, "confirmed forget removes only selected device")
	page.queue_free()
	print("Bluetooth shell checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
