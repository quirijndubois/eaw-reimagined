class_name StarfighterSquad
extends Node3D

const BOID_SCENE := preload("res://prefabs/boid.tscn")
const SQUAD_SIZE := 10

## Which side this squadron belongs to. Enemy squads (ally=false) face the opposite direction on spawn.
@export var ally: bool = true

# ── Boid tuning (editable per prefab) ──────────────────────────────────────
@export_group("Boid Movement")
## Maximum flight speed in units/sec.
@export var boid_max_speed:  float = 1.5
## Minimum speed — boids never fully stop so they can always steer.
@export var boid_min_speed:  float = 1.5
## How quickly boids can change direction (slerp blend rate per second). Higher = snappier turns.
@export var boid_turn_rate:  float = 0.1
## Maximum roll speed in radians/sec. Limits how fast fighters bank into a turn.
@export var boid_roll_rate:  float = 1.2

@export_group("Boid Flocking")
## Radius within which a boid pushes away from its neighbours (personal space).
@export var boid_sep_radius: float = 0.0
## Radius within which a boid matches neighbours' heading and position (flock radius).
@export var boid_nbr_radius: float = 0.5
## Weight of the separation force (keeps boids from colliding with each other).
@export var w_sep:           float = 0.0
## Weight of the alignment force (boids try to fly in the same direction as neighbours).
@export var w_align:         float = 0.0
## Weight of the cohesion force (boids drift toward the group centre).
@export var w_cohesion:      float = 0.0
## Weight of the goal-seeking force (toward waypoint, attack target, or enemy boid).
@export var w_seek:          float = 5.0

@export_group("Boid Combat")
## Maximum distance (units) at which a boid can fire at a target.
@export var boid_fire_range:    float = 12.0
## Minimum dot product between facing direction and target direction required to fire.
## 1.0 = must face exactly, 0.0 = can fire in any direction. Lower = wider firing cone.
@export var boid_fire_dot:      float = 0.55
## Seconds between shots per boid (plus small random jitter).
@export var boid_fire_interval: float = 0.50

# ── State ──────────────────────────────────────────────────────────────────
var selected:      bool  = false
var attack_target: Ship  = null

# Waypoint boids fly toward (set via right-click move order)
var waypoint:     Vector3 = Vector3.ZERO
var has_waypoint: bool    = false
var home_position: Vector3 = Vector3.ZERO

var boids: Array = []
var _boids_spawned := false

var _icon:          MeshInstance3D
var _icon_mesh:     ImmediateMesh
var _icon_fill_mat: StandardMaterial3D
var _icon_ring_mat: StandardMaterial3D
var _icon_sel_mat:  StandardMaterial3D
var _last_boid_count: int = -1


func _ready() -> void:
	add_to_group("Ships")
	add_to_group("Squads")
	if ally:
		add_to_group("Allies")
	else:
		add_to_group("Enemies")

	_spawn_boids()
	home_position = global_position
	_create_icon()
	set_selected(false)
	attack_target = _find_nearest_enemy_ship()


func _spawn_boids() -> void:
	# Boids live at root level so the squad's position can be derived from them
	# without creating a feedback loop.
	var root := get_tree().get_root()
	for i in SQUAD_SIZE:
		var b := BOID_SCENE.instantiate() as Boid
		b.ally  = ally
		b.squad = self
		root.add_child(b)
		b.global_position = global_position + Vector3(
			randf_range(-1.5, 1.5),
			randf_range(-0.4, 0.4),
			randf_range(-1.5, 1.5)
		)
		boids.append(b)
	_boids_spawned = true


func _exit_tree() -> void:
	for b in boids:
		if is_instance_valid(b):
			b.queue_free()


