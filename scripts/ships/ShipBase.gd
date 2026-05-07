class_name ShipBase
extends Node2D

## Physics layer 6 (`mining_ship_pickup`). Monitorable `Area2D` hull mirror so pickup areas get `area_entered`.
const PHYSICS_LAYER_MINING_SHIP_FOR_PICKUPS: int = 1 << 5

## Local +X is forward. Hull + drill use `CircleShape2D` on nodes resolved at runtime
## (`Hull/HullCollider` or `Hull/CollisionShape2D`, `Drill/DrillCollider` or `Drill/CollisionShape2D`).

signal out_of_fuel

const WEAPON_LASER_UPGRADE_ID := &"weapon_laser"
const _LASER_BEAM_FLASH_S := 0.09
const WEAPON_MISSILE_UPGRADE_ID := &"weapon_missile"
## Baseline missile tuning lives in [method ShipDataRegistry.get_weapon_missile_stat_base]; upgraded via `weapon_systems.tres`.
const WEAPON_MISSILE_FLIGHT_TIME_MIN_S := 0.07
const WEAPON_MISSILE_FLIGHT_TIME_MAX_S := 0.32
## Half-angle (rad) in front of the ship; cells outside the cone are not missile targets.
const WEAPON_MISSILE_FIRE_CONE_HALF_ANGLE_RAD: float = 1.222  # ~70°

const WEAPON_BOMB_UPGRADE_ID := &"weapon_bomb"
const WEAPON_CHAIN_LIGHTNING_UPGRADE_ID := &"weapon_chain_lightning"
const _CHAIN_LIGHTNING_FLASH_S := 0.11
const _CHAIN_LIGHTNING_ABS_HOP_CAP := 8

const WEAPON_GRAVITY_PULL_UPGRADE_ID := &"weapon_gravity_pull"
## Gravity Pull — Option A (terrain): [method MiningWorld.mine_solid_in_circle_world] at the ship with empty type filter. Tuning is code constants (first vertical slice).
const _WEAPON_GRAVITY_PULL_COOLDOWN_S := 2.35
const _WEAPON_GRAVITY_PULL_RANGE_GAME_PX := 52.0
const _WEAPON_GRAVITY_PULL_DAMAGE_PER_CELL := 1

const _WeaponBombFxScript = preload("res://scripts/world/WeaponBombFx.gd")

var _hull_shape: CollisionShape2D
var _drill_shape: CollisionShape2D

@export var move_speed_px_s: float = 8.0
@export var turn_rate_rad_s: float = 9.0
@export var vision_radius_cells: int = 3
@export var mine_damage_per_tick: float = 1.0
@export var mine_interval_s: float = 0.2
@export var fuel_drain_per_second: float = 1.0
var hull_radius_px: float = 8.0
var mine_radius_px: float = 2.0
@export var hull_debug_blocked_pad_px: float = 0.15

var grid: MiningWorld
## Cosmetic mission ship chain segments: no mining, fuel drain, movement, vision, or debug overlay.
var follower_visual_only: bool = false
var _base_mine_damage_per_tick: float = 1.0
var _base_move_speed_px_s: float = 8.0
var _base_turn_rate_rad_s: float = 9.0
var _base_vision_radius_cells: int = 3
var _fuel_out_emitted: bool = false
var _mine_accum_time: float = 0.0
var _mine_pending_damage: float = 0.0
var _debug_layer: Node2D

var _tread_cycle_t: float = 0.0
var _tread_stopping: bool = false
var _audio_listener_2d: AudioListener2D

var _laser_cooldown_t: float = 0.0
var _laser_beam_flash_t: float = 0.0
var _laser_beam: Line2D

var _missile_cooldown_t: float = 0.0
var _missile_tracer: Line2D
var _missile_flight_active: bool = false
var _missile_flight_elapsed_s: float = 0.0
var _missile_flight_duration_s: float = 0.0
var _missile_from_world: Vector2 = Vector2.ZERO
var _missile_to_world: Vector2 = Vector2.ZERO
var _missile_impact_world: Vector2 = Vector2.ZERO

var _bomb_cooldown_t: float = 0.0

var _chain_lightning_cooldown_t: float = 0.0
var _chain_lightning_line: Line2D
var _chain_lightning_flash_t: float = 0.0

var _gravity_pull_cooldown_t: float = 0.0


func _ready() -> void:
	if follower_visual_only:
		_ready_follower_visual_only()
		return
	var sd: Resource = ShipDataRegistry.get_active()
	if sd == null:
		push_error("ShipDataRegistry.get_active() returned null")
		return
	move_speed_px_s = float(sd.get("move_speed_px_s"))
	turn_rate_rad_s = float(sd.get("turn_rate_rad_s"))
	vision_radius_cells = int(sd.get("vision_radius_cells"))
	mine_damage_per_tick = float(sd.get("mine_damage_per_tick"))
	mine_interval_s = float(sd.get("mine_interval_s"))
	fuel_drain_per_second = float(sd.get("fuel_drain_per_second"))
	_base_mine_damage_per_tick = mine_damage_per_tick
	_base_move_speed_px_s = move_speed_px_s
	_base_turn_rate_rad_s = turn_rate_rad_s
	_base_vision_radius_cells = vision_radius_cells
	_hull_shape = _find_hull_collider()
	_drill_shape = _find_drill_collider()
	if _hull_shape:
		hull_radius_px = _circle_max_world_radius(_hull_shape, 8.0)
	else:
		push_warning("ShipBase: no hull CollisionShape2D; using hull_radius_px=%s" % hull_radius_px)
	if _drill_shape:
		mine_radius_px = _circle_max_world_radius(_drill_shape, 2.0)
	else:
		push_warning("ShipBase: no drill CollisionShape2D; using mine_radius_px=%s" % mine_radius_px)
	_debug_layer = _MiningDebugLayer.new()
	_debug_layer._ship = self
	_debug_layer.name = "DebugDraw"
	_debug_layer.z_as_relative = true
	_debug_layer.z_index = 10
	add_child(_debug_layer)
	_debug_layer.add_to_group(&"mining_ship")
	_setup_pickup_overlap_area()
	_audio_listener_2d = AudioListener2D.new()
	_audio_listener_2d.name = &"AudioListener2D"
	add_child(_audio_listener_2d)
	_laser_beam = Line2D.new()
	_laser_beam.width = 2.0
	_laser_beam.default_color = Color(0.95, 0.25, 0.55, 0.92)
	_laser_beam.z_index = 6
	_laser_beam.visible = false
	add_child(_laser_beam)
	_missile_tracer = Line2D.new()
	_missile_tracer.width = 3.2
	_missile_tracer.default_color = Color(0.95, 0.55, 0.12, 0.95)
	_missile_tracer.z_index = 5
	_missile_tracer.visible = false
	add_child(_missile_tracer)
	_chain_lightning_line = Line2D.new()
	_chain_lightning_line.width = 2.8
	_chain_lightning_line.default_color = Color(0.22, 0.88, 1.0, 0.94)
	_chain_lightning_line.antialiased = true
	_chain_lightning_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_chain_lightning_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_chain_lightning_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_chain_lightning_line.z_index = 8
	_chain_lightning_line.visible = false
	add_child(_chain_lightning_line)


