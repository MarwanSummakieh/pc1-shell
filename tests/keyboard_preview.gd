extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OS.get_environment("PC1_UI_CAPTURE_DIR").path_join(name))

func _run() -> void:
	root.get_node("PlayerOne").device = 0
	var shell: Control = load("res://scenes/shell_root.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	root.get_node("Files").open()
	await process_frame
	var keyboard: Control = load("res://src/keyboard.gd").new()
	keyboard.title_text = "Search this folder"
	keyboard.masked = false
	keyboard.initial_text = "holiday"
	root.add_child(keyboard)
	await capture("keyboard-text.png")
	keyboard.move_panel(Vector2(-1100, -450))
	await capture("keyboard-moved.png")
	root.remove_child(keyboard)
	keyboard.queue_free()
	keyboard = load("res://src/keyboard.gd").new()
	keyboard.title_text = "Enter number"
	keyboard.input_context = "numeric"
	keyboard.masked = false
	root.add_child(keyboard)
	await capture("keyboard-numeric.png")
	root.remove_child(keyboard)
	keyboard.queue_free()
	keyboard = load("res://src/keyboard.gd").new()
	keyboard.title_text = "Search"
	keyboard.masked = false
	keyboard.live_input = true
	root.add_child(keyboard)
	await process_frame
	keyboard._saved_position = Vector2(0.5, 1.0)
	keyboard._restore_position()
	await capture("keyboard-floating-live.png")
	quit()
