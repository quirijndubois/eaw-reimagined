extends CanvasLayer

const SHIP_CATALOG: Array[Dictionary] = [
	{ "id": "ISD",  "label": "Star\nDestroyer",  "scene": "res://prefabs/ISD.tscn" },
	{ "id": "SQDN", "label": "Fighter\nSquadron", "scene": "res://prefabs/starfighter_squad.tscn" },
]

const CARD_SIZE    := Vector2(240, 290)
const MINIMAP_SIZE := Vector2(460, 460)

var _pause_btn: Button
var _paused := false
var _minimap_tween: Tween
var _minimap_container: Control
var _minimap_hovered := false

var _ship_panel: PanelContainer
var _drag_entry: Dictionary = {}
var _is_dragging := false
var _ghost_3d: Node3D = null

# Spawn-side toggle
var _spawn_as_ally: bool = true
var _ally_btn: Button
var _enemy_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("HUD")
	_build_top_bar()
	_build_ship_panel()
	_build_minimap()


func _process(_delta: float) -> void:
	_update_minimap_hover()
	if not _is_dragging or not _ghost_3d:
		return
	var mouse := get_viewport().get_mouse_position()
	if _ship_panel.get_global_rect().has_point(mouse):
		_ghost_3d.visible = false
		return
	var world_pos := _screen_to_world(mouse)
	if world_pos != Vector3.INF:
		_ghost_3d.visible = true
		_ghost_3d.position = world_pos
	else:
		_ghost_3d.visible = false


func _update_minimap_hover() -> void:
	if not _minimap_container:
		return
	var hovered := _minimap_container.get_global_rect().has_point(get_viewport().get_mouse_position())
	if hovered == _minimap_hovered:
		return
	_minimap_hovered = hovered
	_minimap_container.pivot_offset = _minimap_container.size
	if _minimap_tween:
		_minimap_tween.kill()
	_minimap_tween = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_minimap_tween.tween_property(_minimap_container, "scale", Vector2.ONE * (2.0 if hovered else 1.0), 0.25)


# ── Top-center buttons ────────────────────────────────────────────────────

func _build_top_bar() -> void:
	var container := PanelContainer.new()
	container.anchor_left   = 0.5
	container.anchor_right  = 0.5
	container.anchor_top    = 0.0
	container.anchor_bottom = 0.0
	container.offset_left   = -240
	container.offset_right  = 240
	container.offset_top    = 12
	container.offset_bottom = 98  # tall enough for 60px buttons + panel margin

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(hbox)

	_pause_btn = Button.new()
	_pause_btn.text = "|| Pause"
	_pause_btn.custom_minimum_size = Vector2(200, 60)
	_pause_btn.add_theme_font_size_override("font_size", 22)
	_pause_btn.focus_mode = Control.FOCUS_NONE   # prevent Space from activating the button
	_pause_btn.pressed.connect(_on_pause_pressed)
	hbox.add_child(_pause_btn)

	var slomo_btn := Button.new()
	slomo_btn.text = ">> 0.5x"
	slomo_btn.custom_minimum_size = Vector2(190, 60)
	slomo_btn.add_theme_font_size_override("font_size", 22)
	slomo_btn.toggle_mode = true
	slomo_btn.toggled.connect(_on_slomo_toggled)
	hbox.add_child(slomo_btn)

	var cinema_btn := Button.new()
	cinema_btn.text = "CINEMA"
	cinema_btn.custom_minimum_size = Vector2(160, 60)
	cinema_btn.add_theme_font_size_override("font_size", 22)
	cinema_btn.pressed.connect(_on_cinema_pressed)
	hbox.add_child(cinema_btn)

	add_child(container)


func _on_pause_pressed() -> void:
	_paused = !_paused
	get_tree().paused = _paused
	_pause_btn.text = "> Resume" if _paused else "|| Pause"


func _on_slomo_toggled(active: bool) -> void:
	Engine.time_scale = 0.4 if active else 1.0


func _on_cinema_pressed() -> void:
	var cams := get_tree().get_nodes_in_group("CinemaCamera")
	if not cams.is_empty():
		cams[0].toggle()


# ── Bottom-left: ship spawn palette ──────────────────────────────────────

