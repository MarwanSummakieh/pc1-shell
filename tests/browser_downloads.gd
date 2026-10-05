extends SceneTree
var web: Control
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func _run() -> void:
	web = load("res://src/browser_screen.gd").new()
	root.add_child(web)
	var base := "http://127.0.0.1:" + OS.get_environment("PC1_DOWNLOAD_PORT")
	web.open_url(base)
	for attempt in 100:
		if web._view.get_page_title() == "Download fixture": break
		await create_timer(0.1).timeout
	check(web._view.get_page_title() == "Download fixture", "download fixture loads")
	# The title arrives before Chromium's first layout/paint. Allow its input
	# surface to become ready before clicking, as a person viewing the page does.
	await create_timer(0.5).timeout
	web._view.set_pointer(Vector2(140, 75))
	web._click(true)
	await create_timer(0.1).timeout
	web._click(false)
	await create_timer(3.0).timeout
	check(web._view.get_page_title() == "Route changed", "soft navigation does not crash the shell")
	web._view.set_download_directory(OS.get_environment("PC1_DOWNLOAD_DIR"))
	web._view.load_url(base + "/file")
	var saved: Dictionary = {}
	for attempt in 100:
		for download: Dictionary in web._downloads.values():
			if download.state == "complete":
				saved = download
		if not saved.is_empty(): break
		await create_timer(0.1).timeout
	check(not saved.is_empty(), "download completes through the embedded engine")
	if not saved.is_empty():
		check(FileAccess.get_file_as_string(str(saved.path)) == "PC1 download test\n".repeat(1024), "downloaded file contains the expected bytes")
	web._open_downloads()
	check(web._menu != null and not web._menu.items.is_empty(), "Downloads menu opens with download status")
	web._close_menu()
	print("Browser download checks: %d failure(s)" % failures)
	root.remove_child(web)
	web.queue_free()
	await create_timer(0.5).timeout
	quit(1 if failures else 0)
