extends Control

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ConsoleButton = preload("res://src/console_button.gd")

var anchor_control: Control
var _panel: PanelContainer
var _slider: HSlider
var _value: Label
var _status: Label
var _mute: Button
var _timer: Timer
var _target := ""
var _queued_volume := -1
var _dismissed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	var box := TvTheme.card_art_box(TvTheme.SURFACE)
	box.set_content_margin_all(20)
	box.set_border_width_all(1)
	box.border_color = TvTheme.TEXT_SECONDARY.darkened(0.55)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 4)
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_mute = ConsoleButton.new()
	_mute.text = "Mute"
	_mute.glyph = "speaker"
	_mute.icon_only = true
	_mute.pressed.connect(_toggle_mute)
	row.add_child(_mute)
	var title := Label.new()
	title.text = "Volume"
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_value = Label.new()
	_value.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	row.add_child(_value)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = 100
	_slider.step = 1
	_slider.custom_minimum_size = Vector2(280, 44)
	_slider.accessibility_name = "Output volume"
	_slider.tooltip_text = "Volume · Left / right to adjust · Select to mute"
	for style in ["slider", "grabber_area", "grabber_area_highlight"]:
		var track := TvTheme.card_art_box(TvTheme.SURFACE_PRESSED if style == "slider" else TvTheme.PRIMARY)
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		_slider.add_theme_stylebox_override(style, track)
	_slider.add_theme_stylebox_override("focus", TvTheme.card_focus_ring())
	_slider.draw.connect(_draw_slider_focus)
	_slider.focus_entered.connect(_slider.queue_redraw)
	_slider.focus_exited.connect(_slider.queue_redraw)
	_slider.value_changed.connect(_volume_changed)
	column.add_child(_slider)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	TvTheme.wire_column([_mute, _slider])
	_mute.focus_next = _mute.get_path_to(_slider)
	_mute.focus_previous = _mute.focus_next
	_slider.focus_next = _slider.get_path_to(_mute)
	_slider.focus_previous = _slider.focus_next
	_timer = Timer.new()
	_timer.wait_time = 0.08
	_timer.one_shot = true
	_timer.timeout.connect(_send_volume)
	add_child(_timer)
	Audio.changed.connect(_refresh)
	resized.connect(_position_panel)
	anchor_control.item_rect_changed.connect(_position_panel.call_deferred)
	_panel.minimum_size_changed.connect(_position_panel.call_deferred)
	_refresh()
	_position_panel.call_deferred()
	_slider.grab_focus()


func _position_panel() -> void:
	if _dismissed:
		return
	if not is_instance_valid(anchor_control):
		closed.emit()
		return
	_panel.size = _panel.get_combined_minimum_size()
	var origin := anchor_control.get_global_rect()
	_panel.global_position = Vector2(
		clampf(origin.get_center().x - _panel.size.x / 2, 12, maxf(12, size.x - _panel.size.x - 12)),
		maxf(12, origin.position.y - _panel.size.y - 12))


func _refresh() -> void:
	var output := Audio.selected("output")
	var target := str(output.get("name", ""))
	if target != _target or not Audio.available or not Audio.error.is_empty():
		_queued_volume = -1
		_timer.stop()
	_target = target
	if _dismissed:
		_send_volume()
		if _queued_volume < 0:
			queue_free()
		return
	var enabled := Audio.available and not output.is_empty()
	_slider.editable = enabled
	_mute.disabled = not enabled or Audio.pending
	_mute.tooltip_text = "Unmute" if output.get("muted", false) else "Mute"
	_mute.accessibility_name = _mute.tooltip_text
	if _queued_volume < 0 and not Audio.pending:
		_slider.set_value_no_signal(int(output.get("volume", 0)))
	_update_value()
	_status.text = Audio.error
	if _status.text.is_empty():
		if not Audio.available:
			_status.text = "Audio unavailable"
		elif output.is_empty():
			_status.text = "No output device"
		elif output.get("muted", false):
			_status.text = "Muted"
	_status.visible = not _status.text.is_empty()
	if not Audio.pending and _queued_volume >= 0:
		_send_volume.call_deferred()


func _update_value() -> void:
	_value.text = "%d%%" % int(_slider.value)


func _draw_slider_focus() -> void:
	if _slider.has_focus():
		_slider.draw_style_box(TvTheme.card_focus_ring(), Rect2(Vector2.ZERO, _slider.size))


func _volume_changed(value: float) -> void:
	_queued_volume = roundi(value)
	_update_value()
	_timer.start()


func _send_volume() -> void:
	if _queued_volume < 0 or Audio.pending:
		return
	var output := Audio.selected("output")
	var volume := _queued_volume
	_queued_volume = -1
	if Audio.available and str(output.get("name", "")) == _target:
		Audio.request("output", "volume", output, volume)


func _toggle_mute() -> void:
	var output := Audio.selected("output")
	Audio.request("output", "mute", output, not bool(output.get("muted", false)))


## Finish the latest drag value after an outstanding acknowledgement, even
## when the user has already returned to the menu.
func dismiss() -> void:
	_dismissed = true
	hide()
	set_process_input(false)
	_timer.stop()
	if _queued_volume >= 0:
		reparent(get_tree().root)
		_send_volume()
	if _queued_volume < 0:
		queue_free()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		closed.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_shell_home"):
		get_viewport().set_input_as_handled()
		_send_volume()
		closed.emit()
	elif event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true):
		get_viewport().set_input_as_handled()
		if _slider.editable:
			_slider.value = clampf(_slider.value + (5 if event.is_action_pressed("ui_right", true) else -5), 0, 100)
	elif event.is_action_pressed("ui_accept") and _slider.has_focus():
		get_viewport().set_input_as_handled()
		_toggle_mute()
