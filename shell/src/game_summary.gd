extends VBoxContainer

const TvTheme = preload("res://src/tv_theme.gd")

var _title: Label
var _facts: Label
var _description: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size.x = 1100
	add_theme_constant_override("separation", 8)
	_title = _label(TvTheme.SIZE_HERO_TITLE, 1)
	_facts = _label(TvTheme.SIZE_BODY, 2)
	_facts.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_description = _label(TvTheme.SIZE_BODY, 3)


func _label(font_size: int, lines: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func show_entry(entry: Dictionary) -> void:
	_title.text = str(entry.get("title", ""))
	var metadata: Dictionary = entry.get("metadata", {})
	var parts: PackedStringArray = []
	var release_date := str(metadata.get("release_date", ""))
	if not release_date.is_empty():
		parts.append(release_date)
	var genres: Array = metadata.get("genres", [])
	if not genres.is_empty():
		parts.append(", ".join(genres))
	var developers: Array = metadata.get("developers", [])
	if not developers.is_empty():
		parts.append(", ".join(developers))
	_facts.text = " · ".join(parts)
	var history: Dictionary = entry.get("play_history", {})
	if not history.is_empty():
		parts.append(PlayHistory.duration(float(history.get("total_seconds", 0))))
		_facts.text = " · ".join(parts)
	_facts.visible = not _facts.text.is_empty()
	_description.text = str(metadata.get("description", entry.get("subtitle", "")))
	_description.visible = not _description.text.is_empty()
