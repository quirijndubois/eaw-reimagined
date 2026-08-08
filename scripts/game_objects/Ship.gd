class_name Ship
extends Node3D

const DEATH_EXPLOSION_SCENE := preload("res://prefabs/death_explosion.tscn")
const SHIP_FIRE_SCENE       := preload("res://prefabs/ship_fire.tscn")

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

@export var max_speed: float = 0.7
@export var acceleration: float = 0.8

@export var max_rotation_speed: float = 5
@export var rotation_acceleration: float = 1.5

@export var fire_range: float = 25.0

var selection_circle_instance: MeshInstance3D
var range_circle_instance: MeshInstance3D
var visible_material: StandardMaterial3D
var invisible_material: StandardMaterial3D
var range_visible_material: StandardMaterial3D
var range_invisible_material: StandardMaterial3D

var angle := 0.0
var location := Vector2.ZERO
var z_offset := 0.0
var speed := 0.0
var angle_speed := 0.0
var target_angle := 0.0

# Quadratic bezier path: p0 (start) → p1 (control) → p2 (destination)
var bezier_p0 := Vector3.ZERO
var bezier_p1 := Vector3.ZERO
var bezier_p2 := Vector3.ZERO
var path_t := -1.0

var combat_target: Node3D = null

var _arriving := false
var _dying   := false
var _bank: float = 0.0
var _fall_speed: float = 0.0
var _tumble_rate: Vector3 = Vector3.ZERO
var _tumble: Vector3 = Vector3.ZERO


func _ready() -> void:
	target_angle = rotation.y
	angle = rotation.y

	create_collision_shape()
	create_selection_circle()
	create_range_circle()
	set_selected(selected)
	set_bars()

	location = Vector2(global_position.x, global_position.z)
	z_offset = global_position.y

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
	set_bars()


func die() -> void:
	if _dying:
		return
	_dying = true
	set_selected(false)
	remove_from_group("Ships")
	remove_from_group("Allies")
	remove_from_group("Enemies")

	# Disable collision so clicks pass through the wreck
	var static_body := mesh_instance.get_node_or_null("StaticBody")
	if static_body:
		static_body.collision_layer = 0
		static_body.collision_mask  = 0

	# Stop all turrets on this ship
	for child in get_children():
		if child is Turret:
			child.active = false
			child.set_process(false)

	var exp := DEATH_EXPLOSION_SCENE.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position

	for i in 3:
		var fire := SHIP_FIRE_SCENE.instantiate()
		fire.position = Vector3(
			randf_range(-0.4, 0.4),
			randf_range(0.0, 0.15),
			randf_range(-0.9, 0.2)
		)
		add_child(fire)

	_tumble_rate = Vector3(
		randf_range(-0.4, 0.4),
		randf_range(-0.15, 0.15),
		randf_range(-0.4, 0.4)
	)
	_tumble = rotation

	get_tree().create_timer(15.0).timeout.connect(queue_free)


func create_collision_shape() -> void:
	var static_body = StaticBody3D.new()
	static_body.name = "StaticBody"
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	if mesh_instance.mesh:
		var shape = mesh_instance.mesh.create_trimesh_shape()
		collision_shape.shape = shape
		static_body.add_child(collision_shape)
		mesh_instance.add_child(static_body)
		if mesh_instance.owner:
			static_body.owner = mesh_instance.owner
			collision_shape.owner = mesh_instance.owner
	else:
		push_warning("MeshInstance has no mesh assigned for collision creation")
		static_body.free()


func create_selection_circle():
	visible_material = StandardMaterial3D.new()
	visible_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if ally:
		visible_material.albedo_color = Color(0, 0, 1)
	else:
		visible_material.albedo_color = Color(1, 0, 0)

	visible_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	invisible_material = visible_material.duplicate()
	invisible_material.albedo_color.a = 0.0

	var circle_mesh := ImmediateMesh.new()
	var radius: float = 1.5
	var segments: int = 64
	circle_mesh.clear_surfaces()
	circle_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, visible_material)

	for i in range(segments + 1):
		var ang = TAU * i / float(segments)
		circle_mesh.surface_add_vertex(Vector3(radius * cos(ang), 0.01, radius * sin(ang)))

	circle_mesh.surface_end()

	selection_circle_instance = MeshInstance3D.new()
	selection_circle_instance.mesh = circle_mesh
	add_child(selection_circle_instance)


func create_range_circle() -> void:
	var team_color := Color(0.3, 0.55, 1.0) if ally else Color(1.0, 0.35, 0.35)

	range_visible_material = StandardMaterial3D.new()
	range_visible_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_visible_material.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.18)
	range_visible_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	range_invisible_material = range_visible_material.duplicate()
	range_invisible_material.albedo_color.a = 0.0

	var circle_mesh := ImmediateMesh.new()
	var segments := 96
	var dash := 8
	var gap  := 3
	var step := dash + gap
	var i    := 0
	while i < segments:
		var end: int = min(i + dash, segments)
		circle_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, range_visible_material)
		for j in range(i, end + 1):
			var ang := TAU * j / float(segments)
			circle_mesh.surface_add_vertex(Vector3(fire_range * cos(ang), 0.01, fire_range * sin(ang)))
		circle_mesh.surface_end()
		i += step

	range_circle_instance = MeshInstance3D.new()
	range_circle_instance.mesh = circle_mesh
	add_child(range_circle_instance)


