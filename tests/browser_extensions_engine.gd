extends SceneTree

const Extensions = preload("res://src/browser_extensions.gd")
var failed := false
var view: Control
var expected := "Extension active"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	expected = OS.get_environment("PC1_EXTENSION_EXPECTED_TITLE")
	if not ClassDB.class_exists("MowserView"):
		push_error("MowserView missing from extension engine test")
		quit(1)
		return
	view = ClassDB.instantiate("MowserView")
	view.size = Vector2(1000, 700)
	var accepted: bool = view.set_extension_paths(Extensions.enabled_paths())
	if OS.get_environment("PC1_EXTENSION_EXPECT_REJECTED") == "1":
		if accepted:
			push_error("Engine accepted a missing extension directory")
			quit(1)
			return
		accepted = view.set_extension_paths(PackedStringArray())
	if not accepted:
		push_error("Engine rejected managed extension paths")
		quit(1)
		return
	view.page_failed.connect(func(url: String, reason: String):
		failed = true
		push_error("Extension page failed: " + url + " " + reason))
	root.add_child(view)
	view.load_url(OS.get_environment("PC1_EXTENSION_TEST_URL"))
	# The content script runs at document_idle, after the ordinary page title.
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not failed:
		await create_timer(0.1).timeout
		if view.get_page_title() == expected: break
	await create_timer(1.0).timeout
	var title: String = view.get_page_title()
	print("Extension engine title: " + title + " (expected " + expected + ")")
	var success := not failed and title == expected
	if success and expected == "Extension active":
		var page := Extensions.page_url(Extensions.entries()[0], view.get_active_extension_paths())
		view.load_url(page)
		deadline = Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and view.get_page_title() != "Extension settings":
			await create_timer(0.1).timeout
		success = not failed and view.get_page_title() == "Extension settings"
		print("Extension settings page: " + view.get_page_title())
	root.remove_child(view)
	view.queue_free()
	await create_timer(0.5).timeout
	print("Browser extension engine checks: %d failure(s)" % (0 if success else 1))
	quit(0 if success else 1)
