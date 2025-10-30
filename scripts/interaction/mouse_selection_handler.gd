extends Node3D

@onready var selection_rect := $CanvasLayer/SelectionRectangle

const DRAG_THRESHOLD := 20

const path_sensitivity = 3

var is_dragging_left: bool = false
var is_dragging_right: bool = false
var drag_start_position_left: Vector2 = Vector2.ZERO
var drag_start_position_right: Vector2 = Vector2.ZERO

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
			if is_dragging_left:
				_end_drag(event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_start_drag_right(event.position)
		else:
			if is_dragging_right:
				_end_drag_right(event.position)
			else:
				# Regular right click (no drag)
				for ship in get_tree().get_nodes_in_group("Selected"):
					ship.set_heading(check_ground_hit(event.position))

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_dragging_left:
		var drag_distance = (event.position - drag_start_position_left).length()
		if not selection_rect.visible and drag_distance > DRAG_THRESHOLD:
			selection_rect.visible = true
		if selection_rect.visible:
			selection_rect.update_rect(drag_start_position_left, event.position)

	elif is_dragging_right:
		_dragging_right(event.position)

# --- Left Drag Selection ---

func _start_drag(pos: Vector2) -> void:
	drag_start_position_left = pos
	is_dragging_left = true
	selection_rect.visible = false

func _end_drag(end_position: Vector2) -> void:
	is_dragging_left = false
	selection_rect.visible = false

	var drag_distance = (end_position - drag_start_position_left).length()
	if drag_distance > DRAG_THRESHOLD and selection_rect.size.length() > 10:
		_select_objects_in_rect()

# --- Right Drag Behavior ---

func _start_drag_right(pos: Vector2) -> void:
	drag_start_position_right = pos
	is_dragging_right = true

func _dragging_right(pos: Vector2) -> void:
	var offset = check_ground_hit(pos) - check_ground_hit(drag_start_position_right)
	for ship in get_tree().get_nodes_in_group("Selected"):
		ship.display_heading(check_ground_hit(drag_start_position_right),offset*path_sensitivity)

func _end_drag_right(pos: Vector2) -> void:
	is_dragging_right = false
	var offset = check_ground_hit(pos) - check_ground_hit(drag_start_position_right)
	for ship in get_tree().get_nodes_in_group("Selected"):
		ship.set_heading(check_ground_hit(drag_start_position_right),offset*path_sensitivity)

# --- Selection Logic ---

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

	var plane_normal = Vector3(0, 1, 0)
	var plane_point = Vector3(0, 0, 0)

	var denom = direction.dot(plane_normal)
	var t = (plane_point - from).dot(plane_normal) / denom
	var hit_position = from + direction * t

	return hit_position - position