func set_selected(value: bool) -> void:
	if _dying and value:
		return
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

	if range_circle_instance:
		var rc_mesh := range_circle_instance.mesh as ImmediateMesh
		if rc_mesh:
			var mat := range_visible_material if selected else range_invisible_material
			for s in range(rc_mesh.get_surface_count()):
				rc_mesh.surface_set_material(s, mat)


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
	var should_fire := not _arriving and not _dying
	for child in get_children():
		if child is Turret:
			child.active = should_fire


# Assign a quadratic bezier path. control is the pull handle, destination is the end point.
func set_attack_target(target: Node3D) -> void:
	combat_target = target
	path_t = -1.0


func set_bezier_path(control: Vector3, destination: Vector3) -> void:
	combat_target = null
	bezier_p0 = Vector3(location.x, z_offset, location.y)
	bezier_p1 = control
	bezier_p2 = destination
	path_t = 0.0


func _bezier_pos(t: float) -> Vector3:
	var u := 1.0 - t
	return u * u * bezier_p0 + 2.0 * u * t * bezier_p1 + t * t * bezier_p2


func _bezier_tangent(t: float) -> Vector3:
	var u := 1.0 - t
	return 2.0 * u * (bezier_p1 - bezier_p0) + 2.0 * t * (bezier_p2 - bezier_p1)


func _update_rotation(delta: float) -> void:
	# Shortest angular distance to target, wrapped to [-PI, PI]
	var angle_diff := fposmod(target_angle - angle + PI, TAU) - PI

	var time_to_stop: float = abs(angle_speed) / rotation_acceleration
	var angle_to_stop: float = abs(angle_speed) * time_to_stop / 2.0

	var target_angle_speed := 0.0
	if angle_to_stop < abs(angle_diff):
		target_angle_speed = sign(angle_diff) * max_rotation_speed

	angle_speed = move_toward(angle_speed, target_angle_speed, rotation_acceleration * delta)
	angle += angle_speed * delta


func _follow_bezier(delta: float) -> void:
	var tangent := _bezier_tangent(path_t)
	var tangent_len := tangent.length()

	if tangent_len < 0.001:
		_arrive()
		return

	# Braking: decelerate when remaining distance is less than stopping distance
	var dist_remaining := _bezier_pos(path_t).distance_to(bezier_p2)
	var dist_to_stop := speed * speed / (2.0 * acceleration) if speed > 0.0 else 0.0

	if dist_remaining > dist_to_stop:
		speed = min(speed + acceleration * delta, max_speed)
	else:
		speed = max(speed - acceleration * delta, 0.0)

	# Advance t by converting world-space speed to curve parameter speed
	path_t = min(path_t + speed * delta / tangent_len, 1.0)

	var new_pos := _bezier_pos(path_t)
	location = Vector2(new_pos.x, new_pos.z)

	# Always face direction of travel
	target_angle = atan2(tangent.x, tangent.z)

	if path_t >= 1.0:
		_arrive()


func _arrive() -> void:
	speed = 0.0
	path_t = -1.0


func hyperspace_arrive(drop_target: Vector3) -> void:
	var facing := Vector3(sin(angle), 0.0, cos(angle))
	var start  := drop_target - facing * 600.0

	location = Vector2(start.x, start.z)
	z_offset = start.y
	_set_position()
	target_angle = atan2(facing.x, facing.z)
	angle        = target_angle

	_arriving = true
	path_t    = -1.0

	# Tween ship position
	var tween := create_tween()
	tween.tween_method(_hyperspace_move, start, drop_target, 1.1) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _arriving = false)


func _hyperspace_move(pos: Vector3) -> void:
	location = Vector2(pos.x, pos.z)
	z_offset = pos.y


func _set_position() -> void:
	global_position = Vector3(location.x, z_offset, location.y)


func _set_rotation() -> void:
	rotation = Vector3(0, angle, _bank)


func _process(delta: float) -> void:
	if _dying:
		_fall_speed += 0.18 * delta
		z_offset -= _fall_speed * delta
		_tumble += _tumble_rate * delta
		rotation = _tumble
		_set_position()
		return

	_handle_weapons()

	# Clear dead/destroyed combat target
	if combat_target != null:
		if not is_instance_valid(combat_target):
			combat_target = null
		elif combat_target is Ship and combat_target._dying:
			combat_target = null
		elif combat_target is StarfighterSquad and combat_target.boids.is_empty():
			combat_target = null

	_update_rotation(delta)
	if range_circle_instance and selected:
		range_circle_instance.rotation.y = -angle + (Time.get_ticks_msec() * 0.0004)

	if path_t >= 0.0:
		_follow_bezier(delta)
	elif is_instance_valid(combat_target):
		_pursue_combat_target(delta)

	var target_bank := clampf(-angle_speed * 0.06, -0.3, 0.3)
	_bank = lerpf(_bank, target_bank, delta * 4.0)
	_set_position()
	_set_rotation()


func _pursue_combat_target(delta: float) -> void:
	var target_pos := combat_target.global_position
	var to_target  := Vector3(target_pos.x - global_position.x, 0.0, target_pos.z - global_position.z)
	var dist       := to_target.length()

	if to_target.length_squared() > 0.001:
		target_angle = atan2(to_target.x, to_target.z)

	if dist > fire_range * 0.75:
		speed = minf(speed + acceleration * delta, max_speed)
		var fwd := Vector2(sin(angle), cos(angle))
		location += fwd * speed * delta
	else:
		speed = maxf(speed - acceleration * delta * 3.0, 0.0)


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
