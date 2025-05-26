class_name DefaultLaser

extends Node3D

var energy: int = 10

var brightness: float = 10
var direction: Vector3 = Vector3.LEFT
var speed: float = 10
var color: Color = Color(.5, 1, .5)
var size: Vector3 = Vector3(1e-2, 1e-2, 4e-1)
var distance_range: int = 50

var distance_traveled: float = 0
var emitter = null

func _ready() -> void:
	direction = direction.normalized()
	add_colored_sphere()

func _process(delta: float):
	update(delta)

func update(delta):
	
	global_position += direction * speed * delta

	distance_traveled += speed * delta

	look_at(global_position + direction, Vector3.UP)
	
	var collision = check_collision()
	if collision:
		die()
		collision.deal_damage(energy)
	elif distance_traveled > distance_range:
		die()
	
func check_collision():
	var from = global_position + direction * 0.1
	var to = global_position - direction * 0.1

	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = get_world_3d().direct_space_state.intersect_ray(query)

	if result:
		var collider = result["collider"].get_parent().get_parent()
		if collider != emitter:
			return collider
	return null

func die():
	queue_free()

func add_colored_sphere():
	var mesh_instance = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	mesh_instance.mesh = sphere_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	
	# Enable emission and set the emissive color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = brightness

	mesh_instance.material_override = material
	
	# Stretch the sphere — for example, making it tall and thin
	mesh_instance.scale = size

	add_child(mesh_instance)
