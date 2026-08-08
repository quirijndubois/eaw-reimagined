class_name Boid
extends Node3D

const XWING_MESH      := preload("res://models/xwing/xwing.obj")
const EXPLOSION_SCENE := preload("res://prefabs/explosion.tscn")

# Set by StarfighterSquad._spawn_boids() — boids live at root level
var squad: StarfighterSquad = null
var ally:  bool = true

var velocity:     Vector3 = Vector3.ZERO
var _fwd:         Vector3 = Vector3.FORWARD  # aircraft forward axis (world space)
var _up:          Vector3 = Vector3.UP       # aircraft up axis — encodes roll state
var speed:        float   = 0.0
var _fire_cooldown: float = 0.0

var health: float = 3.0

const DETECT_RANGE := 18.0   # radius in which boids auto-engage enemies

# Attack run state machine: 0 = APPROACH (fly toward ship), 1 = RETREAT (bank away for next run)
var _attack_phase: int     = 0
var _phase_timer:  float   = 0.0
var _retreat_pt:   Vector3 = Vector3.ZERO
var _mesh_instance: MeshInstance3D
var _highlight_mat: StandardMaterial3D


func _ready() -> void:
	_fire_cooldown = randf_range(0.0, 0.5)
	_phase_timer   = randf_range(1.5, 5.0)
	_fwd = Vector3(randf_range(-1.0, 1.0), randf_range(-0.1, 0.1), randf_range(-1.0, 1.0)).normalized()
	_up  = (Vector3.UP - Vector3.UP.dot(_fwd) * _fwd).normalized()
	speed = squad.boid_max_speed if is_instance_valid(squad) else 1.5
	velocity = _fwd * speed

	var col := Color(0.35, 0.6, 1.0) if ally else Color(1.0, 0.3, 0.3)
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.albedo_color     = Color(col.r, col.g, col.b, 0.6)
	_highlight_mat.emission_enabled = true
	_highlight_mat.emission         = col
	_highlight_mat.emission_energy  = 6.0
	_highlight_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh     = XWING_MESH
	_mesh_instance.scale    = Vector3(0.008, 0.008, 0.008)
	_mesh_instance.rotation = Vector3(0.0, PI * 1.2, 0.0)
	add_child(_mesh_instance)

	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask  = 0
	area.monitorable     = true
	area.monitoring      = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.04
	cs.shape  = sp
	area.add_child(cs)
	add_child(area)


func deal_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		_die()


func set_highlighted(val: bool) -> void:
	if is_instance_valid(_mesh_instance):
		_mesh_instance.material_overlay = _highlight_mat if val else null


func _die() -> void:
	var exp := EXPLOSION_SCENE.instantiate()
	get_tree().get_root().add_child(exp)
	exp.global_position = global_position
	if is_instance_valid(squad):
		squad.boids.erase(self)
	queue_free()


