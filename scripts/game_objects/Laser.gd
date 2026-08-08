class_name DefaultLaser
extends Node3D

const EXPLOSION_SCENE  := preload("res://prefabs/explosion.tscn")
const SHIELD_HIT_SCENE := preload("res://prefabs/shield_hit.tscn")

static var _sphere_mesh: SphereMesh
static var _mat_cache: Dictionary = {}
static var _explosion_counts: Dictionary = {}
static var _explosion_last:   Dictionary = {}
static var _shield_counts:    Dictionary = {}
static var _shield_last:      Dictionary = {}
const MAX_SIMULTANEOUS      := 6
const EXPLOSION_INTERVAL_MS := 300
const SHIELD_INTERVAL_MS    := 80

var energy: int = 1
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
	_add_travel_light()


func _add_travel_light() -> void:
	var l := OmniLight3D.new()
	l.light_color      = color
	l.light_energy     = 0.008
	l.omni_range       = 3.0
	l.omni_attenuation = 2.0
	l.shadow_enabled   = false
	add_child(l)


func _process(delta: float) -> void:
	var step := speed * delta
	global_position += direction * step
	distance_traveled += step
	look_at(global_position + direction, Vector3.UP)

	var hit := check_collision(step)
	if not hit.is_empty():
		var collider = hit["collider"]
		if collider is Boid:
			# Explosion parented to root so it outlives the boid
			var e := EXPLOSION_SCENE.instantiate()
			get_tree().get_root().add_child(e)
			e.global_position = global_position
			die()
			collider.deal_damage(energy)
		elif collider is Ship and collider.shield_health > 0:
			_spawn_shield_hit(collider, hit["normal"])
			die()
			collider.deal_damage(energy)
		else:
			_spawn_explosion(collider)
			die()
			collider.deal_damage(energy)
	elif distance_traveled > distance_range:
		die()


func check_collision(step: float = 0.1) -> Dictionary:
	var half  := maxf(step * 0.5, 0.05)
	var from  := global_position + direction * half
	var to    := global_position - direction * half
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collision_mask     = 1 | 4
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result:
		return {}
	var raw: Object = result["collider"]
	if not is_instance_valid(emitter):
		return {}

	# Boid hit — Area3D whose parent is a Boid
	if raw is Area3D:
		var boid: Node = raw.get_parent()
		if boid is Boid and is_instance_valid(boid) and boid.ally != emitter.ally:
			return {"collider": boid, "normal": result["normal"]}
		return {}

	# Ship hit — StaticBody3D → MeshInstance3D → Ship
	var ship: Node = raw.get_parent().get_parent()
	if is_instance_valid(ship) and ship is Ship \
			and ship != emitter and ship.ally != emitter.ally:
		return {"collider": ship, "normal": result["normal"]}
	return {}


func die() -> void:
	queue_free()


func _spawn_explosion(collider: Object) -> void:
	var id  := collider.get_instance_id()
	var now := Time.get_ticks_msec()
	if _explosion_counts.get(id, 0) >= MAX_SIMULTANEOUS:
		return
	if now - _explosion_last.get(id, 0) < EXPLOSION_INTERVAL_MS:
		return
	_explosion_last[id] = now
	var e := EXPLOSION_SCENE.instantiate()
	collider.add_child(e)
	e.global_position = global_position
	_explosion_counts[id] = _explosion_counts.get(id, 0) + 1
	e.tree_exiting.connect(func() -> void:
		_explosion_counts[id] = max(0, _explosion_counts.get(id, 0) - 1)
	)


func _spawn_shield_hit(ship: Ship, surface_normal: Vector3) -> void:
	var id  := ship.get_instance_id()
	var now := Time.get_ticks_msec()
	if _shield_counts.get(id, 0) >= MAX_SIMULTANEOUS:
		return
	if now - _shield_last.get(id, 0) < SHIELD_INTERVAL_MS:
		return
	_shield_last[id] = now
	var h := SHIELD_HIT_SCENE.instantiate()
	ship.add_child(h)
	h.setup(global_position, surface_normal)
	_shield_counts[id] = _shield_counts.get(id, 0) + 1
	h.tree_exiting.connect(func() -> void:
		_shield_counts[id] = max(0, _shield_counts.get(id, 0) - 1)
	)


func add_colored_sphere() -> void:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
	var key := color.to_html(false)
	if not _mat_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color      = color
		mat.emission_enabled  = true
		mat.emission          = color
		mat.emission_energy   = brightness
		_mat_cache[key] = mat
	var mi := MeshInstance3D.new()
	mi.mesh              = _sphere_mesh
	mi.material_override = _mat_cache[key]
	mi.scale             = size
	add_child(mi)
