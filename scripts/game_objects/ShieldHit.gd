extends Node3D

const SHADER   := preload("res://shaders/shield_hit.gdshader")
const DURATION := 0.35


func setup(hit_pos: Vector3, surface_normal: Vector3) -> void:
	global_position = hit_pos

	var up    := surface_normal.normalized()
	var fwd   := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var right := up.cross(fwd).normalized()
	fwd       = right.cross(up).normalized()
	global_basis = Basis(right, up, fwd)

	var plane := PlaneMesh.new()
	plane.size = Vector2(0.45, 0.45)

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("progress", 0.0)

	var mi := MeshInstance3D.new()
	mi.mesh              = plane
	mi.material_override = mat
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("progress", v),
		0.0, 1.0, DURATION
	)
	tw.tween_callback(queue_free)
