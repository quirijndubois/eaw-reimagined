extends Node3D

const T_FIRE  := preload("res://textures/fire_01.png")
const T_SMOKE := preload("res://textures/smoke_01.png")

func _ready() -> void:
	_spawn_fire()
	_spawn_smoke()


func _spawn_fire() -> void:
	var p := GPUParticles3D.new()
	p.amount        = 18
	p.lifetime      = 0.7
	p.explosiveness = 0.0
	p.one_shot      = false
	p.fixed_fps     = 0

	var pm := ParticleProcessMaterial.new()
	pm.spread               = 35.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity              = Vector3(0, 0.4, 0)
	pm.scale_min            = 0.5
	pm.scale_max            = 1.1
	pm.color_ramp = _grad([
		Color(1.0, 0.90, 0.30, 0.9),
		Color(1.0, 0.45, 0.05, 0.8),
		Color(0.55, 0.10, 0.00, 0.5),
		Color(0.10, 0.04, 0.00, 0.0),
	])
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.4, 1.0), Vector2(1.0, 0.5)])

	var m := StandardMaterial3D.new()
	m.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode                 = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture             = T_FIRE
	m.billboard_mode             = BaseMaterial3D.BILLBOARD_ENABLED
	m.depth_draw_mode            = BaseMaterial3D.DEPTH_DRAW_DISABLED

	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)

	p.process_material  = pm
	p.draw_pass_1       = q
	p.material_override = m
	add_child(p)


func _spawn_smoke() -> void:
	var p := GPUParticles3D.new()
	p.amount        = 12
	p.lifetime      = 1.6
	p.explosiveness = 0.0
	p.one_shot      = false
	p.fixed_fps     = 0

	var pm := ParticleProcessMaterial.new()
	pm.spread               = 25.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.45
	pm.gravity              = Vector3(0, 0.15, 0)
	pm.scale_min            = 0.6
	pm.scale_max            = 1.4
	pm.color_ramp = _grad([
		Color(0.35, 0.20, 0.08, 0.0),
		Color(0.22, 0.14, 0.06, 0.65),
		Color(0.12, 0.10, 0.08, 0.70),
		Color(0.06, 0.05, 0.04, 0.0),
	])
	pm.scale_curve = _curve([Vector2(0, 0.2), Vector2(0.4, 1.0), Vector2(1.0, 2.0)])

	var m := StandardMaterial3D.new()
	m.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode                 = BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture             = T_SMOKE
	m.billboard_mode             = BaseMaterial3D.BILLBOARD_ENABLED
	m.depth_draw_mode            = BaseMaterial3D.DEPTH_DRAW_DISABLED

	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)

	p.process_material  = pm
	p.draw_pass_1       = q
	p.material_override = m
	add_child(p)


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