func _create_icon() -> void:
	var col := Color(0.45, 0.70, 1.0) if ally else Color(1.0, 0.40, 0.40)

	# Bright fill — alive sector
	_icon_fill_mat = StandardMaterial3D.new()
	_icon_fill_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icon_fill_mat.albedo_color     = Color(col.r, col.g, col.b, 0.90)
	_icon_fill_mat.emission_enabled = true
	_icon_fill_mat.emission         = col
	_icon_fill_mat.emission_energy  = 2.5
	_icon_fill_mat.billboard_mode   = BaseMaterial3D.BILLBOARD_ENABLED
	_icon_fill_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	_icon_fill_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED

	# Dim ring — full diamond background + empty-sector fill
	_icon_ring_mat = StandardMaterial3D.new()
	_icon_ring_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icon_ring_mat.albedo_color   = Color(col.r, col.g, col.b, 0.25)
	_icon_ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_icon_ring_mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	_icon_ring_mat.cull_mode      = BaseMaterial3D.CULL_DISABLED

	# Selection outline — brighter, slightly larger diamond drawn only when selected
	_icon_sel_mat = StandardMaterial3D.new()
	_icon_sel_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icon_sel_mat.albedo_color     = Color(col.r, col.g, col.b, 1.0)
	_icon_sel_mat.emission_enabled = true
	_icon_sel_mat.emission         = col
	_icon_sel_mat.emission_energy  = 5.0
	_icon_sel_mat.billboard_mode   = BaseMaterial3D.BILLBOARD_ENABLED
	_icon_sel_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	_icon_sel_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED

	_icon_mesh = ImmediateMesh.new()
	_icon = MeshInstance3D.new()
	_icon.mesh        = _icon_mesh
	_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_icon.position    = Vector3(0.0, 0.25, 0.0)
	add_child(_icon)
	_icon.add_to_group("HUD")

	# Area3D for click selection — layer 2 so lasers (mask 1|4) ignore it
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask  = 0
	area.monitorable     = true
	area.monitoring      = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.28
	cs.shape  = sp
	area.add_child(cs)
	add_child(area)

	_update_icon_mesh()


func _update_icon_mesh() -> void:
	_last_boid_count = boids.size()
	var fraction := float(boids.size()) / float(SQUAD_SIZE)

	_icon_mesh.clear_surfaces()

	const R    := 0.22
	const SEGS := 48   # steps around the diamond perimeter

	# Pre-sample perimeter points clockwise from top
	var pts: Array[Vector3] = []
	for i in SEGS + 1:
		pts.append(_diamond_pt(float(i) / float(SEGS), R))

	# Dim background — full diamond
	_icon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _icon_ring_mat)
	_icon_mesh.surface_add_vertex(Vector3(0.0,  R,   0.0))
	_icon_mesh.surface_add_vertex(Vector3( R,   0.0, 0.0))
	_icon_mesh.surface_add_vertex(Vector3(-R,   0.0, 0.0))
	_icon_mesh.surface_add_vertex(Vector3(0.0, -R,   0.0))
	_icon_mesh.surface_add_vertex(Vector3(-R,   0.0, 0.0))
	_icon_mesh.surface_add_vertex(Vector3( R,   0.0, 0.0))
	_icon_mesh.surface_end()

	# Bright fill — triangle fan from centre to diamond perimeter, alive fraction
	var fill_segs := int(round(SEGS * fraction))
	if fill_segs > 0:
		_icon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _icon_fill_mat)
		for i in fill_segs:
			_icon_mesh.surface_add_vertex(Vector3.ZERO)
			_icon_mesh.surface_add_vertex(pts[i])
			_icon_mesh.surface_add_vertex(pts[i + 1])
		_icon_mesh.surface_end()

	# Diamond outline — always full, bright
	_icon_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _icon_fill_mat)
	_icon_mesh.surface_add_vertex(Vector3(0.0,  R,   0.0))
	_icon_mesh.surface_add_vertex(Vector3( R,   0.0, 0.0))
	_icon_mesh.surface_add_vertex(Vector3(0.0, -R,   0.0))
	_icon_mesh.surface_add_vertex(Vector3(-R,   0.0, 0.0))
	_icon_mesh.surface_add_vertex(Vector3(0.0,  R,   0.0))
	_icon_mesh.surface_end()

	# Outer selection diamond — only drawn when selected
	if selected:
		const RS := R * 1.5
		_icon_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _icon_sel_mat)
		_icon_mesh.surface_add_vertex(Vector3(0.0,  RS,  0.0))
		_icon_mesh.surface_add_vertex(Vector3( RS,  0.0, 0.0))
		_icon_mesh.surface_add_vertex(Vector3(0.0, -RS,  0.0))
		_icon_mesh.surface_add_vertex(Vector3(-RS,  0.0, 0.0))
		_icon_mesh.surface_add_vertex(Vector3(0.0,  RS,  0.0))
		_icon_mesh.surface_end()