func _setup_pickup_overlap_area() -> void:
	if _hull_shape == null:
		return
	if get_node_or_null(^"PickupOverlapArea") != null:
		return
	var area := Area2D.new()
	area.name = &"PickupOverlapArea"
	area.collision_layer = PHYSICS_LAYER_MINING_SHIP_FOR_PICKUPS
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	var cs := CollisionShape2D.new()
	cs.shape = _hull_shape.shape
	add_child(area)
	area.add_child(cs)
	cs.global_transform = _hull_shape.global_transform


func _ready_follower_visual_only() -> void:
	set_physics_process(false)
	_hull_shape = _find_hull_collider()
	_drill_shape = _find_drill_collider()
	if _hull_shape:
		hull_radius_px = _circle_max_world_radius(_hull_shape, 8.0)
	else:
		push_warning("ShipBase: follower has no hull CollisionShape2D; using hull_radius_px=%s" % hull_radius_px)
	if _drill_shape:
		mine_radius_px = _circle_max_world_radius(_drill_shape, 2.0)
	else:
		push_warning("ShipBase: follower has no drill CollisionShape2D; using mine_radius_px=%s" % mine_radius_px)


func get_effective_mine_damage_per_tick() -> float:
	if GameStatistics.debug_mine_damage_override_enabled:
		return GameStatistics.debug_mine_damage_override_value
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"mine_damage_per_tick", _base_mine_damage_per_tick
	)
	return PartRegistry.apply_effects_for_stat(&"mine_damage_per_tick", v)


func get_effective_vision_radius_cells() -> int:
	if GameStatistics.debug_vision_radius_cells_override_enabled:
		return GameStatistics.debug_vision_radius_cells_override_value
	return maxi(
		1,
		ShipDataRegistry.apply_effects_for_stat_int(&"vision_radius_cells", _base_vision_radius_cells)
	)


func get_effective_move_speed_px_s() -> float:
	if GameStatistics.debug_move_speed_override_enabled:
		return GameStatistics.debug_move_speed_override_value
	var v: float = ShipDataRegistry.apply_effects_for_stat(&"move_speed_px_s", _base_move_speed_px_s)
	return PartRegistry.apply_effects_for_stat(&"move_speed_px_s", v)


func get_effective_mine_interval_s() -> float:
	if GameStatistics.debug_mine_interval_override_enabled:
		return GameStatistics.debug_mine_interval_override_value
	return mine_interval_s


func get_effective_fuel_drain_per_second() -> float:
	return PartRegistry.apply_effects_for_stat(&"fuel_drain_per_second", fuel_drain_per_second)


func get_effective_turn_rate_rad_s() -> float:
	if GameStatistics.debug_turn_rate_rad_s_override_enabled:
		return GameStatistics.debug_turn_rate_rad_s_override_value
	return maxf(
		0.0,
		ShipDataRegistry.apply_effects_for_stat(&"turn_rate_rad_s", _base_turn_rate_rad_s)
	)


func carve_hull_terrain_on_spawn() -> void:
	if grid == null:
		return
	grid.clear_solid_in_circle_world(position, hull_radius_px)


func _physics_process(delta: float) -> void:
	if grid == null:
		return
	if _audio_listener_2d != null:
		_audio_listener_2d.make_current()
	var mouse := get_global_mouse_position()
	var dir := mouse - global_position
	if dir.length_squared() > 0.0001:
		var target_rot: float = dir.angle()
		var max_turn: float = get_effective_turn_rate_rad_s() * delta
		rotation = rotate_toward(rotation, target_rot, max_turn)
	var tread_move_mult := 1.0
	if not follower_visual_only:
		var ts: PackedFloat32Array = PartRegistry.treads_movement_effect_timing()
		var ev: float = ts[0]
		var du: float = ts[1]
		if ev > 0.0 and du > 0.0:
			_tread_cycle_t += delta
			if not _tread_stopping:
				if _tread_cycle_t >= ev:
					_tread_stopping = true
					_tread_cycle_t = 0.0
			else:
				tread_move_mult = clampf(ts[2], 0.0, 1.0)
				if _tread_cycle_t >= du:
					_tread_stopping = false
					_tread_cycle_t = 0.0
	var step := (
		transform.x.normalized() * get_effective_move_speed_px_s() * delta * tread_move_mult
	)
	_move_with_collision(step)

	_tick_mining(delta)
	_tick_weapon_laser(delta)
	_tick_weapon_missile(delta)
	_tick_weapon_bomb(delta)
	_tick_weapon_gravity_pull(delta)
	_tick_weapon_chain_lightning(delta)

	GameStatistics.consume_fuel(get_effective_fuel_drain_per_second() * delta)

	grid.update_vision(_front_world(), get_effective_vision_radius_cells())

	if GameStatistics.fuel <= 0.0 and not _fuel_out_emitted:
		_fuel_out_emitted = true
		out_of_fuel.emit()

	if GameStatistics.debug_world_visuals and _debug_layer:
		_debug_layer.queue_redraw()


