extends Button

const TvTheme = preload("res://src/tv_theme.gd")
var task: Dictionary = {}
var _name: Label
var _detail: Label
var _progress: ProgressBar

func _ready() -> void:
	custom_minimum_size.y = 138
	add_theme_stylebox_override("normal", TvTheme.card_idle_box())
	var hover := TvTheme.card_idle_box()
	hover.bg_color = TvTheme.SURFACE_FOCUS
	add_theme_stylebox_override("hover", hover)
	var pressed_box := TvTheme.card_idle_box()
	pressed_box.bg_color = TvTheme.SURFACE_PRESSED
	add_theme_stylebox_override("pressed", pressed_box)
	add_theme_stylebox_override("focus", TvTheme.card_focus_ring(8))
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left", "right"]: pad.add_theme_constant_override("margin_" + edge, 24)
	for edge in ["top", "bottom"]: pad.add_theme_constant_override("margin_" + edge, 16)
	add_child(pad)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_name.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_name)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_detail.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_detail)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 6
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = TvTheme.SURFACE_FOCUS
	_progress.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = TvTheme.PRIMARY
	_progress.add_theme_stylebox_override("fill", fill)
	column.add_child(_progress)
	update_task(task)

func update_task(value: Dictionary) -> void:
	task = value
	if not is_instance_valid(_name): return
	_name.text = str(task.get("name", "Download"))
	tooltip_text = _name.text
	var status := str(task.get("status", "waiting"))
	var total := int(task.get("total", 0))
	var received := int(task.get("received", 0))
	var label: String = {"active": "Downloading", "waiting": "Queued", "paused": "Paused", "complete": "Complete", "error": "Failed", "seeding": "Seeding", "cancelled": "Cancelled"}.get(status, status.capitalize())
	var parts := PackedStringArray([label, "Browser" if task.get("kind") == "browser" else ("Torrent" if task.get("kind") == "torrent" else ("Setup" if task.get("kind") == "setup" else "Link"))])
	if task.get("kind") == "setup": parts.append(str(task.get("error", "")))
	if total > 0: parts.append("%s / %s" % [String.humanize_size(received), String.humanize_size(total)])
	elif received > 0: parts.append(String.humanize_size(received))
	if int(task.get("speed", 0)) > 0:
		parts.append(String.humanize_size(int(task.speed)) + "/s")
		var seconds := int(maxi(0, total - received) / int(task.speed))
		if total > received: parts.append("%dm left" % maxi(1, int(ceil(seconds / 60.0))))
	if status == "seeding": parts.append("↑ " + String.humanize_size(int(task.get("upload_speed", 0))) + "/s")
	_detail.text = " · ".join(parts)
	_progress.value = 100.0 * received / total if total > 0 else 0
	_progress.visible = task.get("kind") != "setup"
