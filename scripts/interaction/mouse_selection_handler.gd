extends Node3D

@onready var selection_rect := $CanvasLayer/SelectionRectangle

const DRAG_THRESHOLD := 20

var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

# --- Input Handlers ---

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag(event.position)
			_direct_select(event)
		else:
			if is_dragging:
				_end_drag(event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not event.pressed:
			spawn_ship("ISD", check_ground_hit(event.position))

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not is_dragging:
		return

	var drag_distance = (event.position - drag_start_position).length()
	if not selection_rect.visible and drag_distance > DRAG_THRESHOLD:
		selection_rect.visible = true

	if selection_rect.visible:
		selection_rect.update_rect(drag_start_position, event.position)

# --- Drag Selection ---

func _start_drag(pos: Vector2) -> void:
	drag_start_position = pos
	is_dragging = true
	selection_rect.visible = false

func _end_drag(end_position: Vector2) -> void:
	is_dragging = false
	selection_rect.visible = false

	var drag_distance = (end_position - drag_start_position).length()
	if drag_distance > DRAG_THRESHOLD and selection_rect.size.length() > 10:
		_select_objects_in_rect()

func _select_objects_in_rect() -> void:
	_deselect_all_if_needed()

	var camera = get_viewport().get_camera_3d()
	var ships = get_tree().get_nodes_in_group("Ships")
	var rect = Rect2(selection_rect.position, selection_rect.size)

	for ship in ships:
		if ship is Ship:
			var screen_pos = camera.unproject_position(ship.global_transform.origin)
			if rect.has_point(screen_pos):
				ship.set_selected(true)

# --- Direct Selection (Raycast) ---

func _direct_select(event: InputEventMouseButton) -> void:
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(event.position)
	var to = from + camera.project_ray_normal(event.position) * 1000

	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = get_world_3d().direct_space_state.intersect_ray(query)

	_deselect_all_if_needed()

	if result:
		var collider = result["collider"]
		var parent = collider.get_parent().get_parent()
		if parent is Ship:
			parent.set_selected(true)

# --- Utility ---

func _deselect_all_if_needed() -> void:
	if not Input.is_key_pressed(KEY_CTRL):
		for node in get_tree().get_nodes_in_group("Selected"):
			if node is Ship and node.is_selected():
				node.set_selected(false)

func spawn_ship(ship_name: String, spawn_position: Vector3) -> Node3D:
	var scene_path = "res://prefabs/" + ship_name + ".tscn"

	var scene = load(scene_path)
	
	var instance = scene.instantiate()
	if instance is Node3D:
		instance.global_position = spawn_position

		if spawn_position.z > 0:
			instance.ally = false
			instance.rotation.y = PI

		add_child(instance)
		return instance
	else:
		push_error("The instantiated scene is not of type Node3D.")
		return null


func check_ground_hit(mouse_position: Vector2):

	var camera = get_viewport().get_camera_3d()

	var from = camera.project_ray_origin(mouse_position)
	var direction = camera.project_ray_normal(mouse_position)

	# Plane is Z = 0 → normal = Vector3(0, 0, 1)
	var plane_normal = Vector3(0, 1, 0)
	var plane_point = Vector3(0, 0, 0)

	var denom = direction.dot(plane_normal)

	var t = (plane_point - from).dot(plane_normal) / denom
	var hit_position = from + direction * t
	
	return hit_position - position