func _draw_mining_debug(ci: CanvasItem) -> void:
	if not GameStatistics.debug_world_visuals or grid == null:
		return
	var front_local: Vector2 = (
		ci.to_local(_drill_shape.global_position)
		if _drill_shape
		else (Vector2.RIGHT * mine_radius_px)
	)
	var color_hull_full: Color = Color(0.2, 0.88, 0.42, 0.42)
	var color_hull_empty: Color = Color(0.25, 0.95, 0.4, 0.88)
	var color_hull_blocked: Color = Color(0.95, 0.2, 0.22, 0.9)
	var color_mine_dot: Color = Color(1.0, 0.12, 0.12, 0.95)
	var color_drill_bearing: Color = Color(1.0, 0.35, 0.35, 0.85)

	var cs: float = MiningWorld.CELL_SIZE_PX
	var hull_c_world: Vector2 = global_position
	var rh: float = hull_radius_px
	var rh_blocked: float = rh + maxf(0.0, hull_debug_blocked_pad_px)

	ci.draw_circle(Vector2.ZERO, hull_radius_px, color_hull_full)

	var out_r: float = maxf(rh, rh_blocked)
	var hcx0: int = int(floor((hull_c_world.x - out_r) / cs))
	var hcx1: int = int(floor((hull_c_world.x + out_r) / cs))
	var hcy0: int = int(floor((hull_c_world.y - out_r) / cs))
	var hcy1: int = int(floor((hull_c_world.y + out_r) / cs))
	for cy in range(hcy0, hcy1 + 1):
		for cx in range(hcx0, hcx1 + 1):
			if not _circle_overlaps_cell_rect(hull_c_world, rh_blocked, cx, cy):
				continue
			var ctr: Vector2 = Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)
			var is_solid: bool = grid.is_solid_world(ctr)
			if is_solid:
				_draw_cell_rect_world_outline(
					ci, Vector2(float(cx) * cs, float(cy) * cs), cs, color_hull_blocked, 0.5
				)
			elif _circle_overlaps_cell_rect(hull_c_world, rh, cx, cy):
				_draw_cell_rect_world_outline(
					ci, Vector2(float(cx) * cs, float(cy) * cs), cs, color_hull_empty, 0.5
				)

	var drill_c: Vector2 = _drill_center_world()
	var r: float = get_effective_drill_world_radius_px()
	var dot_r: float = maxf(0.6, cs * 0.1)
	var cx0: int = int(floor((drill_c.x - r) / cs))
	var cx1: int = int(floor((drill_c.x + r) / cs))
	var cy0: int = int(floor((drill_c.y - r) / cs))
	var cy1: int = int(floor((drill_c.y + r) / cs))
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_rect(drill_c, r, cx, cy):
				continue
			var ctr2: Vector2 = Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)
			if not grid.is_solid_world(ctr2):
				continue
			ci.draw_circle(ci.to_local(ctr2), dot_r, color_mine_dot)

	ci.draw_circle(front_local, maxf(get_debug_drill_draw_radius_px(), 0.4), color_drill_bearing)
	ci.draw_line(Vector2.ZERO, front_local, color_drill_bearing, 1.0)


func _draw_cell_rect_world_outline(
	ci: CanvasItem, tl_world: Vector2, cell_size: float, color: Color, width: float
) -> void:
	_draw_world_rect_outline(ci, tl_world, cell_size, cell_size, color, width)


func _draw_world_rect_outline(
	ci: CanvasItem, tl_world: Vector2, w: float, h: float, color: Color, width: float
) -> void:
	var tl: Vector2 = ci.to_local(tl_world)
	var ax: Vector2 = ci.to_local(tl_world + Vector2(w, 0.0)) - tl
	var ay: Vector2 = ci.to_local(tl_world + Vector2(0.0, h)) - tl
	var c0: Vector2 = tl
	var c1: Vector2 = tl + ax
	var c2: Vector2 = tl + ax + ay
	var c3: Vector2 = tl + ay
	ci.draw_line(c0, c1, color, width)
	ci.draw_line(c1, c2, color, width)
	ci.draw_line(c2, c3, color, width)
	ci.draw_line(c3, c0, color, width)


func _circle_max_world_radius(collision: CollisionShape2D, fallback: float) -> float:
	var circ := collision.shape as CircleShape2D
	if circ == null or circ.radius <= 0.0:
		return fallback
	var r: float = circ.radius
	var t: Transform2D = collision.global_transform
	var ex: float = (t * Vector2(r, 0.0) - t * Vector2.ZERO).length()
	var ey: float = (t * Vector2(0.0, r) - t * Vector2.ZERO).length()
	var world_r: float = maxf(ex, ey)
	if not is_finite(world_r) or world_r <= 0.0:
		return fallback
	return world_r


func get_drill_world_radius_px() -> float:
	if _drill_shape == null:
		return mine_radius_px
	return _circle_max_world_radius(_drill_shape, mine_radius_px)


func _game_to_world_radius_scale() -> float:
	var s: float = maxf(absf(scale.x), absf(scale.y))
	return s if s > 0.0 else 1.0


func get_effective_drill_world_radius_px() -> float:
	return get_effective_drill_game_radius_px() * _game_to_world_radius_scale()