func _process(delta: float) -> void:
	if not is_instance_valid(squad):
		return

	_fire_cooldown -= delta

	var max_speed  := squad.boid_max_speed
	var min_speed  := squad.boid_min_speed
	var turn_rate  := squad.boid_turn_rate
	var sep_r      := squad.boid_sep_radius
	var nbr_r      := squad.boid_nbr_radius

	var ship_target  := squad.attack_target
	var attacking    := is_instance_valid(ship_target)

	var boid_target: Boid = null
	if not attacking:
		boid_target = _find_nearest_enemy_boid()

	# ── Attack run state machine ──────────────────────────────────────────────
	var seek_pt     := Vector3.ZERO
	var in_approach := false

	if attacking:
		var dist_to_ship := global_position.distance_to(ship_target.global_position)

		if _attack_phase == 0:  # APPROACH — keep closing until a real close pass
			seek_pt     = ship_target.global_position
			in_approach = true
			if dist_to_ship < 0.6:
				_attack_phase = 1
				_phase_timer  = randf_range(2.5, 4.5)
				# Retreat point is ahead in the boid's current flight direction,
				# not reversed — this makes the boid fly through and arc back naturally
				# rather than snapping into a 180° turn.
				var fly_dir := _fwd
				var right   := fly_dir.cross(Vector3.UP)
				if right.length_squared() < 0.01:
					right = fly_dir.cross(Vector3.FORWARD)
				right = right.normalized()
				_retreat_pt = global_position \
						+ (fly_dir + right * randf_range(-0.4, 0.4)).normalized() * 3.0

		else:  # RETREAT — fly through, then arc back; timer as safety net
			_phase_timer -= delta
			seek_pt = _retreat_pt
			if dist_to_ship > 3.0 or _phase_timer <= 0.0:
				_attack_phase = 0

	elif boid_target != null:
		# Lead pursuit: aim where the target will be rather than where it is now.
		# Pure pursuit of a same-speed target causes symmetric orbits; leading breaks them.
		var dist_to_boid := global_position.distance_to(boid_target.global_position)
		var lead_time    := dist_to_boid / maxf(squad.boid_max_speed, 0.1)
		seek_pt     = boid_target.global_position + boid_target.velocity * lead_time
		in_approach = true  # suppress flocking — full focus on the intercept
	elif squad.has_waypoint:
		seek_pt = squad.waypoint
	else:
		seek_pt = squad.home_position

	# ── Neighbour scan ─────────────────────────────────────────────────────
	var sep_acc   := Vector3.ZERO
	var align_acc := Vector3.ZERO
	var coh_pos   := Vector3.ZERO
	var sep_n     := 0
	var nbr_n     := 0

	for other in squad.boids:
		if other == self or not is_instance_valid(other):
			continue
		var diff: Vector3 = global_position - other.global_position
		var d := diff.length()

		if d < sep_r and d > 0.001:
			sep_acc += diff.normalized() / d
			sep_n   += 1

		if d < nbr_r:
			align_acc += other.velocity
			coh_pos   += other.global_position
			nbr_n     += 1

	# ── Desired direction ──────────────────────────────────────────────────
	var desired   := Vector3.ZERO
	var to_goal   := seek_pt - global_position
	var dist_goal := to_goal.length()

	if in_approach:
		if dist_goal > 0.3:
			desired = to_goal.normalized() * squad.w_seek
	else:
		if sep_n > 0:
			desired += (sep_acc / float(sep_n)).normalized() * squad.w_sep
		if nbr_n > 0:
			desired += (align_acc / float(nbr_n)).normalized() * squad.w_align
			desired += ((coh_pos / float(nbr_n)) - global_position).normalized() * squad.w_cohesion
		if dist_goal > 0.3:
			desired += to_goal.normalized() * squad.w_seek

	# ── Hull avoidance — gradient repulsion that builds gradually from ~1.5 units out
	# so the boid curves smoothly rather than snapping when very close.
	if attacking:
		var rep := _scan_hull()
		if rep.length_squared() > 0.001:
			desired += rep * squad.w_seek * 5.0

	# ── Aircraft flight model: roll then pitch, no yaw ────────────────────────
	var desired_dir := desired.normalized() if desired.length_squared() > 0.001 else _fwd

	# Keep axes orthonormal
	var _right := _fwd.cross(_up)
	if _right.length_squared() < 0.001:
		_right = _fwd.cross(Vector3.RIGHT if abs(_fwd.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD)
	_right = _right.normalized()
	_up = _right.cross(_fwd).normalized()

	# ROLL — rotate _up around _fwd toward the lateral component of desired_dir.
	# This banks the ship so the target comes into the pitch plane.
	var lateral := desired_dir - desired_dir.dot(_fwd) * _fwd
	if lateral.length_squared() > 0.001:
		var target_up  := lateral.normalized()
		var roll_angle := _up.angle_to(target_up)
		if roll_angle > 0.001:
			var max_roll := squad.boid_roll_rate * delta
			var t        := minf(max_roll / roll_angle, 1.0)
			_up = _up.slerp(target_up, t).normalized()
		_right = _fwd.cross(_up).normalized()
		_up    = _right.cross(_fwd).normalized()

	# PITCH — pull the nose toward _up (only axis available after roll; no yaw).
	var pitch_input := desired_dir.dot(_up)
	_fwd = (_fwd + _up * pitch_input * turn_rate * delta).normalized()
	_right = _fwd.cross(_up)
	if _right.length_squared() < 0.001:
		_right = _fwd.cross(Vector3.RIGHT if abs(_fwd.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD)
	_right = _right.normalized()
	_up    = _right.cross(_fwd).normalized()

	# Gentle auto-level — drifts back to wings-level when not actively turning.
	var level_up := (Vector3.UP - Vector3.UP.dot(_fwd) * _fwd)
	if level_up.length_squared() > 0.001:
		_up    = _up.slerp(level_up.normalized(), 0.5 * delta).normalized()
		_right = _fwd.cross(_up).normalized()
		_up    = _right.cross(_fwd).normalized()

	# Speed — always at least min_speed, lerp toward max
	speed = maxf(lerpf(speed, max_speed, 0.5 * delta), min_speed)
	velocity = _fwd * speed
	velocity.y -= clampf(global_position.y, -1.5, 1.5) * 2.0 * delta
	# Re-extract _fwd from the corrected velocity so height correction feeds back into orientation
	if velocity.length_squared() > 0.001:
		speed = velocity.length()
		_fwd  = velocity / speed
	global_position += velocity * delta

	# Destroy boid only when fully inside hull (wall both ahead and behind = sandwiched)
	var hit_ship := _inside_hull()
	if hit_ship:
		hit_ship.deal_damage(3)
		_die()
		return

	# Orient using _fwd and _up directly — _up encodes roll, no extra rotate_object_local needed
	look_at(global_position + _fwd, _up)

	# ── Firing — raycast forward, shoot only when enemy geometry is ahead ──
	if _fire_cooldown <= 0.0:
		_try_fire_raycast()


# Returns the Ship the boid is fully inside (hull surface ahead AND behind),
# or null if the boid hasn't fully penetrated any hull.
func _inside_hull() -> Ship:
	var space := get_world_3d().direct_space_state
	var dir: Vector3 = velocity.normalized() if velocity.length_squared() > 0.01 else _fwd

	var fwd := PhysicsRayQueryParameters3D.create(
		global_position, global_position + dir * 0.15, 1)
	fwd.collide_with_areas = false
	var fwd_hit := space.intersect_ray(fwd)
	if not fwd_hit:
		return null

	var back := PhysicsRayQueryParameters3D.create(
		global_position, global_position - dir * 0.15, 1)
	back.collide_with_areas = false
	if not space.intersect_ray(back):
		return null

	# Resolve collider → Ship (StaticBody → MeshInstance → Ship)
	var body: Object = fwd_hit["collider"]
	var ship: Node   = body.get_parent().get_parent() if is_instance_valid(body) else null
	if ship is Ship and is_instance_valid(ship) and not ship._dying:
		return ship
	return null


# Casts rays against ship geometry (layer 1) with quadratic proximity falloff,
# so repulsion builds gradually from ~1.5 units out rather than snapping hard when close.
func _scan_hull() -> Vector3:
	const RAY_LEN := 1.5
	var space := get_world_3d().direct_space_state

	var right := _fwd.cross(_up)
	if right.length_squared() < 0.01:
		right = _fwd.cross(Vector3.FORWARD)
	right = right.normalized()

	var dirs := [
		_fwd,
		(_fwd + right * 0.7).normalized(),
		(_fwd - right * 0.7).normalized(),
	]

	var repulsion := Vector3.ZERO
	for dir: Vector3 in dirs:
		var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + dir * RAY_LEN, 1
		)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit:
			var t := 1.0 - global_position.distance_to(hit["position"]) / RAY_LEN
			repulsion += hit["normal"] * (t * t)  # quadratic — gentle far, strong near

	return repulsion


func _find_nearest_enemy_boid() -> Boid:
	var best: Boid = null
	var best_d     := DETECT_RANGE
	for sq in get_tree().get_nodes_in_group("Squads"):
		if not (sq is StarfighterSquad) or sq.ally == ally:
			continue
		for b in sq.boids:
			if not is_instance_valid(b):
				continue
			var d := global_position.distance_to(b.global_position)
			if d < best_d:
				best_d = d
				best   = b
	return best


# Fire at the best enemy boid in cone (aimed directly at them) or at capital ship geometry.
func _try_fire_raycast() -> void:
	# ── Boid targets: pick closest-to-center target in cone ───────────────────
	var best_boid: Boid = null
	var best_dot        := squad.boid_fire_dot
	for sq in get_tree().get_nodes_in_group("Squads"):
		if not (sq is StarfighterSquad) or sq.ally == ally:
			continue
		for b: Boid in sq.boids:
			if not is_instance_valid(b):
				continue
			var to_b := b.global_position - global_position
			var dist := to_b.length()
			if dist < 0.001 or dist > squad.boid_fire_range:
				continue
			var d := to_b.normalized().dot(_fwd)
			if d > best_dot:
				best_dot  = d
				best_boid = b

	if is_instance_valid(best_boid):
		var aim := (best_boid.global_position - global_position).normalized()
		_spawn_laser(aim)
		return

	# ── Capital ship targets: raycast against hull geometry ───────────────────
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + _fwd * squad.boid_fire_range, 1)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit:
		return
	var raw: Object = hit["collider"]
	var ship: Node  = raw.get_parent().get_parent()
	if not (ship is Ship and is_instance_valid(ship) and ship.ally != ally):
		return
	_spawn_laser(_fwd)


func _spawn_laser(dir: Vector3) -> void:
	var laser := DefaultLaser.new()
	laser.direction      = dir
	laser.emitter        = squad
	laser.color          = Color(0.35, 0.55, 1.0) if ally else Color(1.0, 0.45, 0.1)
	laser.speed          = 24.0
	laser.distance_range = squad.boid_fire_range
	laser.energy         = 1
	laser.brightness     = 8.0
	get_tree().get_root().add_child(laser)
	laser.global_position = global_position

	_fire_cooldown = squad.boid_fire_interval + randf_range(-0.05, 0.15)
