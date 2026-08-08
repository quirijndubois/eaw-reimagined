extends Node3D

const SHADER      := preload("res://shaders/play_area_grid.gdshader")
const WORLD_BOUNDS := 75.0


func _ready() -> void:
	add_to_group("HUD")
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_BOUNDS * 2.0, WORLD_BOUNDS * 2.0)

	var mat := ShaderMaterial.new()
	mat.shader = SHADER

	var mi := MeshInstance3D.new()
	mi.mesh              = plane
	mi.material_override = mat
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position          = Vector3(0.0, -0.02, 0.0)  # just below ships/ground
	add_child(mi)