func get_drill_game_radius_px() -> float:
	var w: float = get_drill_world_radius_px()
	var s: float = maxf(absf(scale.x), absf(scale.y))
	if s > 0.0:
		w /= s
	return w


func get_effective_drill_game_radius_px() -> float:
	if GameStatistics.debug_drill_range_game_px_override_enabled:
		return GameStatistics.debug_drill_range_game_px_override_value
	var base_game: float = get_drill_game_radius_px()
	var bonus: float = ShipDataRegistry.apply_effects_for_stat(&"drill_range_bonus_game_px", 0.0)
	return base_game + bonus


func get_debug_drill_draw_radius_px() -> float:
	return get_effective_drill_game_radius_px()


func _front_offset() -> Vector2:
	if _drill_shape:
		return _drill_shape.global_position - global_position
	return Vector2.RIGHT.rotated(rotation) * mine_radius_px


func _find_hull_collider() -> CollisionShape2D:
	for path: String in ["Hull/HullCollider", "Hull/CollisionShape2D"]:
		var c := get_node_or_null(path) as CollisionShape2D
		if c:
			return c
	return null


func _find_drill_collider() -> CollisionShape2D:
	for path: String in ["Drill/DrillCollider", "Drill/CollisionShape2D"]:
		var c := get_node_or_null(path) as CollisionShape2D
		if c:
			return c
	return null


func _front_world() -> Vector2:
	return global_position + _front_offset()


func _drill_center_world() -> Vector2:
	return _front_world()


func get_drill_center_world() -> Vector2:
	return _drill_center_world()


func get_hull_center_world() -> Vector2:
	if _hull_shape:
		return _hull_shape.global_position
	return global_position


func _circle_overlaps_cell_rect(center: Vector2, radius: float, cell_x: int, cell_y: int) -> bool:
	var cs: float = MiningWorld.CELL_SIZE_PX
	var L: float = float(cell_x) * cs
	var T: float = float(cell_y) * cs
	var R: float = L + cs
	var B: float = T + cs
	var px: float = clampf(center.x, L, R)
	var py: float = clampf(center.y, T, B)
	var dx: float = center.x - px
	var dy: float = center.y - py
	return dx * dx + dy * dy <= radius * radius


func _hull_overlaps_solid(center_world: Vector2) -> bool:
	var cs: float = MiningWorld.CELL_SIZE_PX
	var r: float = hull_radius_px
	var cx0: int = int(floor((center_world.x - r) / cs))
	var cx1: int = int(floor((center_world.x + r) / cs))
	var cy0: int = int(floor((center_world.y - r) / cs))
	var cy1: int = int(floor((center_world.y + r) / cs))
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not grid.is_solid_world(Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)):
				continue
			if _circle_overlaps_cell_rect(center_world, r, cx, cy):
				return true
	return false


func _try_move_by(step: Vector2) -> bool:
	if step == Vector2.ZERO:
		return true
	var start: Vector2 = global_position
	var end: Vector2 = start + step
	if not _hull_overlaps_solid(end):
		global_position = end
		return true
	var t_low: float = 0.0
	var t_high: float = 1.0
	for _i in 16:
		var t_mid: float = (t_low + t_high) * 0.5
		if _hull_overlaps_solid(start + step * t_mid):
			t_high = t_mid
		else:
			t_low = t_mid
	if t_low > 1e-5:
		global_position = start + step * t_low
		return true
	return false


func _move_with_collision(step: Vector2) -> void:
	if step == Vector2.ZERO:
		return
	if _try_move_by(step):
		return
	if _try_move_by(Vector2(step.x, 0.0)):
		return
	_try_move_by(Vector2(0.0, step.y))


func _tick_mining(delta: float) -> void:
	var drill_c: Vector2 = _drill_center_world()
	var drill_r: float = get_effective_drill_world_radius_px()
	var biting: bool = grid.has_solid_overlapping_circle_world(drill_c, drill_r)
	AudioManager.set_drilling(true, drill_c, biting)
	if not biting:
		_mine_accum_time = 0.0
		return

	_mine_accum_time += delta
	var interval_s := get_effective_mine_interval_s()
	while _mine_accum_time >= interval_s:
		_mine_accum_time -= interval_s
		_mine_pending_damage += get_effective_mine_damage_per_tick()
		var whole: int = int(floor(_mine_pending_damage))
		if whole <= 0:
			continue
		_mine_pending_damage -= float(whole)
		drill_c = _drill_center_world()
		drill_r = get_effective_drill_world_radius_px()
		var allowed := PartRegistry.get_drill_allowed_mine_type_ids()
		var hp_removed: int = grid.mine_solid_in_circle_world(drill_c, drill_r, whole, allowed)
		if hp_removed > 0:
			AudioManager.play_dirt_mine(drill_c)


func _laser_range_game_px() -> float:
	return ShipDataRegistry.apply_effects_for_stat(
		&"weapon_laser_range_game_px",
		ShipDataRegistry.get_weapon_laser_stat_base(&"weapon_laser_range_game_px")
	)


func _laser_damage_amount() -> int:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_laser_damage",
		ShipDataRegistry.get_weapon_laser_stat_base(&"weapon_laser_damage")
	)
	return maxi(1, int(round(v)))


func _laser_cooldown_s() -> float:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_laser_cooldown_s",
		ShipDataRegistry.get_weapon_laser_stat_base(&"weapon_laser_cooldown_s")
	)
	return maxf(0.05, v)


func _laser_beam_width_game_px() -> float:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_laser_beam_width_game_px",
		ShipDataRegistry.get_weapon_laser_stat_base(&"weapon_laser_beam_width_game_px")
	)
	return maxf(0.5, v)


func _laser_pierce_extra_count() -> int:
	return maxi(
		0,
		ShipDataRegistry.apply_effects_for_stat_int(
			&"weapon_laser_pierce_count",
			int(round(ShipDataRegistry.get_weapon_laser_stat_base(&"weapon_laser_pierce_count")))
		)
	)