func _build_ship_panel() -> void:
	_ship_panel = PanelContainer.new()
	_ship_panel.anchor_left   = 0.0
	_ship_panel.anchor_right  = 0.0
	_ship_panel.anchor_top    = 1.0
	_ship_panel.anchor_bottom = 1.0

	var n := SHIP_CATALOG.size()
	var panel_w := CARD_SIZE.x * n + 20.0 + maxf(0, n - 1) * 8.0
	_ship_panel.offset_left   = 14
	_ship_panel.offset_right  = 14 + panel_w
	# Extra height: CARD_SIZE + side-toggle row (38) + vbox separation (8) + panel margins (~20)
	_ship_panel.offset_top    = -(CARD_SIZE.y + 38 + 8 + 20 + 14)
	_ship_panel.offset_bottom = -14

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_ship_panel.add_child(vbox)

	# ── Side toggle row ───────────────────────────────────────────────────
	var toggle_row := HBoxContainer.new()
	toggle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	toggle_row.add_theme_constant_override("separation", 6)
	vbox.add_child(toggle_row)

	_ally_btn = Button.new()
	_ally_btn.text = "ALLY"
	_ally_btn.custom_minimum_size = Vector2(104, 44)
	_ally_btn.add_theme_font_size_override("font_size", 22)
	_ally_btn.pressed.connect(func(): _set_spawn_side(true))
	toggle_row.add_child(_ally_btn)

	_enemy_btn = Button.new()
	_enemy_btn.text = "ENEMY"
	_enemy_btn.custom_minimum_size = Vector2(104, 44)
	_enemy_btn.add_theme_font_size_override("font_size", 22)
	_enemy_btn.pressed.connect(func(): _set_spawn_side(false))
	toggle_row.add_child(_enemy_btn)

	_refresh_side_buttons()

	# ── Ship cards ────────────────────────────────────────────────────────
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	for entry in SHIP_CATALOG:
		hbox.add_child(_make_card(entry))

	add_child(_ship_panel)


func _set_spawn_side(ally: bool) -> void:
	_spawn_as_ally = ally
	_refresh_side_buttons()


func _refresh_side_buttons() -> void:
	_ally_btn.modulate  = Color(0.50, 0.85, 1.00) if _spawn_as_ally  else Color(1, 1, 1, 0.45)
	_enemy_btn.modulate = Color(1.00, 0.45, 0.45) if not _spawn_as_ally else Color(1, 1, 1, 0.45)


func _make_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(vbox)

	# Ship icon drawn via custom Control
	var icon := _make_ship_icon(entry.get("id", ""))
	icon.custom_minimum_size = Vector2(155, 105)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(icon)

	var lbl := Label.new()
	lbl.text = entry.get("label", entry.get("id", ""))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(lbl)

	var hint := Label.new()
	hint.text = "drag to place"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.modulate = Color(1, 1, 1, 0.45)
	hint.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(hint)

	card.gui_input.connect(_on_card_input.bind(entry))
	return card


# Draws a top-down Star Destroyer silhouette (wedge pointing upward)
func _make_ship_icon(ship_id: String) -> Control:
	var ctrl := Control.new()
	ctrl.draw.connect(func() -> void:
		var w := ctrl.size.x
		var h := ctrl.size.y
		if w < 1.0 or h < 1.0:
			return

		match ship_id:
			"ISD":
				# Concave 6-vertex hull decomposed into a triangle fan from the nose
				# so Godot's triangulator never sees a concave polygon.
				var nose   := Vector2(w * 0.50, 0)
				var pts    := [
					Vector2(w * 0.02, h * 0.92),  # port wing
					Vector2(w * 0.12, h * 0.70),  # port indent
					Vector2(w * 0.50, h * 0.82),  # stern centre
					Vector2(w * 0.88, h * 0.70),  # starboard indent
					Vector2(w * 0.98, h * 0.92),  # starboard wing
				]
				var body_col := Color(0.68, 0.70, 0.76)
				for i in pts.size() - 1:
					ctrl.draw_colored_polygon(
						PackedVector2Array([nose, pts[i], pts[i + 1]]), body_col)

				# Bridge superstructure diamond
				var bridge := PackedVector2Array([
					Vector2(w * 0.50, h * 0.30),
					Vector2(w * 0.60, h * 0.50),
					Vector2(w * 0.50, h * 0.65),
					Vector2(w * 0.40, h * 0.50),
				])
				ctrl.draw_colored_polygon(bridge, Color(0.85, 0.87, 0.93))

				# Subtle outline
				ctrl.draw_polyline(
					PackedVector2Array([nose, pts[0], pts[1], pts[2], pts[3], pts[4], nose]),
					Color(0.9, 0.92, 1.0, 0.35), 1.0
				)
			"SQDN":
				# Five small fighters in a V-formation
				var col := Color(0.45, 0.75, 1.0)
				var tips := [
					Vector2(w*0.50, h*0.08),
					Vector2(w*0.25, h*0.38),
					Vector2(w*0.75, h*0.38),
					Vector2(w*0.10, h*0.72),
					Vector2(w*0.90, h*0.72),
				]
				for tip in tips:
					ctrl.draw_colored_polygon(PackedVector2Array([
						tip,
						tip + Vector2(-w*0.08, h*0.20),
						tip + Vector2( w*0.08, h*0.20),
					]), col)
			_:
				# Generic fallback — simple triangle
				ctrl.draw_colored_polygon(
					PackedVector2Array([Vector2(w*0.5, 0), Vector2(0, h), Vector2(w, h)]),
					Color(0.6, 0.65, 0.7)
				)
	)
	return ctrl


