extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	await process_frame
	var inbox := root.get_node("Notifications")
	var folder := "/tmp/pc1-notification-shell-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder.path_join("marwanos"))
	OS.set_environment("XDG_STATE_HOME", folder)
	var file := FileAccess.open(folder.path_join("marwanos/notifications.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"entries": [{"id": 1, "app": "FDM Controller", "summary": "Download complete", "body": "alpha.bin", "closed": false}]}))
	file.close()
	inbox._poll(false)
	_check(inbox.entries.size() == 1, "persistent inbox read")
	var home: Control = load("res://src/shell_root.gd").new()
	root.add_child(home)
	await process_frame
	inbox.received.emit(inbox.entries[0])
	_check(home._app_alert.visible, "notification appears in system home alert")
	_check(home._app_alert.text == "FDM Controller: Download complete", "system alert copy")
	_check(home._app_alert_timer.time_left > 0, "system alert expires")
	root.get_node("Info").open()
	await process_frame
	var found := false
	for label in root.get_node("Info")._screen.find_children("*", "Label", true, false):
		if label.text == "Download complete":
			found = true
	_check(found, "notification history is controller accessible in Info")
	DirAccess.remove_absolute(folder.path_join("marwanos/notifications.json"))
	DirAccess.remove_absolute(folder.path_join("marwanos"))
	DirAccess.remove_absolute(folder)
	print("Notification shell checks: %d failure(s)" % failures)
	if OS.get_environment("MARWANOS_NOTIFICATION_PREVIEW") == "1":
		await create_timer(8).timeout
	quit(0 if failures == 0 else 1)