func _laser_width_world_radius() -> float:
	return _laser_beam_width_game_px() * 0.5 * _game_to_world_radius_scale()


func _laser_priority_metric(cell: Vector2i) -> float:
	var pri: int = GameSession.weapon_laser_target_priority
	match pri:
		GameSession.WEAPON_LASER_TARGET_HEALTHIEST:
			return float(grid.get_cell_hp_at(cell))
		GameSession.WEAPON_LASER_TARGET_WEAKEST:
			return -float(grid.get_cell_hp_at(cell))
		GameSession.WEAPON_LASER_TARGET_HIGHEST_VALUE:
			var ti: int = grid.get_cell_type_at(cell)
			if ti >= 0 and ti < MiningWorld.TYPE_MONEY.size():
				return float(MiningWorld.TYPE_MONEY[ti])
			return 0.0
		GameSession.WEAPON_LASER_TARGET_HIGHEST_DENSITY:
			return float(_laser_neighbor_solid_count(cell))
		_:
			return float(grid.get_cell_hp_at(cell))


func _laser_neighbor_solid_count(cell: Vector2i) -> int:
	var n: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var o: Vector2i = Vector2i(cell.x + dx, cell.y + dy)
			var ctr: Vector2 = Vector2(
				(float(o.x) + 0.5) * MiningWorld.CELL_SIZE_PX, (float(o.y) + 0.5) * MiningWorld.CELL_SIZE_PX
			)
			if grid.is_solid_world(ctr):
				n += 1
	return n


func _laser_tie_break_prefer(a: Vector2i, b: Vector2i) -> bool:
	var da: float = grid.cell_center_world(a).distance_squared_to(global_position)
	var db: float = grid.cell_center_world(b).distance_squared_to(global_position)
	if da < db:
		return true
	if da > db:
		return false
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


func _laser_cell_preferred_over(a: Vector2i, b: Vector2i) -> bool:
	var ma: float = _laser_priority_metric(a)
	var mb: float = _laser_priority_metric(b)
	if ma > mb + 1e-5:
		return true
	if mb > ma + 1e-5:
		return false
	return _laser_tie_break_prefer(a, b)


func _pick_laser_target_cell() -> Variant:
	return _pick_priority_solid_cell_in_world_radius(_laser_range_world_px())


## Solid cell within `range_world_px` of the ship, using laser prep priority / tie-break (shared with Bomb).
func _pick_priority_solid_cell_in_world_radius(range_world_px: float) -> Variant:
	var center: Vector2 = global_position
	var r: float = range_world_px
	if r <= 0.0 or grid == null:
		return null
	var cs: float = MiningWorld.CELL_SIZE_PX
	var cx0: int = int(floor((center.x - r) / cs))
	var cx1: int = int(floor((center.x + r) / cs))
	var cy0: int = int(floor((center.y - r) / cs))
	var cy1: int = int(floor((center.y + r) / cs))
	var has_best: bool = false
	var best: Vector2i = Vector2i.ZERO
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_rect(center, r, cx, cy):
				continue
			var ctr := Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)
			if not grid.is_solid_world(ctr):
				continue
			var cand: Vector2i = Vector2i(cx, cy)
			if not has_best or _laser_cell_preferred_over(cand, best):
				best = cand
				has_best = true
	if not has_best:
		return null
	return best


func _laser_cells_along_beam(primary: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [primary]
	var extra: int = _laser_pierce_extra_count()
	var dir_world: Vector2 = grid.cell_center_world(primary) - global_position
	if dir_world.length_squared() < 1e-8:
		dir_world = Vector2.RIGHT
	else:
		dir_world = dir_world.normalized()
	var cur: Vector2i = primary
	for _i in extra:
		var nxt: Variant = _laser_next_solid_cell_along_dir(cur, dir_world)
		if nxt == null:
			break
		cur = nxt as Vector2i
		out.append(cur)
	return out


func _laser_next_solid_cell_along_dir(from_cell: Vector2i, dir_world: Vector2) -> Variant:
	var from_ctr: Vector2 = grid.cell_center_world(from_cell)
	var step: float = MiningWorld.CELL_SIZE_PX * 0.92
	var probe: Vector2 = from_ctr + dir_world * step
	var cand: Vector2i = grid.world_pos_to_cell(probe)
	if cand != from_cell and grid.is_solid_world(grid.cell_center_world(cand)):
		return cand
	var d := Vector2i(
		(1 if dir_world.x > 0.25 else (-1 if dir_world.x < -0.25 else 0)),
		(1 if dir_world.y > 0.25 else (-1 if dir_world.y < -0.25 else 0))
	)
	if d == Vector2i.ZERO:
		d = Vector2i(1, 0)
	for _k in 2:
		var try_cell: Vector2i = from_cell + d
		if grid.is_solid_world(grid.cell_center_world(try_cell)):
			return try_cell
		d = Vector2i(-d.y, d.x)
	return null


func _laser_collect_damage_cells(center_cells: Array[Vector2i]) -> Array[Vector2i]:
	var wr: float = _laser_width_world_radius()
	var seen: Dictionary = {}
	var ordered: Array[Vector2i] = []
	for cell in center_cells:
		var ring: Array[Vector2i] = grid.get_mineable_cells_in_circle_world(
			grid.cell_center_world(cell), wr, PackedInt32Array()
		)
		for c in ring:
			if seen.has(c):
				continue
			seen[c] = true
			ordered.append(c)
	return ordered


func _laser_volley_damage_cells(cells: Array[Vector2i]) -> int:
	var dmg: int = _laser_damage_amount()
	var total: int = 0
	for c in cells:
		total += grid.mine_cell_at_world_point(grid.cell_center_world(c), dmg)
	return total


func _laser_range_world_px() -> float:
	return maxf(0.0, _laser_range_game_px()) * _game_to_world_radius_scale()


func _flash_laser_beam(target_world: Vector2) -> void:
	if _laser_beam == null:
		return
	_laser_beam.width = maxf(1.0, _laser_beam_width_game_px() * _game_to_world_radius_scale())
	_laser_beam.clear_points()
	_laser_beam.add_point(Vector2.ZERO)
	_laser_beam.add_point(to_local(target_world))
	_laser_beam.visible = true
	_laser_beam_flash_t = _LASER_BEAM_FLASH_S


func _missile_range_game_px() -> float:
	return maxf(
		0.0,
		ShipDataRegistry.apply_effects_for_stat(
			&"weapon_missile_range_game_px",
			ShipDataRegistry.get_weapon_missile_stat_base(&"weapon_missile_range_game_px")
		)
	)


func _missile_damage_amount() -> int:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_missile_damage",
		ShipDataRegistry.get_weapon_missile_stat_base(&"weapon_missile_damage")
	)
	return maxi(1, int(round(v)))


