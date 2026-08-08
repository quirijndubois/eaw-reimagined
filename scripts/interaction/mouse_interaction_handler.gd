extends Node3D

@onready var selection_rect := $CanvasLayer/SelectionRectangle

const DRAG_THRESHOLD := 20

# Left-click drag (box selection)
var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO

# Right-click bezier path
var is_right_pressing: bool = false
var bezier_end: Vector3 = Vector3.ZERO      # right-click point = destination
var bezier_control: Vector3 = Vector3.ZERO  # drag point = bezier control handle

var path_curve_line: Line2D
var path_handle_line: Line2D


func _ready() -> void:
	path_curve_line = Line2D.new()
	path_curve_line.width = 2.0
	path_curve_line.default_color = Color(0.4, 1.0, 0.4, 0.85)
	path_curve_line.visible = false
	$CanvasLayer.add_child(path_curve_line)

	path_handle_line = Line2D.new()
	path_handle_line.width = 1.0
	path_handle_line.default_color = Color(1.0, 1.0, 0.4, 0.6)
	path_handle_line.visible = false
	$CanvasLayer.add_child(path_handle_line)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag(event.position)
			_direct_select(event)
		else:
			if is_dragging:
				_end_drag(event.position)

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_start_right_press(event.position)
		else:
			if is_right_pressing:
				_end_right_press(event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_dragging:
		_update_drag(event.position)
	if is_right_pressing:
		_update_right_press(event.position)


# --- Box Selection ---

func _start_drag(pos: Vector2) -> void:
	drag_start_position = pos
	is_dragging = true
	selection_rect.visible = false

func _update_drag(current_pos: Vector2) -> void:
	var drag_distance = (current_pos - drag_start_position).length()
	if not selection_rect.visible and drag_distance > DRAG_THRESHOLD:
		selection_rect.visible = true
	if selection_rect.visible:
		selection_rect.update_rect(drag_start_position, current_pos)

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
		var screen_pos: Vector2
		if ship is Ship:
			screen_pos = camera.unproject_position(ship.global_transform.origin)
		elif ship is StarfighterSquad:
			screen_pos = camera.unproject_position(ship.global_position)
		else:
			continue
		if rect.has_point(screen_pos):
			ship.set_selected(true)


# --- Bezier Path (right-click + drag) ---
#
# Right-click at destination, drag to pull the control handle, release to fly.
# Bezier: ship_position → drag_point (control) → right_click_point (destination)
# Right-clicking directly on an enemy ship issues an attack order for selected squads.

func _start_right_press(pos: Vector2) -> void:
	var selected = get_tree().get_nodes_in_group("Selected")
	if selected.is_empty():
		return

	# Detect right-clicked target — ship takes priority over squad
	var target_ship  := _raycast_for_ship(pos)
	var target_squad := _raycast_for_squad(pos) if not is_instance_valid(target_ship) else null
	var target: Node3D = target_ship if is_instance_valid(target_ship) else target_squad

	# Issue attack orders to all selected units that are enemies of the target
	if is_instance_valid(target):
		var issued := false
		for node in selected:
			if node.ally == target.ally:
				continue
			if node is StarfighterSquad and target is Ship:
				node.set_attack_target(target_ship)
				issued = true
			elif node is Ship:
				node.set_attack_target(target)
				issued = true
		if issued:
			return

	# Movement order
	bezier_end     = check_ground_hit(pos)
	bezier_control = bezier_end
	is_right_pressing = true
	_update_path_preview()

func _update_right_press(pos: Vector2) -> void:
	bezier_control = check_ground_hit(pos)
	_update_path_preview()

func _end_right_press(_pos: Vector2) -> void:
	is_right_pressing = false
	path_curve_line.visible = false
	path_handle_line.visible = false

	for node in get_tree().get_nodes_in_group("Selected"):
		if node is Ship or node is StarfighterSquad:
			node.set_bezier_path(bezier_control, bezier_end)

func _process(_delta: float) -> void:
	if is_right_pressing:
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	for node in get_tree().get_nodes_in_group("Selected"):
		if node is Ship and node.path_t >= 0.0:
			_draw_active_path(node, camera)
			return
	path_curve_line.visible = false
	path_handle_line.visible = false


func _draw_active_path(ship: Ship, camera: Camera3D) -> void:
	path_curve_line.clear_points()
	var steps := 24
	for i in range(steps + 1):
		var t := ship.path_t + float(i) / float(steps) * (1.0 - ship.path_t)
		var u := 1.0 - t
		var world_pos := u * u * ship.bezier_p0 + 2.0 * u * t * ship.bezier_p1 + t * t * ship.bezier_p2
		path_curve_line.add_point(camera.unproject_position(world_pos))
	path_curve_line.visible = true
	path_handle_line.visible = false


func _update_path_preview() -> void:
	var selected = get_tree().get_nodes_in_group("Selected")
	if selected.is_empty():
		return

	var camera = get_viewport().get_camera_3d()

	var center := Vector3.ZERO
	var count := 0
	for node in selected:
		if node is Ship or node is StarfighterSquad:
			center += node.global_position
			count  += 1
	if count == 0:
		return
	center /= float(count)

	var p0 := center
	var p1 := bezier_control
	var p2 := bezier_end

	path_curve_line.clear_points()
	for i in range(25):
		var t := float(i) / 24.0
		var u := 1.0 - t
		var world_pos := u * u * p0 + 2.0 * u * t * p1 + t * t * p2
		path_curve_line.add_point(camera.unproject_position(world_pos))
	path_curve_line.visible = true

	path_handle_line.clear_points()
	path_handle_line.add_point(camera.unproject_position(p2))
	path_handle_line.add_point(camera.unproject_position(p1))
	path_handle_line.visible = true


# --- Direct Click Selection ---

func _direct_select(event: InputEventMouseButton) -> void:
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(event.position)
	var to = from + camera.project_ray_normal(event.position) * 1000

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collision_mask     = 1 | 2   # layer 1 = ships, layer 2 = squad selection areas
	var result = get_world_3d().direct_space_state.intersect_ray(query)

	_deselect_all_if_needed()

	if result:
		var collider = result["collider"]
		# Area3D → direct parent is StarfighterSquad
		if collider is Area3D:
			var parent = collider.get_parent()
			if parent is StarfighterSquad:
				parent.set_selected(true)
				return
		# StaticBody3D → grandparent is Ship
		var grandparent = collider.get_parent().get_parent()
		if grandparent is Ship:
			grandparent.set_selected(true)
			return

	# Proximity fallback for squads (icon is small, area might miss at distance)
	for squad in get_tree().get_nodes_in_group("Squads"):
		if squad is StarfighterSquad:
			var sp := camera.unproject_position(squad.global_position)
			if sp.distance_to(event.position) < 32.0:
				squad.set_selected(true)
				return


# --- Utility ---

func _deselect_all_if_needed() -> void:
	if not Input.is_key_pressed(KEY_CTRL):
		for node in get_tree().get_nodes_in_group("Selected"):
			node.set_selected(false)


func _raycast_for_squad(pos: Vector2) -> StarfighterSquad:
	var camera = get_viewport().get_camera_3d()
	var from   = camera.project_ray_origin(pos)
	var to     = from + camera.project_ray_normal(pos) * 1000
	var query  = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collision_mask     = 2
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		var collider = result["collider"]
		if collider is Area3D:
			var parent = collider.get_parent()
			if parent is StarfighterSquad:
				return parent
	# Proximity fallback
	var camera2 = get_viewport().get_camera_3d()
	for squad in get_tree().get_nodes_in_group("Squads"):
		if squad is StarfighterSquad:
			if camera2.unproject_position(squad.global_position).distance_to(pos) < 32.0:
				return squad
	return null


func _raycast_for_ship(pos: Vector2) -> Ship:
	var camera = get_viewport().get_camera_3d()
	var from   = camera.project_ray_origin(pos)
	var to     = from + camera.project_ray_normal(pos) * 1000
	var query  = PhysicsRayQueryParameters3D.create(from, to)
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		var grandparent = result["collider"].get_parent().get_parent()
		if grandparent is Ship:
			return grandparent
	return null


func spawn_ship(ship_name: String, spawn_position: Vector3) -> Node3D:
	var scene_path = "res://prefabs/" + ship_name + ".tscn"
	var scene = load(scene_path)
	var instance = scene.instantiate()
	if instance is Node3D:
		instance.global_position = Vector3(spawn_position.x, randf_range(-0.6, 0.6), spawn_position.z)
		if spawn_position.z > 0:
			instance.ally = false
			instance.rotation.y = PI
		add_child(instance)
		return instance
	else:
		push_error("The instantiated scene is not of type Node3D.")
		return null


func check_ground_hit(mouse_position: Vector2) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(mouse_position)
	var direction = camera.project_ray_normal(mouse_position)

	var plane_normal = Vector3(0, 1, 0)
	var plane_point = Vector3(0, 0, 0)

	var denom = direction.dot(plane_normal)
	var t = (plane_point - from).dot(plane_normal) / denom
	return from + direction * t - position
