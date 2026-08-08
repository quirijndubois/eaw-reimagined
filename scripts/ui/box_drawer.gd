extends ColorRect

static var _style: StyleBoxFlat


func _ready() -> void:
	visible = false
	color = Color(0, 0, 0, 0)  # suppress default ColorRect fill

	if not _style:
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.62, 0.62, 0.64, 0.09)
		_style.set_corner_radius_all(5)
		_style.set_border_width_all(1)
		_style.border_color = Color(0.78, 0.78, 0.80, 0.85)


func _draw() -> void:
	_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))


func update_rect(start_pos: Vector2, current_pos: Vector2) -> void:
	position = Vector2(min(start_pos.x, current_pos.x), min(start_pos.y, current_pos.y))
	size     = Vector2(abs(current_pos.x - start_pos.x), abs(current_pos.y - start_pos.y))
	queue_redraw()