func _missile_cooldown_s() -> float:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_missile_cooldown_s",
		ShipDataRegistry.get_weapon_missile_stat_base(&"weapon_missile_cooldown_s")
	)
	return maxf(0.05, v)


func _missile_travel_speed_game_px_s() -> float:
	return maxf(
		1.0,
		ShipDataRegistry.apply_effects_for_stat(
			&"weapon_missile_travel_speed_game_px_s",
			ShipDataRegistry.get_weapon_missile_stat_base(&"weapon_missile_travel_speed_game_px_s")
		)
	)


func _missile_range_world_px() -> float:
	return _missile_range_game_px() * _game_to_world_radius_scale()


func _missile_travel_speed_world_px_s() -> float:
	return _missile_travel_speed_game_px_s() * _game_to_world_radius_scale()


func _missile_forward_world() -> Vector2:
	var d: Vector2 = transform.x
	if d.length_squared() < 1e-8:
		return Vector2.RIGHT
	return d.normalized()


func _pick_missile_target_cell() -> Variant:
	var center: Vector2 = global_position
	var r: float = _missile_range_world_px()
	if r <= 0.0 or grid == null:
		return null
	var fwd: Vector2 = _missile_forward_world()
	var cs: float = MiningWorld.CELL_SIZE_PX
	var cx0: int = int(floor((center.x - r) / cs))
	var cx1: int = int(floor((center.x + r) / cs))
	var cy0: int = int(floor((center.y - r) / cs))
	var cy1: int = int(floor((center.y + r) / cs))
	var has_best: bool = false
	var best: Vector2i = Vector2i.ZERO
	var best_d2: float = 0.0
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_rect(center, r, cx, cy):
				continue
			var ctr := Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)
			if not grid.is_solid_world(ctr):
				continue
			var to_c: Vector2 = ctr - center
			var d2: float = to_c.length_squared()
			if d2 < 1e-8:
				continue
			var ang: float = fwd.angle_to(to_c)
			if absf(ang) > WEAPON_MISSILE_FIRE_CONE_HALF_ANGLE_RAD:
				continue
			if not has_best or d2 < best_d2:
				best = Vector2i(cx, cy)
				best_d2 = d2
				has_best = true
	if not has_best:
		return null
	return best


func _missile_finish_flight() -> void:
	_missile_flight_active = false
	if _missile_tracer != null:
		_missile_tracer.visible = false
	var w: Vector2 = _missile_impact_world
	var removed: int = grid.mine_cell_at_world_point(w, _missile_damage_amount())
	if removed > 0:
		AudioManager.play_dirt_mine(w)


func _tick_weapon_missile(delta: float) -> void:
	if follower_visual_only or grid == null:
		return
	if UpgradeBus.get_level(WEAPON_MISSILE_UPGRADE_ID) < 1:
		return
	if _missile_flight_active:
		_missile_flight_elapsed_s += delta
		var u: float = clampf(_missile_flight_elapsed_s / _missile_flight_duration_s, 0.0, 1.0)
		var head_world: Vector2 = _missile_from_world.lerp(_missile_to_world, u)
		if _missile_tracer != null:
			_missile_tracer.clear_points()
			_missile_tracer.add_point(to_local(_missile_from_world))
			_missile_tracer.add_point(to_local(head_world))
			_missile_tracer.default_color.a = lerpf(0.55, 1.0, u)
			_missile_tracer.visible = true
		if _missile_flight_elapsed_s >= _missile_flight_duration_s:
			_missile_finish_flight()
		return
	_missile_cooldown_t -= delta
	if _missile_cooldown_t > 0.0:
		return
	_missile_cooldown_t = _missile_cooldown_s()
	var target: Variant = _pick_missile_target_cell()
	if target == null:
		return
	var cell: Vector2i = target as Vector2i
	_missile_impact_world = grid.cell_center_world(cell)
	_missile_from_world = _front_world()
	var dist: float = _missile_from_world.distance_to(_missile_impact_world)
	var spd: float = _missile_travel_speed_world_px_s()
	var dur: float = dist / spd
	dur = clampf(dur, WEAPON_MISSILE_FLIGHT_TIME_MIN_S, WEAPON_MISSILE_FLIGHT_TIME_MAX_S)
	_missile_flight_duration_s = dur
	_missile_flight_elapsed_s = 0.0
	_missile_to_world = _missile_impact_world
	_missile_flight_active = true


