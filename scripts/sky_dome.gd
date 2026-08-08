extends Node3D

const SHADER := preload("res://shaders/sky_dome.gdshader")


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 300.0
	sphere.height = 600.0
	sphere.radial_segments = 32
	sphere.rings = 16

	var mat := ShaderMaterial.new()
	mat.shader = SHADER

	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
