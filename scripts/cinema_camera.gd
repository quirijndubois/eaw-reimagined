extends Node3D

const SHOT_DURATION := 5.0

var _active      := false
var _camera: Camera3D
var _timer       := 0.0
var _tween: Tween
var _chase_ship: Node3D = null
var _chase_offset := Vector3.ZERO
var _chase_boid: Boid = null
var _fade_rect: ColorRect
var _exit_btn: Button

# Shot history — each entry is a Callable with all params already bound
var _history: Array    = []
var _history_pos: int  = -1


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	add_to_group("CinemaCamera")

	_camera = Camera3D.new()
	_camera.current = false
	_camera.fov = 55.0
	add_child(_camera)

	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	cl.add_child(_fade_rect)

	_exit_btn = Button.new()
	_exit_btn.text = "EXIT CINEMA  [SPACE]"
	_exit_btn.add_theme_font_size_override("font_size", 15)
	_exit_btn.anchor_left   = 0.5
	_exit_btn.anchor_right  = 0.5
	_exit_btn.anchor_top    = 0.0
	_exit_btn.anchor_bottom = 0.0
	_exit_btn.offset_left   = -110
	_exit_btn.offset_right  =  110
	_exit_btn.offset_top    =  12
	_exit_btn.offset_bottom =  44
	_exit_btn.modulate      = Color(1, 1, 1, 0.7)
	_exit_btn.visible       = false
	_exit_btn.pressed.connect(toggle)
	cl.add_child(_exit_btn)


func toggle() -> void:
	if _active:
		_exit()
	else:
		_enter()


func _enter() -> void:
	_active = true
	_camera.current = true
	_exit_btn.visible = true
	for hud in get_tree().get_nodes_in_group("HUD"):
		hud.visible = false
	_advance_shot()


func _exit() -> void:
	_active = false
	_camera.current = false
	_exit_btn.visible = false
	_chase_ship = null
	_chase_boid = null
	if _tween: _tween.kill()
	for hud in get_tree().get_nodes_in_group("HUD"):
		hud.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			toggle()
		KEY_RIGHT:
			if _active: _advance_shot()
		KEY_LEFT:
			if _active: _retreat_shot()


func _process(delta: float) -> void:
	if not _active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_advance_shot()
		return
	if _chase_ship and is_instance_valid(_chase_ship):
		_camera.global_position = _camera.global_position.lerp(
			_chase_ship.global_position + _chase_offset, delta * 2.5
		)
		_safe_look_at(_chase_ship.global_position + Vector3.UP * 0.3)

	if _chase_boid and is_instance_valid(_chase_boid):
		var dir: Vector3 = _chase_boid._fwd
		var target_pos := _chase_boid.global_position - dir * 0.18 + Vector3.UP * 0.07
		_camera.global_position = _camera.global_position.lerp(target_pos, delta * 8.0)
		_safe_look_at(_chase_boid.global_position + dir * 2.0)


# ── History navigation ────────────────────────────────────────────────────────

func _advance_shot() -> void:
	_history_pos += 1
	if _history_pos < _history.size():
		_play_shot(_history[_history_pos])
	else:
		var shot := _make_shot()
		if not shot.is_valid():
			_history_pos -= 1
			return
		_history.append(shot)
		_play_shot(shot)


func _retreat_shot() -> void:
	if _history_pos <= 0:
		return
	_history_pos -= 1
	_play_shot(_history[_history_pos])


func _play_shot(shot: Callable) -> void:
	_timer = SHOT_DURATION
	_chase_ship = null
	_chase_boid = null
	if _tween: _tween.kill()
	_do_cut()
	shot.call()


# ── Shot factory — generates random params and returns a Callable ─────────────

func _make_shot() -> Callable:
	var ships := get_tree().get_nodes_in_group("Ships")
	if ships.is_empty():
		return Callable()
	var ship: Node3D = ships.pick_random()
	# Offer boid followcam only when live boids are present (~1-in-7 chance)
	var has_boids := _get_random_live_boid() != null
	match randi() % (7 if has_boids else 6):
		0: return _make_orbit(ship)
		1: return _make_flyby(ship)
		2: return _make_approach(ship)
		3: return _make_low_pan(ship)
		4: return _make_side_track(ship)
		5: return _make_over_shoulder(ship)
		_: return _make_boid_followcam()


func _make_orbit(ship: Node3D) -> Callable:
	var dist        := randf_range(2.0, 4.5)
	var height      := randf_range(0.5, 1.5)
	var start_angle := randf_range(0.0, TAU)
	var arc         := randf_range(PI * 0.35, PI * 0.6) * (1.0 if randf() > 0.5 else -1.0)
	return func() -> void:
		_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_method(func(t: float) -> void:
			if not is_instance_valid(ship): return
			var a := start_angle + arc * t
			_camera.global_position = ship.global_position + Vector3(cos(a) * dist, height, sin(a) * dist)
			_safe_look_at(ship.global_position + Vector3.UP * 0.3)
		, 0.0, 1.0, SHOT_DURATION)