# Returns a point on the diamond perimeter at parameter t (0=top, clockwise, 1=full loop).
func _diamond_pt(t: float, r: float) -> Vector3:
	var t4  := fmod(t * 4.0, 4.0)
	var seg := int(t4)
	var s   := fmod(t4, 1.0)
	match seg:
		0: return Vector3( r * s,         r * (1.0 - s), 0.0)  # top  → right
		1: return Vector3( r * (1.0 - s), -r * s,        0.0)  # right → bottom
		2: return Vector3(-r * s,         -r * (1.0 - s),0.0)  # bottom → left
		3: return Vector3(-r * (1.0 - s),  r * s,        0.0)  # left  → top
	return Vector3(0.0, r, 0.0)


# ── Public interface ─────────────────────────────────────────────────────────

func is_selected() -> bool:
	return selected


func set_selected(value: bool) -> void:
	selected = value
	if selected:
		add_to_group("Selected")
		remove_from_group("Unselected")
	else:
		add_to_group("Unselected")
		remove_from_group("Selected")
	for b in boids:
		if is_instance_valid(b):
			b.set_highlighted(value)
	_update_icon_mesh()


func set_bezier_path(_control: Vector3, destination: Vector3) -> void:
	# Control point is ignored — boids curve naturally due to limited turn rate.
	# We just send them to the destination.
	attack_target = null
	waypoint      = destination
	home_position = destination
	has_waypoint  = true


func _find_nearest_enemy_ship() -> Ship:
	var enemy_group := "Enemies" if ally else "Allies"
	var best: Ship   = null
	var best_dist    := INF
	for node in get_tree().get_nodes_in_group(enemy_group):
		if node is Ship and is_instance_valid(node):
			var d := global_position.distance_to(node.global_position)
			if d < best_dist:
				best_dist = d
				best      = node
	return best


func set_attack_target(ship: Ship) -> void:
	attack_target = ship
	has_waypoint  = false


# ── Process — position is derived from boid centroid ─────────────────────────

func _process(_delta: float) -> void:
	# Self-destruct once all boids are gone — removes squad from all groups automatically
	if _boids_spawned and boids.is_empty():
		queue_free()
		return

	# Re-acquire nearest enemy when current target is destroyed or dying
	if attack_target != null and \
			(not is_instance_valid(attack_target) or attack_target._dying):
		attack_target = _find_nearest_enemy_ship()

	# Squad node position tracks the centroid of all living boids.
	# The icon, selection circle, and Area3D follow automatically as children.
	var centroid := Vector3.ZERO
	var n := 0
	for b in boids:
		if is_instance_valid(b):
			centroid += b.global_position
			n += 1
	if n > 0:
		global_position = centroid / float(n)

	# Refresh circular progress indicator when a boid dies
	if boids.size() != _last_boid_count:
		_update_icon_mesh()

	# Auto-clear waypoint once all boids are close enough
	if has_waypoint:
		var all_close := true
		for b in boids:
			if is_instance_valid(b) and b.global_position.distance_to(waypoint) > 3.0:
				all_close = false
				break
		if all_close:
			has_waypoint = false