# ── Bottom-right: minimap ─────────────────────────────────────────────────

func _build_minimap() -> void:
	var container := PanelContainer.new()
	container.anchor_left   = 1.0
	container.anchor_right  = 1.0
	container.anchor_top    = 1.0
	container.anchor_bottom = 1.0
	container.offset_left   = -(MINIMAP_SIZE.x + 22)
	container.offset_right  = -14
	# Title (~26px) + separation (4) + minimap (320) + panel margins (~20) + bottom gap (14)
	container.offset_top    = -(MINIMAP_SIZE.y + 26 + 4 + 20 + 14)
	container.offset_bottom = -14

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	container.add_child(vbox)

	var title := Label.new()
	title.text = "OVERVIEW"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var map := MinimapDisplay.new()
	map.custom_minimum_size = MINIMAP_SIZE
	vbox.add_child(map)

	_minimap_container = container
	add_child(container)


# ── 3D ghost during drag ──────────────────────────────────────────────────

func _create_ghost_3d(entry: Dictionary) -> Node3D:
	var packed := load(entry.get("scene", "")) as PackedScene
	if not packed:
		return null

	var temp := packed.instantiate()
	var mesh_inst := _find_first_mesh(temp)

	var ghost := Node3D.new()
	if mesh_inst:
		var gm := MeshInstance3D.new()
		gm.mesh = mesh_inst.mesh
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := StandardMaterial3D.new()
		mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color     = Color(0.45, 0.65, 1.0, 0.22) if _spawn_as_ally \
							   else Color(1.0, 0.40, 0.40, 0.22)
		mat.emission_enabled = true
		mat.emission         = Color(0.4, 0.6, 1.0) if _spawn_as_ally \
							   else Color(1.0, 0.35, 0.35)
		mat.emission_energy  = 0.8
		mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.material_override = mat
		ghost.add_child(gm)

	temp.free()

	if not _spawn_as_ally:
		ghost.rotation.y = PI

	ghost.visible = false
	get_tree().current_scene.add_child(ghost)
	return ghost


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_first_mesh(child)
		if result:
			return result
	return null


# ── Input: end drag ───────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_P:
		_on_pause_pressed()
		get_viewport().set_input_as_handled()
		return
	if not _is_dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag(event.position)
		get_viewport().set_input_as_handled()


func _on_card_input(event: InputEvent, entry: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_drag_entry = entry
		_is_dragging = true
		_ghost_3d = _create_ghost_3d(entry)


func _finish_drag(screen_pos: Vector2) -> void:
	_is_dragging = false

	if _ghost_3d:
		_ghost_3d.queue_free()
		_ghost_3d = null

	if _drag_entry.is_empty():
		return

	if _ship_panel.get_global_rect().has_point(screen_pos):
		_drag_entry = {}
		return

	var world_pos := _screen_to_world(screen_pos)
	if world_pos == Vector3.INF:
		_drag_entry = {}
		return

	_spawn_ship(_drag_entry, world_pos)
	_drag_entry = {}


func _spawn_ship(entry: Dictionary, world_pos: Vector3) -> void:
	var packed := load(entry.get("scene", "")) as PackedScene
	if not packed:
		push_error("HUD: could not load scene: " + entry.get("scene", ""))
		return
	var node := packed.instantiate()
	if not node:
		return
	var drop := Vector3(world_pos.x, randf_range(-0.6, 0.6), world_pos.z)
	if node is Ship:
		node.ally = _spawn_as_ally
		node.position = world_pos
		if not node.ally:
			node.rotation.y = PI
		get_tree().current_scene.add_child(node)
		node.hyperspace_arrive(drop)
	elif node is StarfighterSquad:
		node.ally = _spawn_as_ally
		node.position = drop
		if not node.ally:
			node.rotation.y = PI
		get_tree().current_scene.add_child(node)


# ── Helpers ───────────────────────────────────────────────────────────────

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3.INF
	var from  := camera.project_ray_origin(screen_pos)
	var dir   := camera.project_ray_normal(screen_pos)
	var denom := dir.dot(Vector3.UP)
	if abs(denom) < 0.001:
		return Vector3.INF
	var t := (Vector3.ZERO - from).dot(Vector3.UP) / denom
	return from + dir * t
