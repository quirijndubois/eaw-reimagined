extends ColorRect

func _ready():
	visible = false
	color = Color(0.5, 0.8, 1.0, 0.3)

func update_rect(start_pos: Vector2, current_pos: Vector2) -> void:
	var rect_position = Vector2(
		min(start_pos.x, current_pos.x),
		min(start_pos.y, current_pos.y)
	)
	var rect_size = Vector2(
		abs(current_pos.x - start_pos.x),
		abs(current_pos.y - start_pos.y)
	)
	position = rect_position
	size = rect_size