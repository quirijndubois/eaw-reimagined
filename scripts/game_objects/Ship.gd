class_name Ship
extends Node3D

@onready var shield_health_bar = $Sprite3D/SubViewport/shieldHealth
@onready var hull_health_bar = $Sprite3D/SubViewport/hullHealth
@onready var ship_name_label = $Sprite3D/SubViewport/Panel/Label
@onready var ship_name_panel = $Sprite3D/SubViewport/Panel

@export var mesh_instance: MeshInstance3D

@export var ship_name: String
@export var hull_strength: int
@export var shield_strength: int
@export var hull_health: int
@export var shield_health: int
@export var ally: bool

@export var selected: bool

@export var max_speed: float = 1
@export var acceleration: float = 1

@export var max_rotation_speed: float = 5
@export var rotation_acceleration: float = .5

var selection_circle_instance: MeshInstance3D
var visible_material: StandardMaterial3D
var invisible_material: StandardMaterial3D

var path_instance: MeshInstance3D
var visible_material_path: StandardMaterial3D
var invisible_material_path: StandardMaterial3D

var angle = 0
var tilt = 0
var direction = Vector3.ZERO

# heading is a cubic bezier curve, with from, control 1, control 2, to, t, length
@onready var current_heading = [position, position, position, position]
var current_heading_length = 0
var current_heading_t = 0

func _ready() -> void:

	angle = rotation.y

	create_collision_shape()
	create_selection_circle()
	set_selected(selected)
	set_bars()

	add_to_group("Ships")
	if ally:
		add_to_group("Allies")
	else:
		add_to_group("Enemies")

func _process(delta: float) -> void:
	if path_instance:
		path_instance.global_position = Vector3.ZERO
		path_instance.global_rotation = Vector3.ZERO

	if current_heading_length > 0:
		var cubic_derivative = cubic_bezier_derivative(current_heading[0], current_heading[1], current_heading[2], current_heading[3], current_heading_t)
		var cubic_derivative_length = cubic_derivative.length()
		direction = cubic_derivative
		angle = atan2(direction.x, direction.z)

		var cubic_curvature = cubic_bezier_curvature(current_heading[0], current_heading[1], current_heading[2], current_heading[3], current_heading_t)
		# tilt = -clamp(log(1+cubic_curvature), -.5, .5)

		print(rotation)

		if current_heading_t < 1:
			var current_speed = clamp(1/abs(cubic_curvature), 0, max_speed)
			current_heading_t += delta / cubic_derivative_length * current_speed
		else:
			current_heading_t = 1

	position = cubic_bezier(current_heading[0], current_heading[1], current_heading[2], current_heading[3], current_heading_t)

	_handle_weapons()
	_set_rotation()
	_set_direction()

func deal_damage(damage: int) -> void:
	if shield_health > 0:
		shield_health -= damage
	elif hull_health > 0:
		shield_health = 0
		hull_health -= damage
	else:	
		die()
	
	set_bars()


func die():
	queue_free()

func create_collision_shape() -> void:
	# Create StaticBody3D as parent node
	var static_body = StaticBody3D.new()
	static_body.name = "StaticBody"
	
	# Create collision shape node
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	
	# Create shape based on the mesh
	if mesh_instance.mesh:
		var shape = mesh_instance.mesh.create_trimesh_shape()
		collision_shape.shape = shape
		
		# Build the proper hierarchy
		static_body.add_child(collision_shape)
		mesh_instance.add_child(static_body)
		
		# Important: The static body needs to be owned by the scene
		if mesh_instance.owner:
			static_body.owner = mesh_instance.owner
			collision_shape.owner = mesh_instance.owner
	else:
		push_warning("MeshInstance has no mesh assigned for collision creation")
		static_body.free()

func create_selection_circle():
	# Create materials
	visible_material = StandardMaterial3D.new()
	visible_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if ally:
		visible_material.albedo_color = Color(0, 0, 1) # Blue
	else:
		visible_material.albedo_color = Color(1, 0, 0) # Red

	visible_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	invisible_material = visible_material.duplicate()
	invisible_material.albedo_color.a = 0.0 # Fully transparent

	# Create circle mesh
	var circle_mesh := ImmediateMesh.new()
	var radius: float = 1.5
	var segments: int = 64
	circle_mesh.clear_surfaces()
	circle_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, visible_material)

	for i in range(segments + 1):
		var ang = TAU * i / float(segments)
		var x = radius * cos(ang)
		var z = radius * sin(ang)
		circle_mesh.surface_add_vertex(Vector3(x, 0.01, z))

	circle_mesh.surface_end()

	# Create mesh instance
	selection_circle_instance = MeshInstance3D.new()
	selection_circle_instance.mesh = circle_mesh
	add_child(selection_circle_instance)

