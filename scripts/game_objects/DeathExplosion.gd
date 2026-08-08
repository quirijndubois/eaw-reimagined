extends Node3D

const T_FIRE  := preload("res://textures/fire_01.png")
const T_SMOKE := preload("res://textures/smoke_01.png")
const T_SPARK := preload("res://textures/spark_01.png")
const T_FLARE := preload("res://textures/flare_01.png")
const T_RING  := preload("res://textures/circle_01.png")

func _ready() -> void:
	_spawn_light()
	_spawn_shockwave_ring(0.0, 1.8, 0.6)
	_spawn_shockwave_ring(0.15, 1.2, 0.9)
	_spawn_shockwave_ring(0.4, 0.9, 1.2)
	_spawn_flash()
	_spawn_fireball()
	_spawn_smoke()
	_spawn_sparks()
	get_tree().create_timer(randf_range(4.5, 5.5)).timeout.connect(queue_free)


func _spawn_light() -> void:
	var l := OmniLight3D.new()
	l.light_color  = Color(1.0, 0.60, 0.20)
	l.light_energy = 20.0
	l.omni_range   = 18.0
	l.shadow_enabled = false
	add_child(l)
	var tw := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "light_energy", 0.0, 2.5)


func _spawn_shockwave_ring(delay: float, scale_end: float, lifetime: float) -> void:
	var p := _particles(1, lifetime, 1.0)
	p.transform = Transform3D(Basis(Vector3.RIGHT, randf_range(0.0, TAU)), Vector3.ZERO)
	var pm := ParticleProcessMaterial.new()
	pm.spread               = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity              = Vector3.ZERO
	pm.scale_min            = 0.2
	pm.scale_max            = 0.2
	pm.color_ramp = _grad([
		Color(1.0, 0.85, 0.40, 0.85),
		Color(1.0, 0.50, 0.10, 0.50),
		Color(0.6, 0.20, 0.00, 0.0),
	])
	pm.scale_curve = _curve([Vector2(0, 0.15), Vector2(0.5, scale_end * 0.7), Vector2(1.0, scale_end)])
	p.process_material  = pm
	p.draw_pass_1       = _quad(1.2)
	p.material_override = _mat(T_RING, true)
	if delay > 0.0:
		p.visible = false
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.visible = true
				p.restart()
		)
	add_child(p)


func _spawn_flash() -> void:
	var p := _particles(6, 0.35, 1.0)
	var pm := ParticleProcessMaterial.new()
	pm.spread               = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.gravity              = Vector3.ZERO
	pm.scale_min            = 2.0
	pm.scale_max            = 4.0
	pm.color_ramp = _grad([
		Color(1.0, 1.0, 0.95, 1.0),
		Color(1.0, 0.85, 0.35, 0.8),
		Color(1.0, 0.40, 0.0, 0.0),
	])
	p.process_material  = pm
	p.draw_pass_1       = _quad(0.5)
	p.material_override = _mat(T_FLARE, true)
	add_child(p)


func _spawn_fireball() -> void:
	var p := _particles(40, 1.8, 0.85)
	var pm := ParticleProcessMaterial.new()
	pm.spread               = 180.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.8
	pm.gravity              = Vector3.ZERO
	pm.scale_min            = 1.0
	pm.scale_max            = 2.5
	pm.color_ramp = _grad([
		Color(1.0, 0.90, 0.35, 1.0),
		Color(1.0, 0.50, 0.05, 0.90),
		Color(0.60, 0.12, 0.00, 0.70),
		Color(0.10, 0.05, 0.00, 0.0),
	])
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.3, 1.0), Vector2(1.0, 1.8)])
	p.process_material  = pm
	p.draw_pass_1       = _quad(0.5)
	p.material_override = _mat(T_FIRE, false)
	add_child(p)


func _spawn_smoke() -> void:
	var p := _particles(28, 3.5, 0.75)
	var pm := ParticleProcessMaterial.new()
	pm.spread               = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.8
	pm.gravity              = Vector3.ZERO
	pm.scale_min            = 1.2
	pm.scale_max            = 3.0
	pm.color_ramp = _grad([
		Color(0.45, 0.25, 0.10, 0.0),
		Color(0.28, 0.16, 0.06, 0.85),
		Color(0.14, 0.11, 0.09, 0.90),
		Color(0.06, 0.05, 0.04, 0.0),
	])
	pm.scale_curve = _curve([Vector2(0, 0.2), Vector2(0.35, 1.0), Vector2(1.0, 2.8)])
	p.process_material  = pm
	p.draw_pass_1       = _quad(0.6)
	p.material_override = _mat(T_SMOKE, false)
	add_child(p)


func _spawn_sparks() -> void:
	var p := _particles(80, 1.2, 0.95)
	var pm := ParticleProcessMaterial.new()
	pm.spread               = 180.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 4.5
	pm.gravity              = Vector3.ZERO
	pm.scale_min            = 0.3
	pm.scale_max            = 0.9
	pm.color_ramp = _grad([
		Color(1.0, 0.95, 0.7, 1.0),
		Color(1.0, 0.60, 0.1, 0.9),
		Color(0.9, 0.25, 0.0, 0.5),
		Color(0.0, 0.00, 0.0, 0.0),
	])
	p.process_material  = pm
	p.draw_pass_1       = _quad(0.08)
	p.material_override = _mat(T_SPARK, true)
	add_child(p)


func _particles(amount: int, lifetime: float, explosiveness: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount        = amount
	p.lifetime      = lifetime
	p.explosiveness = explosiveness
	p.one_shot      = true
	p.fixed_fps     = 0
	return p


func _quad(side: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(side, side)
	return q


func _mat(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode                 = BaseMaterial3D.BLEND_MODE_ADD if additive \
	                               else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture             = tex
	m.billboard_mode             = BaseMaterial3D.BILLBOARD_ENABLED
	m.depth_draw_mode            = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _grad(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var n := colors.size()
	g.colors  = PackedColorArray(colors)
	var offs  := PackedFloat32Array()
	for i in n:
		offs.append(float(i) / float(n - 1))
	g.offsets = offs
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _curve(pts: Array) -> CurveTexture:
	var c := Curve.new()
	for pt: Vector2 in pts:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t
