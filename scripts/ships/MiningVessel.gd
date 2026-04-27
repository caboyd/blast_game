class_name MiningVessel
extends Node2D

## Local +X is forward. Hull + drill use `CircleShape2D` on nodes resolved at runtime
## (`Hull/HullCollider` or `Hull/CollisionShape2D`, `Drill/DrillCollider` or `Drill/CollisionShape2D`).

signal out_of_fuel

var _hull_shape: CollisionShape2D
var _drill_shape: CollisionShape2D

@export var move_speed_px_s: float = 8.0
@export var vision_radius_cells: int = 3
## Mining power: damage applied each tick while colliding with a solid cell. Fractional values accumulate.
@export var mine_damage_per_tick: float = 1.0
## Seconds between mining ticks while colliding with a cell.
@export var mine_interval_s: float = 0.2
## World-radius of `Hull` circle shape (set in `_ready` from the collider).
var hull_radius_px: float = 8.0
## World-radius of `Drill` circle shape (debug draw / keeps export compat if read elsewhere).
var mine_radius_px: float = 2.0
## Wider than real hull: solid cells in this band are drawn red as “blocked / attempting entry.”
## Real collision never lets the hull disk overlap those tiles, so a tiny pad is needed to see them.
@export var hull_debug_blocked_pad_px: float = 0.15

var grid: MiningGrid
## Scene default before `mining_power` career upgrades; effective damage adds `GameStatistics` bonus per level.
var _base_mine_damage_per_tick: float = 1.0
var _base_move_speed_px_s: float = 8.0
var _base_vision_radius_cells: int = 3
var _fuel_out_emitted: bool = false
var _mine_accum_time: float = 0.0
## Fractional damage carried over between mining ticks (shared pool for the whole drill area).
var _mine_pending_damage: float = 0.0
var _debug_layer: Node2D


func _ready() -> void:
	var vd: Resource = VesselDataRegistry.get_active()
	if vd != null:
		move_speed_px_s = float(vd.get("move_speed_px_s"))
		vision_radius_cells = int(vd.get("vision_radius_cells"))
		mine_damage_per_tick = float(vd.get("mine_damage_per_tick"))
		mine_interval_s = float(vd.get("mine_interval_s"))
	_base_mine_damage_per_tick = mine_damage_per_tick
	_base_move_speed_px_s = move_speed_px_s
	_base_vision_radius_cells = vision_radius_cells
	_hull_shape = _find_hull_collider()
	_drill_shape = _find_drill_collider()
	if _hull_shape:
		hull_radius_px = _circle_max_world_radius(_hull_shape, 8.0)
	else:
		push_warning("MiningVessel: no hull CollisionShape2D; using hull_radius_px=%s" % hull_radius_px)
	if _drill_shape:
		mine_radius_px = _circle_max_world_radius(_drill_shape, 2.0)
	else:
		push_warning("MiningVessel: no drill CollisionShape2D; using mine_radius_px=%s" % mine_radius_px)
	_debug_layer = _MiningDebugLayer.new()
	_debug_layer._vessel = self
	_debug_layer.name = "DebugDraw"
	_debug_layer.z_as_relative = true
	# Above Hull/Drill art (e.g. Drill may use z_index 1 on that subtree).
	_debug_layer.z_index = 10
	add_child(_debug_layer)
	_debug_layer.add_to_group(&"mining_vessel")


func get_effective_mine_damage_per_tick() -> float:
	return VesselDataRegistry.apply_effects_for_stat(&"mine_damage_per_tick", _base_mine_damage_per_tick)


func get_effective_vision_radius_cells() -> int:
	return maxi(
		1,
		VesselDataRegistry.apply_effects_for_stat_int(&"vision_radius_cells", _base_vision_radius_cells)
	)


func get_effective_move_speed_px_s() -> float:
	return VesselDataRegistry.apply_effects_for_stat(&"move_speed_px_s", _base_move_speed_px_s)


## Same circle as movement (`hull_radius_px` at `global_position`). Call once after `grid` is set (stage start).
func carve_hull_terrain_on_spawn() -> void:
	if grid == null:
		return
	grid.clear_solid_in_circle_world(global_position, hull_radius_px)


func _physics_process(delta: float) -> void:
	if grid == null:
		return
	var mouse := get_global_mouse_position()
	var dir := mouse - global_position
	if dir.length_squared() > 0.0001:
		rotation = dir.angle()
		var step := dir.normalized() * get_effective_move_speed_px_s() * delta
		_move_with_collision(step)

	_tick_mining(delta)

	grid.update_vision(_front_world(), get_effective_vision_radius_cells())

	if GameStatistics.fuel <= 0.0 and not _fuel_out_emitted:
		_fuel_out_emitted = true
		out_of_fuel.emit()

	if GameStatistics.debug_world_visuals and _debug_layer:
		_debug_layer.queue_redraw()


