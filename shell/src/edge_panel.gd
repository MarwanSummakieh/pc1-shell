extends PanelContainer

## Full-height, edge-attached menu shared by game, file and application actions.
const TvTheme = preload("res://src/tv_theme.gd")

func _ready() -> void:
	var box := TvTheme.card_idle_box()
	box.set_corner_radius_all(0)
	add_theme_stylebox_override("panel", box)
	get_viewport().size_changed.connect(_fit)
	if get_parent() is Control:
		get_parent().resized.connect(_fit)
	_fit()

func _fit() -> void:
	var viewport: Vector2 = get_parent().size if get_parent() is Control else get_viewport_rect().size
	var bounds := TvTheme.sidebar_bounds(viewport)
	position = bounds.position
	size = bounds.size