func _make_flyby(ship: Node3D) -> Callable:
	var fwd    := _ship_forward(ship)
	var side   := fwd.cross(Vector3.UP).normalized() * (1.0 if randf() > 0.5 else -1.0)
	var offset := side * randf_range(1.5, 3.0) + Vector3.UP * randf_range(0.2, 1.0)
	var start  := ship.global_position - fwd * 2.5 + offset
	var end    := ship.global_position + fwd * 2.5 + offset
	return func() -> void:
		_tween = create_tween().set_trans(Tween.TRANS_SINE)
		_tween.tween_method(func(t: float) -> void:
			if not is_instance_valid(ship): return
			_camera.global_position = start.lerp(end, t)
			_safe_look_at(ship.global_position + Vector3.UP * 0.3)
		, 0.0, 1.0, SHOT_DURATION)


func _make_approach(ship: Node3D) -> Callable:
	var dir   := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var start := ship.global_position + dir * randf_range(6.0, 10.0) + Vector3.UP * randf_range(1.0, 2.5)
	var end   := ship.global_position + dir * randf_range(1.0, 2.5)  + Vector3.UP * randf_range(0.3, 1.0)
	return func() -> void:
		_tween = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_tween.tween_method(func(t: float) -> void:
			if not is_instance_valid(ship): return
			_camera.global_position = start.lerp(end, t)
			_safe_look_at(ship.global_position + Vector3.UP * 0.3)
		, 0.0, 1.0, SHOT_DURATION)


func _make_low_pan(ship: Node3D) -> Callable:
	var axis  := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var perp  := axis.cross(Vector3.UP).normalized()
	var h     := randf_range(0.1, 0.5)
	var start := ship.global_position + perp * -2.5 + axis * 0.8 + Vector3.UP * h
	var end   := ship.global_position + perp *  2.5 + axis * 0.8 + Vector3.UP * h
	return func() -> void:
		_tween = create_tween().set_trans(Tween.TRANS_SINE)
		_tween.tween_method(func(t: float) -> void:
			if not is_instance_valid(ship): return
			_camera.global_position = start.lerp(end, t)
			_safe_look_at(ship.global_position + Vector3.UP * 0.15)
		, 0.0, 1.0, SHOT_DURATION)


func _make_side_track(ship: Node3D) -> Callable:
	var fwd    := _ship_forward(ship)
	var side   := fwd.cross(Vector3.UP).normalized() * (1.0 if randf() > 0.5 else -1.0)
	var offset := side * randf_range(1.5, 3.0) + Vector3.UP * randf_range(0.4, 1.2)
	return func() -> void:
		_chase_offset = offset
		_chase_ship   = ship
		_camera.global_position = ship.global_position + offset


func _make_over_shoulder(ship: Node3D) -> Callable:
	var fwd   := _ship_forward(ship)
	var start := ship.global_position - fwd * randf_range(1.0, 2.5) + Vector3.UP * randf_range(0.5, 1.5)
	var end   := start + fwd * randf_range(1.0, 2.0)
	return func() -> void:
		_camera.global_position = start
		_safe_look_at(ship.global_position + fwd * 5.0)
		_tween = create_tween().set_trans(Tween.TRANS_SINE)
		_tween.tween_method(func(t: float) -> void:
			if not is_instance_valid(ship): return
			_camera.global_position = start.lerp(end, t)
			_safe_look_at(ship.global_position + fwd * 5.0 + Vector3.UP * 0.2)
		, 0.0, 1.0, SHOT_DURATION)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _do_cut() -> void:
	_fade_rect.visible = true
	_fade_rect.color   = Color(0, 0, 0, 0.85)
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.25)
	tw.tween_callback(func() -> void: _fade_rect.visible = false)


func _safe_look_at(target: Vector3) -> void:
	var dir := target - _camera.global_position
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP
	if abs(dir.normalized().dot(up)) > 0.98:
		up = Vector3.FORWARD
	_camera.look_at(target, up)


func _get_random_live_boid() -> Boid:
	var pool: Array = []
	for sq in get_tree().get_nodes_in_group("Squads"):
		if sq is StarfighterSquad:
			for b in sq.boids:
				if is_instance_valid(b):
					pool.append(b)
	if pool.is_empty():
		return null
	return pool.pick_random()


func _make_boid_followcam() -> Callable:
	var boid := _get_random_live_boid()
	if not is_instance_valid(boid):
		return Callable()
	return func() -> void:
		# Original boid may have died since the shot was recorded — find a substitute
		var target: Boid = boid if is_instance_valid(boid) else _get_random_live_boid()
		if not is_instance_valid(target):
			return
		_chase_boid = target
		var dir: Vector3 = target._fwd
		_camera.global_position = target.global_position - dir * 0.18 + Vector3.UP * 0.07


func _ship_forward(ship: Node3D) -> Vector3:
	if ship is Ship:
		return Vector3(sin(ship.angle), 0.0, cos(ship.angle))
	return ship.global_basis.z.normalized()