func create_path(start_position: Vector3, handle1: Vector3, handle2: Vector3,  end_position: Vector3, color: Color) -> void:
	visible_material_path = StandardMaterial3D.new()
	visible_material_path.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	visible_material_path.albedo_color = color

	visible_material_path.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	invisible_material_path = visible_material_path.duplicate()

	# Create circle mesh
	var path_mesh := ImmediateMesh.new()
	var segments: int = 64
	path_mesh.clear_surfaces()
	path_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, visible_material_path)

	for i in range(segments + 1):
		path_mesh.surface_add_vertex(cubic_bezier(start_position, handle1, handle2, end_position, i / float(segments)))

	path_mesh.surface_end()

	# Create mesh instance
	path_instance = MeshInstance3D.new()
	path_instance.mesh = path_mesh
	add_child(path_instance)

func display_heading(target_position: Vector3, approach_vector: Vector3) -> void:
	if path_instance:
		remove_child(path_instance)
	
	var approach_magnitude = max(2,approach_vector.length())

	var a = global_position
	var b = global_position + direction*approach_magnitude 
	var c = target_position - approach_vector
	var d = target_position

	create_path(a,b,c,d, Color.BLUE)

func set_heading(target_position: Vector3, approach_vector: Vector3):
	if path_instance:
		remove_child(path_instance)
	
	var approach_magnitude = max(2,approach_vector.length())

	var a = global_position
	var b = global_position + direction*approach_magnitude 
	var c = target_position - approach_vector
	var d = target_position

	current_heading = [a, b, c, d]
	current_heading_t = 0
	current_heading_length = cubic_bezier_length(a, b, c, d)

	create_path(a,b,c,d, Color.RED)


func set_selected(value: bool) -> void:
	selected = value

	set_bars()

	if selected:
		add_to_group("Selected")
		remove_from_group("Unselected")
	else:
		add_to_group("Unselected")
		remove_from_group("Selected")
	
	if selection_circle_instance:
		var circle_mesh := selection_circle_instance.mesh as ImmediateMesh
		if circle_mesh:
			circle_mesh.surface_set_material(0, visible_material if selected else invisible_material)

func is_selected() -> bool:
	return selected

func get_enemies() -> Array:
	if ally:
		return get_tree().get_nodes_in_group("Enemies")
	else:
		return get_tree().get_nodes_in_group("Allies")

func get_closest(ships) -> Node3D:
	var closest_ship = null
	var closest_distance = 1e10
	for ship in ships:
		var distance = global_position.distance_to(ship.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_ship = ship
	return closest_ship

func _handle_weapons() -> void:
	var enemies = get_enemies()

	var closest_enemy = get_closest(enemies)


	var turrets = get_tree().get_nodes_in_group("Turrets")
	for turret in turrets:

		if turret.get_parent() == self and closest_enemy:
			turret.active = true
			turret.target = closest_enemy.global_position

		if not closest_enemy:
			turret.active = false


func _set_rotation() -> void:
	rotation = Vector3(0, angle, tilt)

func _set_direction() -> void:
	direction = Vector3(sin(angle), 0, cos(angle)) 
	direction = direction.normalized()

func set_bars():

	shield_health_bar.modulate = Color(.5, .5, 1)
	hull_health_bar.modulate = Color(.3, 1, .3)

	if not selected:
		shield_health_bar.modulate.a = 0
		hull_health_bar.modulate.a = 0
		ship_name_panel.modulate.a = 0
	else:
		shield_health_bar.modulate.a = 1
		hull_health_bar.modulate.a = 1
		ship_name_panel.modulate.a = 1

	ship_name_label.text = ship_name

	shield_health_bar.max_value = shield_strength
	hull_health_bar.max_value = hull_strength
 
	shield_health_bar.value = shield_health
	hull_health_bar.value = hull_health


func cubic_bezier(a,b,c,d,t):
	return pow(1-t,3)*a + 3*t*pow(1-t,2)*b + 3*t*t*(1-t)*c + pow(t,3)*d

func cubic_bezier_derivative(a,b,c,d,t):
	return 3*pow(1-t,2)*(b-a) + 6*t*(1-t)*(c-b) + 3*pow(t,2)*(d-c)

func cubic_bezier_second_derivative(a,b,c,d,t):
	return 6*(1-t)*(c-2*b+a) + 6*t*(d-2*c+b)


func cubic_bezier_curvature(a, b, c, d, t) -> float:
	var d1 = cubic_bezier_derivative(a, b, c, d, t)
	var d2 = cubic_bezier_second_derivative(a, b, c, d, t)

	var cross = d1.cross(d2)
	var numerator = cross.length()
	var denominator = pow(d1.length(), 3)

	if denominator == 0.0:
		return 0.0  # Degenerate or flat

	# Use sign of the y-component of the cross product (since we're in x,z plane)
	var _sign = signf(cross.y)

	return _sign * (numerator / denominator)



func cubic_bezier_length(a: Vector3, b: Vector3, c: Vector3, d: Vector3, segments := 100) -> float:
	var length = 0.0
	var prev_point = a

	for i in range(1, segments + 1):
		var t = float(i) / segments
		var point = cubic_bezier(a, b, c, d, t)
		length += prev_point.distance_to(point)
		prev_point = point

	return length
