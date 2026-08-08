@tool
class_name Turret
extends Node3D

@export var laser_color: Color

var cooldown := 0.0
var spread   := 0.02
var active   := false


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_gizmo()
		return
	add_to_group("Turrets")


func _build_gizmo() -> void:
	var im  := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color               = Color(1.0, 0.75, 0.0)
	mat.vertex_color_use_as_albedo = false
	mat.no_depth_test              = true

	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)

	# Arrow shaft along +Z
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3(0, 0, 0.8))

	# Arrow head
	for side in [Vector3(0.15, 0, 0), Vector3(-0.15, 0, 0), Vector3(0, 0.15, 0), Vector3(0, -0.15, 0)]:
		im.surface_add_vertex(Vector3(0, 0, 0.8))
		im.surface_add_vertex(Vector3(0, 0, 0.8) - Vector3(0, 0, 0.25) + side)

	# Hemisphere arc in XZ plane (flat semicircle)
	var segs := 24
	for i in segs:
		var a0 := -PI * 0.5 + PI * float(i)       / float(segs)
		var a1 := -PI * 0.5 + PI * float(i + 1)   / float(segs)
		im.surface_add_vertex(Vector3(sin(a0) * 0.6, 0.0, cos(a0) * 0.6))
		im.surface_add_vertex(Vector3(sin(a1) * 0.6, 0.0, cos(a1) * 0.6))

	# Two radii closing the arc
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3(-0.6, 0.0, 0.0))
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3( 0.6, 0.0, 0.0))

	im.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh         = im
	mi.cast_shadow  = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	cooldown -= delta
	if not active or cooldown > 0.0:
		return
	var target := _find_target()
	if target:
		_shoot(global_position, _hull_point(target))
		cooldown = 0.55


func _find_target() -> Node3D:
	var ship := get_parent() as Ship
	if not ship:
		return null

	var ship_fwd := Vector3(sin(ship.angle), 0.0, cos(ship.angle))

	# If the ship has a designated combat target, only fire at that target.
	if is_instance_valid(ship.combat_target):
		var ct    := ship.combat_target
		var to_ct := ct.global_position - global_position
		var dist  := to_ct.length()
		if dist <= ship.fire_range and to_ct.normalized().dot(ship_fwd) >= 0.7:
			return ct
		return null

	# No combat target — pick the nearest enemy in the forward cone.
	var best: Node3D = null
	var best_dist    := INF
	for enemy: Node3D in ship.get_enemies():
		if not is_instance_valid(enemy):
			continue
		var to_enemy := enemy.global_position - global_position
		var dist     := to_enemy.length()
		if dist > ship.fire_range:
			continue
		if to_enemy.normalized().dot(ship_fwd) < 0.7:
			continue
		if dist < best_dist:
			best_dist = dist
			best      = enemy
	return best


# Returns a random point on the target's hull rather than its centre.
func _hull_point(target: Node3D) -> Vector3:
	if target is Ship and is_instance_valid(target.mesh_instance) \
			and target.mesh_instance.mesh != null:
		var aabb: AABB = target.mesh_instance.mesh.get_aabb()
		var center := aabb.get_center()
		# 60% of the half-extents keeps sampled points well inside the hull
		var half   := aabb.size * 0.3
		var local_pt := center + Vector3(
			randf_range(-half.x, half.x),
			randf_range(-half.y, half.y),
			randf_range(-half.z, half.z)
		)
		return target.mesh_instance.global_transform * local_pt

	if target is StarfighterSquad and not target.boids.is_empty():
		var b: Boid = target.boids[randi() % target.boids.size()]
		if is_instance_valid(b):
			return b.global_position

	return target.global_position


func _shoot(from: Vector3, to: Vector3) -> void:
	var laser     := DefaultLaser.new()
	var jitter    := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	laser.direction = (to - from).normalized() + jitter * spread
	laser.emitter   = get_parent()
	laser.color     = laser_color
	get_tree().get_root().add_child(laser)
	laser.global_position = from