func _tick_weapon_laser(delta: float) -> void:
	if follower_visual_only or grid == null:
		return
	if _laser_beam != null and _laser_beam.visible:
		_laser_beam_flash_t -= delta
		if _laser_beam_flash_t <= 0.0:
			_laser_beam.visible = false
	if UpgradeBus.get_level(WEAPON_LASER_UPGRADE_ID) < 1:
		return
	_laser_cooldown_t -= delta
	if _laser_cooldown_t > 0.0:
		return
	_laser_cooldown_t = _laser_cooldown_s()
	var primary: Variant = _pick_laser_target_cell()
	if primary == null:
		return
	var beam_world: Vector2 = grid.cell_center_world(primary as Vector2i)
	var beam_centers: Array[Vector2i] = _laser_cells_along_beam(primary as Vector2i)
	var to_damage: Array[Vector2i] = _laser_collect_damage_cells(beam_centers)
	var removed: int = _laser_volley_damage_cells(to_damage)
	if removed > 0:
		AudioManager.play_dirt_mine(beam_world)
	_flash_laser_beam(beam_world)


func _chain_lightning_range_game_px() -> float:
	return ShipDataRegistry.apply_effects_for_stat(
		&"weapon_chain_lightning_range_game_px",
		ShipDataRegistry.get_weapon_chain_lightning_stat_base(&"weapon_chain_lightning_range_game_px")
	)


func _chain_lightning_damage_primary() -> int:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_chain_lightning_damage",
		ShipDataRegistry.get_weapon_chain_lightning_stat_base(&"weapon_chain_lightning_damage")
	)
	return maxi(1, int(round(v)))


func _chain_lightning_cooldown_s() -> float:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_chain_lightning_cooldown_s",
		ShipDataRegistry.get_weapon_chain_lightning_stat_base(&"weapon_chain_lightning_cooldown_s")
	)
	return maxf(0.08, v)


func _chain_lightning_max_extra_chains_runtime() -> int:
	var v: int = ShipDataRegistry.apply_effects_for_stat_int(
		&"weapon_chain_lightning_max_extra_chains",
		int(round(ShipDataRegistry.get_weapon_chain_lightning_stat_base(&"weapon_chain_lightning_max_extra_chains")))
	)
	return mini(_CHAIN_LIGHTNING_ABS_HOP_CAP, maxi(0, v))


func _chain_lightning_arc_radius_cells() -> int:
	return maxi(
		1,
		ShipDataRegistry.apply_effects_for_stat_int(
			&"weapon_chain_lightning_arc_radius_cells",
			int(round(ShipDataRegistry.get_weapon_chain_lightning_stat_base(&"weapon_chain_lightning_arc_radius_cells")))
		)
	)


func _chain_lightning_hop_damage_ratio() -> float:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_chain_lightning_chain_damage_multiplier",
		ShipDataRegistry.get_weapon_chain_lightning_stat_base(&"weapon_chain_lightning_chain_damage_multiplier")
	)
	return clampf(v, 0.12, 0.99)


func _chain_lightning_range_world_px() -> float:
	return maxf(0.0, _chain_lightning_range_game_px()) * _game_to_world_radius_scale()


func _pick_chain_lightning_primary_cell() -> Variant:
	var center: Vector2 = global_position
	var r: float = _chain_lightning_range_world_px()
	if r <= 0.0 or grid == null:
		return null
	var cs: float = MiningWorld.CELL_SIZE_PX
	var cx0: int = int(floor((center.x - r) / cs))
	var cx1: int = int(floor((center.x + r) / cs))
	var cy0: int = int(floor((center.y - r) / cs))
	var cy1: int = int(floor((center.y + r) / cs))
	var has_best: bool = false
	var best: Vector2i = Vector2i.ZERO
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_rect(center, r, cx, cy):
				continue
			var ctr := Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)
			if not grid.is_solid_world(ctr):
				continue
			var cand: Vector2i = Vector2i(cx, cy)
			if not has_best or _laser_cell_preferred_over(cand, best):
				best = cand
				has_best = true
	if not has_best:
		return null
	return best


func _pick_chain_lightning_next_cell(from_cell: Vector2i, visited: Dictionary) -> Variant:
	var r_cells: int = _chain_lightning_arc_radius_cells()
	var has_best: bool = false
	var best: Vector2i = Vector2i.ZERO
	for dy in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			if dx == 0 and dy == 0:
				continue
			if maxi(abs(dx), abs(dy)) > r_cells:
				continue
			var cand: Vector2i = Vector2i(from_cell.x + dx, from_cell.y + dy)
			if visited.has(cand):
				continue
			if not grid.is_solid_world(grid.cell_center_world(cand)):
				continue
			if not has_best or _laser_cell_preferred_over(cand, best):
				best = cand
				has_best = true
	if not has_best:
		return null
	return best


func _flash_chain_lightning_path_world(world_points: PackedVector2Array) -> void:
	if _chain_lightning_line == null or world_points.is_empty():
		return
	_chain_lightning_line.clear_points()
	var prev_local: Vector2 = to_local(world_points[0])
	_chain_lightning_line.add_point(prev_local)
	for i in range(1, world_points.size()):
		var next_local: Vector2 = to_local(world_points[i])
		var mid: Vector2 = (prev_local + next_local) * 0.5
		var seg: Vector2 = next_local - prev_local
		var perp: Vector2 = Vector2(-seg.y, seg.x)
		if perp.length_squared() > 1e-4:
			perp = perp.normalized() * minf(6.0, seg.length() * 0.25)
		else:
			perp = Vector2.ZERO
		if (i & 1) == 1:
			perp = -perp
		_chain_lightning_line.add_point(mid + perp)
		_chain_lightning_line.add_point(next_local)
		prev_local = next_local
	_chain_lightning_line.width = maxf(2.0, 2.6 * _game_to_world_radius_scale())
	_chain_lightning_line.visible = true
	_chain_lightning_flash_t = _CHAIN_LIGHTNING_FLASH_S


