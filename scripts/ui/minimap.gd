class_name MinimapDisplay
extends Control

const WORLD_BOUNDS := 75.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)

	draw_rect(r, Color(0.03, 0.06, 0.03, 0.92))

	var grid := Color(0.10, 0.20, 0.10)
	for i in range(1, 5):
		var x := size.x * i / 4.0
		var y := size.y * i / 4.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid)
		draw_line(Vector2(0, y), Vector2(size.x, y), grid)

	var tree := get_tree()
	if tree:
		for ship in tree.get_nodes_in_group("Ships"):
			if ship is Ship:
				_draw_ship(ship)
			elif ship is StarfighterSquad:
				_draw_squad(ship)
		_draw_camera_view()

	draw_rect(r, Color(0.2, 0.5, 0.2), false, 2.0)


func _draw_ship(ship: Node) -> void:
	if not ship is Ship:
		return
	var mp := _to_map(ship.global_position)
	if mp.x < 0 or mp.x > size.x or mp.y < 0 or mp.y > size.y:
		return
	var color := Color(0.35, 0.55, 1.0) if ship.ally else Color(1.0, 0.35, 0.35)
	var range_r: float = ship.fire_range * size.x / (WORLD_BOUNDS * 2.0)
	draw_arc(mp, range_r, 0.0, TAU, 64, Color(color.r, color.g, color.b, 0.18), 1.0)
	draw_circle(mp, 7.0, color)
	var tip := mp + Vector2(sin(ship.angle), cos(ship.angle)) * 12.0
	draw_line(mp, tip, color.lightened(0.4), 2.5)


func _draw_squad(squad: StarfighterSquad) -> void:
	var mp := _to_map(squad.global_position)
	if mp.x < 0 or mp.x > size.x or mp.y < 0 or mp.y > size.y:
		return
	var color := Color(0.45, 0.75, 1.0) if squad.ally else Color(1.0, 0.55, 0.45)
	# Draw small triangle for each boid
	for b in squad.boids:
		if not is_instance_valid(b):
			continue
		var bp := _to_map(b.global_position)
		draw_colored_polygon(PackedVector2Array([
			bp + Vector2(0, -4),
			bp + Vector2(-3, 3),
			bp + Vector2(3, 3),
		]), color)


func _draw_camera_view() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var vp_size := get_viewport().get_visible_rect().size
	var corners := [Vector2(0, 0), Vector2(vp_size.x, 0),
					Vector2(vp_size.x, vp_size.y), Vector2(0, vp_size.y)]

	var poly: Array[Vector2] = []
	for sc in corners:
		poly.append(_to_map(_screen_to_ground(camera, sc)))

	# Sort by polar angle around centroid so the quad is always convex (no hourglass)
	var center := Vector2.ZERO
	for p in poly:
		center += p
	center /= 4.0
	poly.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return (a - center).angle() < (b - center).angle()
	)

	# Draw each edge clipped to the minimap rect
	var color := Color(1.0, 1.0, 0.4, 0.75)
	for i in range(4):
		var seg := _clip_line(poly[i], poly[(i + 1) % 4])
		if seg.size() == 2:
			draw_line(seg[0], seg[1], color, 1.8)


# Liang-Barsky clipping of a line segment to [0,size.x] x [0,size.y]
func _clip_line(p1: Vector2, p2: Vector2) -> Array:
	var dx := p2.x - p1.x
	var dy := p2.y - p1.y
	var t0 := 0.0
	var t1 := 1.0
	var ps := [-dx,        dx,        -dy,        dy       ]
	var qs := [p1.x, size.x - p1.x,  p1.y, size.y - p1.y]

	for i in range(4):
		if ps[i] == 0.0:
			if qs[i] < 0.0:
				return []
		elif ps[i] < 0.0:
			t0 = maxf(t0, qs[i] / ps[i])
		else:
			t1 = minf(t1, qs[i] / ps[i])

	if t0 > t1:
		return []

	return [Vector2(p1.x + t0 * dx, p1.y + t0 * dy),
			Vector2(p1.x + t1 * dx, p1.y + t1 * dy)]


func _screen_to_ground(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	var from  := camera.project_ray_origin(screen_pos)
	var dir   := camera.project_ray_normal(screen_pos)
	var denom := dir.dot(Vector3.UP)
	var t: float
	if abs(denom) < 0.001:
		# Ray nearly parallel to ground — push to far horizon
		t = WORLD_BOUNDS * 8.0
	else:
		t = -from.y / denom
		if t < 0.0:
			# Ray points away from ground (looking at sky) — mirror to far horizon
			t = WORLD_BOUNDS * 8.0
		else:
			t = minf(t, WORLD_BOUNDS * 8.0)
	return from + dir * t


func _to_map(world: Vector3) -> Vector2:
	var u := (world.x + WORLD_BOUNDS) / (WORLD_BOUNDS * 2.0)
	var v := (world.z + WORLD_BOUNDS) / (WORLD_BOUNDS * 2.0)
	return Vector2(u * size.x, v * size.y)
