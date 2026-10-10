extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func _run() -> void:
	await process_frame
	var metadata := root.get_node("Metadata")
	var settings: Control = load("res://src/settings_screen.gd").new()
	root.add_child(settings)
	await process_frame
	settings._metadata_row.activated.emit()
	check(metadata.refresh_pending and settings._metadata_row.disabled, "Update metadata shows pending state and prevents duplicate requests")
	var requests := DirAccess.get_files_at(metadata._folder.path_join("requests"))
	var found := false
	for name in requests:
		var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata._folder.path_join("requests").path_join(name)))
		if request is Dictionary and request.get("action") == "refresh-all": found = true
	check(found, "Settings sends a bulk metadata request to the worker")
	metadata.refresh_pending = false
	metadata.refresh = {"status": "loading", "completed": 1, "total": 3}
	metadata.changed.emit()
	check(settings._metadata_row._value.text.contains("1 of 3"), "worker progress appears in Settings")
	metadata.refresh = {"status": "done", "completed": 3, "failed": 1}
	metadata.changed.emit()
	check(not settings._metadata_row.disabled and settings._metadata_row._value.text.contains("need attention"), "partial failure allows retry and explains how to correct a match")
	root.remove_child(settings)
	settings.queue_free()
	print("Console refinement checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