func _tick_weapon_chain_lightning(delta: float) -> void:
	if follower_visual_only or grid == null:
		return
	if _chain_lightning_line != null and _chain_lightning_line.visible:
		_chain_lightning_flash_t -= delta
		if _chain_lightning_flash_t <= 0.0:
			_chain_lightning_line.visible = false
	if UpgradeBus.get_level(WEAPON_CHAIN_LIGHTNING_UPGRADE_ID) < 1:
		return
	_chain_lightning_cooldown_t -= delta
	if _chain_lightning_cooldown_t > 0.0:
		return
	_chain_lightning_cooldown_t = _chain_lightning_cooldown_s()
	var primary: Variant = _pick_chain_lightning_primary_cell()
	if primary == null:
		return
	var pcell: Vector2i = primary as Vector2i
	var visited: Dictionary = {}
	visited[pcell] = true
	var path_world: PackedVector2Array = PackedVector2Array()
	path_world.append(global_position)
	path_world.append(grid.cell_center_world(pcell))
	var d0: int = _chain_lightning_damage_primary()
	var removed_total: int = grid.mine_cell_at_world_point(grid.cell_center_world(pcell), d0)
	var mult: float = _chain_lightning_hop_damage_ratio()
	var hop_dmg: int = maxi(1, int(round(float(d0) * mult)))
	var from_cell: Vector2i = pcell
	var extra_cap: int = _chain_lightning_max_extra_chains_runtime()
	for _i in range(extra_cap):
		var nxt: Variant = _pick_chain_lightning_next_cell(from_cell, visited)
		if nxt == null:
			break
		var nc: Vector2i = nxt as Vector2i
		visited[nc] = true
		path_world.append(grid.cell_center_world(nc))
		removed_total += grid.mine_cell_at_world_point(grid.cell_center_world(nc), hop_dmg)
		hop_dmg = maxi(1, int(round(float(hop_dmg) * mult)))
		from_cell = nc
	if removed_total > 0:
		AudioManager.play_dirt_mine(grid.cell_center_world(pcell))
	_flash_chain_lightning_path_world(path_world)


func _bomb_range_game_px() -> float:
	return ShipDataRegistry.apply_effects_for_stat(
		&"weapon_bomb_range_game_px",
		ShipDataRegistry.get_weapon_bomb_stat_base(&"weapon_bomb_range_game_px")
	)


func _bomb_blast_radius_game_px() -> float:
	return ShipDataRegistry.apply_effects_for_stat(
		&"weapon_bomb_blast_radius_game_px",
		ShipDataRegistry.get_weapon_bomb_stat_base(&"weapon_bomb_blast_radius_game_px")
	)


func _bomb_cooldown_s() -> float:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_bomb_cooldown_s",
		ShipDataRegistry.get_weapon_bomb_stat_base(&"weapon_bomb_cooldown_s")
	)
	return maxf(0.05, v)


func _bomb_damage_per_cell() -> int:
	var v: float = ShipDataRegistry.apply_effects_for_stat(
		&"weapon_bomb_damage",
		ShipDataRegistry.get_weapon_bomb_stat_base(&"weapon_bomb_damage")
	)
	return maxi(1, int(round(v)))


func _bomb_range_world_px() -> float:
	return maxf(0.0, _bomb_range_game_px()) * _game_to_world_radius_scale()


func _bomb_blast_radius_world_px() -> float:
	return maxf(0.0, _bomb_blast_radius_game_px()) * _game_to_world_radius_scale()


func _spawn_bomb_fx(world_center: Vector2, blast_radius_world: float) -> void:
	if grid == null:
		return
	var fx: Node = _WeaponBombFxScript.new()
	grid.add_child(fx)
	(fx as Node2D).global_position = world_center
	if fx.has_method(&"setup"):
		fx.call(&"setup", blast_radius_world)


func _tick_weapon_bomb(delta: float) -> void:
	if follower_visual_only or grid == null:
		return
	if UpgradeBus.get_level(WEAPON_BOMB_UPGRADE_ID) < 1:
		return
	_bomb_cooldown_t -= delta
	if _bomb_cooldown_t > 0.0:
		return
	_bomb_cooldown_t = _bomb_cooldown_s()
	var epicenter: Variant = _pick_priority_solid_cell_in_world_radius(_bomb_range_world_px())
	if epicenter == null:
		return
	var epicenter_world: Vector2 = grid.cell_center_world(epicenter as Vector2i)
	var blast_r: float = _bomb_blast_radius_world_px()
	var dmg: int = _bomb_damage_per_cell()
	var removed: int = grid.mine_solid_in_circle_world(
		epicenter_world, blast_r, dmg, PackedInt32Array()
	)
	_spawn_bomb_fx(epicenter_world, blast_r)
	if removed > 0:
		AudioManager.play_dirt_mine(epicenter_world)


func _gravity_pull_radius_world_px() -> float:
	return maxf(0.0, _WEAPON_GRAVITY_PULL_RANGE_GAME_PX) * _game_to_world_radius_scale()


func _tick_weapon_gravity_pull(delta: float) -> void:
	if follower_visual_only or grid == null:
		return
	if UpgradeBus.get_level(WEAPON_GRAVITY_PULL_UPGRADE_ID) < 1:
		return
	_gravity_pull_cooldown_t -= delta
	if _gravity_pull_cooldown_t > 0.0:
		return
	_gravity_pull_cooldown_t = maxf(0.05, _WEAPON_GRAVITY_PULL_COOLDOWN_S)
	var r: float = _gravity_pull_radius_world_px()
	if r <= 0.0:
		return
	var dmg: int = maxi(1, _WEAPON_GRAVITY_PULL_DAMAGE_PER_CELL)
	var removed: int = grid.mine_solid_in_circle_world(
		global_position, r, dmg, PackedInt32Array()
	)
	if removed > 0:
		AudioManager.play_dirt_mine(global_position)


class _MiningDebugLayer extends Node2D:
	var _ship: ShipBase

	func _draw() -> void:
		if _ship:
			_ship._draw_mining_debug(self)