func _draw_mining_debug(ci: CanvasItem) -> void:
	if not GameStatistics.debug_world_visuals or grid == null:
		return
	# Local space: +X is forward; drill center from scene collider.
	var front_local: Vector2 = (
		ci.to_local(_drill_shape.global_position)
		if _drill_shape
		else (Vector2.RIGHT * mine_radius_px)
	)
	# Hull collider footprint (matches `hull_radius_px`).
	var color_hull_full: Color = Color(0.2, 0.88, 0.42, 0.42)
	# Grid: empty cells under hull (light green outline). Solid = blocked (red).
	var color_hull_empty: Color = Color(0.25, 0.95, 0.4, 0.88)
	var color_hull_blocked: Color = Color(0.95, 0.2, 0.22, 0.9)
	var color_mine_dot: Color = Color(1.0, 0.12, 0.12, 0.95)
	var color_drill_bearing: Color = Color(1.0, 0.35, 0.35, 0.85)
	var color_chunk_border: Color = Color(0.3, 0.65, 1.0, 0.88)

	var cs: float = MiningGrid.CELL_SIZE_PX
	var chunk_px: float = float(MiningGrid.CHUNK_SIZE) * cs
	var origin_chunk: Vector2i = grid.get_chunk_for_world_pos(global_position)
	const _CHUNK_BORDERS_HALF: int = 4
	for dcy in range(-_CHUNK_BORDERS_HALF, _CHUNK_BORDERS_HALF + 1):
		for dcx in range(-_CHUNK_BORDERS_HALF, _CHUNK_BORDERS_HALF + 1):
			var cchunk: Vector2i = origin_chunk + Vector2i(dcx, dcy)
			var tlx: float = float(cchunk.x * MiningGrid.CHUNK_SIZE) * cs
			var tly: float = float(cchunk.y * MiningGrid.CHUNK_SIZE) * cs
			_draw_world_rect_outline(
				ci, Vector2(tlx, tly), chunk_px, chunk_px, color_chunk_border, 1.0
			)
	var hull_c_world: Vector2 = global_position
	var rh: float = hull_radius_px
	var rh_blocked: float = rh + maxf(0.0, hull_debug_blocked_pad_px)

	# Hull reference (true collider, green disk).
	ci.draw_circle(Vector2.ZERO, hull_radius_px, color_hull_full)

	# Inner = actual hull. Outer = inner + pad: collision stops before the hull ever overlaps
	# most blocking tiles, so red uses the outer circle to mark solids we are pressed against.
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

	# Drill: small red dots on solid cells in the mining footprint.
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


## Max world-space distance from the shape's pivot (covers non-uniform scale on the `CollisionShape2D` chain).
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


## World-space drill radius from the live collider (shape + `global_transform` includes this node’s scale).
func get_drill_world_radius_px() -> float:
	if _drill_shape == null:
		return mine_radius_px
	return _circle_max_world_radius(_drill_shape, mine_radius_px)


func _game_to_world_radius_scale() -> float:
	var s: float = maxf(absf(scale.x), absf(scale.y))
	return s if s > 0.0 else 1.0


func get_effective_drill_world_radius_px() -> float:
	return get_effective_drill_game_radius_px() * _game_to_world_radius_scale()


## Radius in the same **game** space as `MiningGrid` (cell = `CELL_SIZE_PX` px), i.e. with this
## vessel’s `scale` factored out. Use for prep UI when the instance is zoom-scaled; avoids huge `world_r`.
func get_drill_game_radius_px() -> float:
	var w: float = get_drill_world_radius_px()
	var s: float = maxf(absf(scale.x), absf(scale.y))
	if s > 0.0:
		w /= s
	return w


func get_effective_drill_game_radius_px() -> float:
	var base_game: float = get_drill_game_radius_px()
	var bonus: float = VesselDataRegistry.apply_effects_for_stat(&"drill_range_bonus_game_px", 0.0)
	return base_game + bonus


func get_debug_drill_draw_radius_px() -> float:
	return get_effective_drill_game_radius_px()


## World offset from this node's origin to the drill (mining sample point).
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


## World-space position of the ship's front tip (mining sample only).
func _front_world() -> Vector2:
	return global_position + _front_offset()


## Drill circle center in world (matches `CollisionShape2D` / `mine_radius_px`).
func _drill_center_world() -> Vector2:
	return _front_world()


func _circle_overlaps_cell_rect(center: Vector2, radius: float, cell_x: int, cell_y: int) -> bool:
	var cs: float = MiningGrid.CELL_SIZE_PX
	var L: float = float(cell_x) * cs
	var T: float = float(cell_y) * cs
	var R: float = L + cs
	var B: float = T + cs
	var px: float = clampf(center.x, L, R)
	var py: float = clampf(center.y, T, B)
	var dx: float = center.x - px
	var dy: float = center.y - py
	return dx * dx + dy * dy <= radius * radius


## True if the hull circle at `center_world` intersects any solid grid cell.
func _hull_overlaps_solid(center_world: Vector2) -> bool:
	var cs: float = MiningGrid.CELL_SIZE_PX
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


## Hull circle at the vessel origin cannot overlap solid cells. Try full step, then axis slides.
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
	if not grid.has_solid_overlapping_circle_world(drill_c, drill_r):
		_mine_accum_time = 0.0
		return

	_mine_accum_time += delta
	while _mine_accum_time >= mine_interval_s:
		_mine_accum_time -= mine_interval_s
		_mine_pending_damage += get_effective_mine_damage_per_tick()
		var whole: int = int(floor(_mine_pending_damage))
		if whole <= 0:
			continue
		_mine_pending_damage -= float(whole)
		drill_c = _drill_center_world()
		drill_r = get_effective_drill_world_radius_px()
		var hp_rm: int = grid.mine_solid_in_circle_world(drill_c, drill_r, whole)
		if hp_rm > 0:
			GameStatistics.consume_fuel(float(hp_rm))


class _MiningDebugLayer extends Node2D:
	var _vessel: MiningVessel

	func _draw() -> void:
		if _vessel:
			_vessel._draw_mining_debug(self)
