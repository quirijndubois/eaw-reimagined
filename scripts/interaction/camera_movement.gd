extends Node3D

@onready var camera = $Camera3D

var dragging := false
var drag_start_position := Vector3.ZERO
var object_start_position := Vector3.ZERO

func _unhandled_input(event):
	handle_panning_event(event)
	handle_zoom_event(event)
	handle_rotate_event(event)

const zoom_speed = 1e-1

func handle_zoom_event(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.position[2] *= (1 - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.position[2] *= (1 + zoom_speed)
	elif event is InputEventMagnifyGesture:
		camera.position[2] *= 1 + (1 - event.factor) / 3


@onready var rotating = false
@onready var last_mouse_position = Vector2.ZERO
@onready var rotation_sensitivity = 0.004  # Adjust to control rotation speed
func handle_rotate_event(event):

	if event is InputEventPanGesture:
		if Input.is_key_pressed(KEY_SHIFT):
			rotate_y(event.delta.x / 30)
			rotate_object_local(Vector3.RIGHT, event.delta.y / 30)
		else:
			var delta_vector= Vector3(event.delta.x,0,event.delta.y)
			delta_vector = delta_vector.rotated(Vector3.UP, rotation.y)
			position += delta_vector / 10

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and Input.is_key_pressed(KEY_SHIFT):
				rotating = true
				last_mouse_position = event.position
			else:
				rotating = false

	elif event is InputEventMouseMotion and rotating:
		var delta = event.position - last_mouse_position
		last_mouse_position = event.position

		# Horizontal mouse movement rotates around the Y axis (yaw)
		rotate_y(-delta.x * rotation_sensitivity)

		# Optional: Vertical mouse movement rotates around the local X axis (pitch)
		rotate_object_local(Vector3.RIGHT, -delta.y * rotation_sensitivity)


func handle_panning_event(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and not Input.is_key_pressed(KEY_SHIFT):
				var hit_position = check_ground_hit(event.position)
				if hit_position:
					dragging = true
					drag_start_position = hit_position
					object_start_position = position
			else:
				dragging = false

	elif event is InputEventMouseMotion and dragging:
		var current_hit = check_ground_hit(event.position)
		if current_hit:
			var offset = current_hit - drag_start_position
			position = object_start_position - offset

func check_ground_hit(mouse_position: Vector2):
	var from = camera.project_ray_origin(mouse_position)
	var direction = camera.project_ray_normal(mouse_position)

	# Plane is Z = 0 → normal = Vector3(0, 0, 1)
	var plane_normal = Vector3(0, 1, 0)
	var plane_point = Vector3(0, 0, 0)

	var denom = direction.dot(plane_normal)

	var t = (plane_point - from).dot(plane_normal) / denom
	var hit_position = from + direction * t
	
	return hit_position - position

@onready var mouse_pos = Vector2(0,0)
