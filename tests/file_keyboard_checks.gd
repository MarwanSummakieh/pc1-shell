extends RefCounted

## Runs inside the disposable tools fixture; every write stays below its temp
## home or cross-filesystem fixture. Test the frame-by-frame production job.
func finish(job: RefCounted, tree: SceneTree) -> void:
	for _frame in 500:
		if not job.running:
			return
		job.step()
		await tree.process_frame

func write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func run(tree: SceneTree, screen: Control, home: String, check: Callable) -> void:
	var Transfer = load("res://src/file_transfer.gd")
	var Trash = load("res://src/file_trash.gd")
	var source := home.path_join("source/large.dat")
	var dest := home.path_join("destination")
	write(source, "abcdefgh".repeat(256 * 1024))
	var job = Transfer.new()
	job.begin([source], dest, false)
	job.step()
	job.step()
	job.step()
	check.call(job.running and job.copied_bytes <= Transfer.CHUNK and not FileAccess.file_exists(dest.path_join("large.dat")), "large copy yields and stays hidden until complete")
	job.cancel()
	await finish(job, tree)
	check.call(not FileAccess.file_exists(dest.path_join("large.dat")) and FileAccess.file_exists(source), "cancelled copy keeps the original and removes its unfinished destination")
	check.call(Array(DirAccess.open(dest).get_files()).filter(func(name: String): return name.begins_with(".marwanos-transfer-")).is_empty(), "cancel removes hidden staging files")
	job = Transfer.new()
	job.begin([source], dest, false)
	await finish(job, tree)
	check.call(job.errors.is_empty() and job.completed.size() == 1 and FileAccess.get_file_as_bytes(source) == FileAccess.get_file_as_bytes(dest.path_join("large.dat")), "incremental copy preserves all bytes")
	job = Transfer.new()
	job.begin([source], dest, false)
	await finish(job, tree)
	check.call(job.completed[0]["name"] == "large (copy).dat", "incremental collision preserves the existing destination")
	var literal := home.path_join("source/literal_$(touch INJECTED)_`touch INJECTED2`_\".txt")
	write(literal, "Literal filename")
	job = Transfer.new()
	job.begin([literal], dest, true)
	await finish(job, tree)
	check.call(job.errors.is_empty() and FileAccess.get_file_as_string(dest.path_join(literal.get_file())) == "Literal filename" and not FileAccess.file_exists("INJECTED") and not FileAccess.file_exists("INJECTED2"), "file moves pass dollar, backtick and quote characters literally without shell execution")
	var race := home.path_join("source/race.dat")
	write(race, "x".repeat(1024 * 1024))
	job = Transfer.new()
	job.begin([race], dest, false)
	job.step()
	job.step()
	write(race, "Changed source")
	await finish(job, tree)
	check.call(not job.errors.is_empty() and FileAccess.get_file_as_string(race) == "Changed source" and not FileAccess.file_exists(dest.path_join("race.dat")), "source changes abort the copy and keep its new original")
	var committed_collision := home.path_join("source/late-collision.txt")
	write(committed_collision, "Source")
	job = Transfer.new()
	job.begin([committed_collision], dest, false)
	job.step()
	write(dest.path_join("late-collision.txt"), "Existing destination")
	await finish(job, tree)
	check.call(not job.errors.is_empty() and FileAccess.get_file_as_string(dest.path_join("late-collision.txt")) == "Existing destination", "destination created during copying is never overwritten")
	job = Transfer.new()
	job.begin([home.path_join("source")], home.path_join("source/../source/child"), false)
	await finish(job, tree)
	check.call(not job.errors.is_empty() and not DirAccess.dir_exists_absolute(home.path_join("source/child")), "normalized paths cannot copy a folder into itself")
	OS.execute("ln", ["-s", "missing-target", dest.path_join("link.txt")])
	write(home.path_join("source/link.txt"), "Regular file")
	job = Transfer.new()
	job.begin([home.path_join("source/link.txt")], dest, false)
	await finish(job, tree)
	check.call(Transfer.is_link(dest.path_join("link.txt")) and FileAccess.get_file_as_string(dest.path_join("link (copy).txt")) == "Regular file", "dangling destination links count as collisions and are never followed")
	OS.execute("ln", ["-s", home.path_join("source"), home.path_join("source-alias")])
	job = Transfer.new()
	job.begin([home.path_join("source")], home.path_join("source-alias"), false)
	await finish(job, tree)
	check.call(not job.errors.is_empty(), "copy refuses a destination reached through a directory link")
	var cross := OS.get_environment("PC1_TOOLS_CROSS_HOME").path_join("incremental")
	DirAccess.make_dir_absolute(cross)
	job = Transfer.new()
	job.begin([home.path_join("with-link")], cross, true)
	await finish(job, tree)
	check.call(not job.errors.is_empty() and job.errors[0].contains("contains links"), "cross-filesystem move reports skipped links")
	check.call(FileAccess.file_exists(home.path_join("with-link/original.txt")) and Transfer.is_link(home.path_join("with-link/link.txt")) and FileAccess.get_file_as_string(cross.path_join("with-link/original.txt")) == "Original data\n", "incomplete move retains original tree and publishes its regular files")
	var moving := home.path_join("move-complete")
	DirAccess.make_dir_absolute(moving)
	write(moving.path_join(".keep"), "Hidden content")
	write(moving.path_join("large.dat"), "z".repeat(1024 * 1024))
	job = Transfer.new()
	job.begin([moving], cross, true)
	job.step()
	job.step()
	job.step()
	check.call(job.running and DirAccess.dir_exists_absolute(moving), "cross-filesystem move yields rather than using Godot's blocking rename fallback")
	await finish(job, tree)
	check.call(job.errors.is_empty() and not DirAccess.dir_exists_absolute(moving) and FileAccess.get_file_as_string(cross.path_join("move-complete/.keep")) == "Hidden content" and FileAccess.get_file_as_string(cross.path_join("move-complete/large.dat")).length() == 1024 * 1024, "completed cross-filesystem move preserves hidden content before removing its original")
	var trash_file := home.path_join("source/restore # sample.txt")
	write(trash_file, "Restore me")
	check.call(Trash.trash(trash_file) == OK and not FileAccess.file_exists(trash_file), "delete writes a recoverable trash entry")
	var entries: Array = Trash.entries()
	check.call(entries.size() == 1 and entries[0]["path"] == trash_file, "trash metadata preserves escaped original paths")
	write(trash_file, "New original")
	var restored: Dictionary = Trash.restore(str(entries[0]["id"]))
	check.call(restored.get("ok", false) and FileAccess.get_file_as_string(str(restored.get("path", ""))) == "Restore me" and FileAccess.get_file_as_string(trash_file) == "New original", "restore preserves collisions and restores content")
	check.call(not Trash.restore("../escape").get("ok", false), "restore rejects metadata traversal")
	var pane: Control = screen._pane()
	pane.show_directory(dest)
	pane.set_search("LARGE")
	check.call(pane._items.size() == 2 and pane.search_text == "LARGE", "controller search filters names without case sensitivity")
	pane.show_directory(home.path_join("source"))
	check.call(pane.search_text.is_empty() and pane._items.size() >= 3, "entering another folder clears its search")
	check.call(pane.history_move(-1) and pane.path == dest, "previous folder restores navigation history")
	check.call(pane.history_move(1) and pane.path == home.path_join("source"), "next folder restores navigation history")
	screen._clipboard = {"paths": [source], "cut": false}
	screen._paste_into(dest)
	await tree.process_frame
	check.call(screen._transfer != null, "Files starts the asynchronous production transfer")
	screen._transfer.cancel()
	for _frame in 50:
		await tree.process_frame
		if screen._transfer == null:
			break
	check.call(screen._transfer == null and tree.root.gui_get_focus_owner() != null, "cancelled production transfer restores controller focus")
	var picks: Array = []
	var picker: Control = load("res://src/files_screen.gd").new()
	picker.picker_mode = true
	picker.picker_extensions = PackedStringArray(["txt"])
	picker.files_picked.connect(func(paths: PackedStringArray): picks.append(paths))
	tree.root.add_child(picker)
	await tree.process_frame
	picker._pane().show_directory(dest)
	check.call(picker._pane()._items.all(func(item: Control): return item.entry["is_dir"] or str(item.entry["name"]).ends_with(".txt")), "upload picker filters accepted file extensions")
	picker._choose_picker_entries([{"path": dest.path_join("example.txt"), "is_dir": false}])
	check.call(picks.size() == 1 and picks[0] == PackedStringArray([dest.path_join("example.txt")]), "upload picker returns absolute readable paths")
	tree.root.remove_child(picker)
	picker.queue_free()
	await tree.process_frame
	var Keyboard = load("res://src/keyboard.gd")
	var keyboard: Control = Keyboard.new()
	keyboard.initial_text = "private"
	keyboard.masked = true
	tree.root.add_child(keyboard)
	await tree.process_frame
	await tree.process_frame
	var rect: Rect2 = keyboard.get_panel_rect()
	check.call(rect.size.x <= 600 and rect.size.y <= 520, "text keyboard fits within a compact readable panel")
	check.call(not keyboard._entry.text.contains("private"), "password draft remains masked")
	var owner := tree.root.gui_get_focus_owner()
	var router := tree.root.get_node("ControllerRouter")
	var player := tree.root.get_node("PlayerOne")
	var axes: Array = router._axes.duplicate()
	axes[JOY_AXIS_RIGHT_X] = -0.9
	router._apply_state({"connected": true, "name": "Tools fixture controller",
		"buttons": router._buttons.duplicate(), "axes": axes})
	await tree.process_frame
	await tree.process_frame
	check.call(keyboard.get_panel_rect().position.x < rect.position.x and tree.root.gui_get_focus_owner() == owner, "right stick moves the keyboard without moving key focus")
	# Cross at least one real reconciliation timeout with the stick held. The
	# production native-disconnect guard must retain a routed player and motion.
	await tree.create_timer(player.RECONCILE_SECONDS + 0.1).timeout
	check.call(player.device == router.DEVICE and player.guid == "pc1-controller-router"
		and is_equal_approx(player.axis(JOY_AXIS_RIGHT_X), -0.9)
		and keyboard.get_panel_rect().position.x < rect.position.x
		and tree.root.gui_get_focus_owner() == owner, "routed keyboard movement and key focus survive the real controller reconciliation timer")
	axes[JOY_AXIS_RIGHT_X] = 0.0
	router._apply_state({"connected": true, "name": "Tools fixture controller",
		"buttons": router._buttons.duplicate(), "axes": axes})
	await tree.process_frame
	check.call(is_zero_approx(player.axis(JOY_AXIS_RIGHT_X)), "routed right-stick release neutralizes keyboard movement")
	keyboard.move_panel(Vector2(-10000, -10000))
	check.call(keyboard.get_panel_rect().position == Vector2.ONE * Keyboard.PANEL_GAP and tree.root.gui_get_focus_owner() == owner, "moving keyboard clamps to viewport and preserves text navigation focus")
	keyboard.move_panel(Vector2(10000, 10000))
	check.call(tree.root.get_visible_rect().encloses(keyboard.get_panel_rect()), "keyboard clamps at the opposite viewport edge")
	keyboard.move_panel(Vector2(-280, -180))
	var saved: Vector2 = keyboard._saved_position
	tree.root.remove_child(keyboard)
	keyboard.queue_free()
	keyboard = Keyboard.new()
	keyboard.input_context = "numeric"
	tree.root.add_child(keyboard)
	await tree.process_frame
	await tree.process_frame
	check.call(keyboard._saved_position.is_equal_approx(saved), "keyboard position persists when opened in a different input context")
	check.call(keyboard.get_panel_rect().size.x <= 420 and keyboard._flat.size() == 15, "number pad is narrower than the text keyboard")
	tree.root.remove_child(keyboard)
	keyboard.queue_free()
	await tree.process_frame
	keyboard = Keyboard.new()
	keyboard.live_input = true
	keyboard.masked = false
	var inserts: Array = []
	var edits: Array = []
	keyboard.text_inserted.connect(func(value: String): inserts.append(value))
	keyboard.editing_key.connect(func(value: String): edits.append(value))
	tree.root.add_child(keyboard)
	await tree.process_frame
	keyboard._insert("hello")
	keyboard._move_caret(-1)
	keyboard._on_backspace()
	check.call(inserts == ["hello"] and edits == ["Left", "BackSpace"] and keyboard._text.is_empty(), "live browser keyboard forwards text and caret edits without storing a draft")
	tree.root.remove_child(keyboard)
	keyboard.queue_free()
	screen._pane().grab_pane_focus()
