extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var web: Control = load("res://src/browser_screen.gd").new()
	root.add_child(web)
	web.open_url("https://example.com", "Internet verification")
	var opened := false
	for attempt in 200:
		if web._view.get_page_title() == "Example Domain":
			opened = true
			break
		await create_timer(0.1).timeout
	if opened:
		print("PASS: internet HTTPS page renders with normal certificate validation")
	else:
		push_error("FAIL: internet HTTPS page did not open: " + web._last_error)
	print("Browser engine checks: %d failure(s)" % (0 if opened else 1))
	root.remove_child(web)
	web.queue_free()
	await create_timer(0.5).timeout
	quit(0 if opened else 1)
