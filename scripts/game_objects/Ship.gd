class_name Ship
extends Node3D

@export var mesh_instance: MeshInstance3D

@export var ship_name: String
@export var hull_strength: int
@export var laser_color: Color
@export var shield_strength: int
@export var hull_health: int
@export var shield_health: int
@export var ally: bool

@export var selected: bool

var selection_circle_instance: MeshInstance3D
var visible_material: StandardMaterial3D
var invisible_material: StandardMaterial3D

func _ready() -> void:
	create_collision_shape()
	create_selection_circle()
	set_selected(selected)

	add_to_group("Ships")
	if ally:
		add_to_group("Allies")
	else:
		add_to_group("Enemies")


func deal_damage(damage: int) -> void:
	if shield_health > 0:
		shield_health -= damage
	elif hull_health > 0:
		shield_health = 0
		hull_health -= damage
	else:
		die()

func die() -> void:
	pass


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
		var angle = TAU * i / float(segments)
		var x = radius * cos(angle)
		var z = radius * sin(angle)
		circle_mesh.surface_add_vertex(Vector3(x, 0.01, z))

	circle_mesh.surface_end()

	# Create mesh instance
	selection_circle_instance = MeshInstance3D.new()
	selection_circle_instance.mesh = circle_mesh
	add_child(selection_circle_instance)

func set_selected(value: bool) -> void:
	if value:
		add_to_group("Selected")
		remove_from_group("Unselected")
	else:
		add_to_group("Unselected")
		remove_from_group("Selected")
	
	selected = value
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

func _process(delta: float) -> void:
	var enemies = get_enemies()

	var closest_enemy = get_closest(enemies)


	var turrets = get_tree().get_nodes_in_group("Turrets")
	for turret in turrets:

		if turret.get_parent() == self and closest_enemy:
			turret.active = true
			turret.target = closest_enemy.global_position

		if not closest_enemy:
			turret.active = false
