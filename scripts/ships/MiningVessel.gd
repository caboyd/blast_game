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
## Show a debug overlay (hull, mining point, mined cell outline).
@export var debug_collision_visual: bool = true

var grid: MiningGrid
var _fuel_out_emitted: bool = false
var _mine_accum_time: float = 0.0
## Fractional damage carried over between mining ticks (shared pool for the whole drill area).
var _mine_pending_damage: float = 0.0


func _ready() -> void:
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
		var step := dir.normalized() * move_speed_px_s * delta
		_move_with_collision(step)

	_tick_mining(delta)

	grid.update_vision(_front_world(), vision_radius_cells)

	if GameStatistics.fuel <= 0.0 and not _fuel_out_emitted:
		_fuel_out_emitted = true
		out_of_fuel.emit()

	if debug_collision_visual:
		queue_redraw()


func _draw() -> void:
	if not debug_collision_visual or grid == null:
		return
	# Local space: +X is forward; drill center from scene collider.
	var front_local: Vector2 = (
		to_local(_drill_shape.global_position)
		if _drill_shape
		else (Vector2.RIGHT * mine_radius_px)
	)
	var color_hull: Color = Color(0.35, 0.75, 1.0, 0.85)
	var color_point: Color = Color(1.0, 0.4, 0.4, 0.95)
	var color_cell_solid: Color = Color(1.0, 0.25, 0.25, 0.9)
	var color_cell_empty: Color = Color(0.4, 1.0, 0.5, 0.7)

	# Hull (movement blocker), centered on the vessel.
	draw_arc(Vector2.ZERO, hull_radius_px, 0.0, TAU, 48, color_hull, 1.0, true)

	# Mining point — debug disc matches `CircleShape2D` radius in local space.
	var d_circ: CircleShape2D = _drill_shape.shape as CircleShape2D if _drill_shape else null
	if d_circ:
		var drill_edge_w: Vector2 = _drill_shape.global_transform * Vector2(d_circ.radius, 0.0) - _drill_shape.global_position
		var r_loc: float = (to_local(_drill_shape.global_position + drill_edge_w) - front_local).length()
		draw_circle(front_local, maxf(r_loc, 0.4), color_point)
	else:
		draw_circle(front_local, 1.2, color_point)
	draw_line(Vector2.ZERO, front_local, color_point, 1.0)

	# Outline each grid cell the drill circle overlaps (world AABB test).
	var drill_c: Vector2 = _drill_center_world()
	var r: float = mine_radius_px
	var cs: float = MiningGrid.CELL_SIZE_PX
	var cx0: int = int(floor((drill_c.x - r) / cs))
	var cx1: int = int(floor((drill_c.x + r) / cs))
	var cy0: int = int(floor((drill_c.y - r) / cs))
	var cy1: int = int(floor((drill_c.y + r) / cs))
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_rect(drill_c, r, cx, cy):
				continue
			var ctr := Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)
			var cell: Vector2i = Vector2i(cx, cy)
			var tl_world: Vector2 = Vector2(float(cell.x) * cs, float(cell.y) * cs)
			var tl_local: Vector2 = to_local(tl_world)
			var x_axis: Vector2 = to_local(tl_world + Vector2(cs, 0.0)) - tl_local
			var y_axis: Vector2 = to_local(tl_world + Vector2(0.0, cs)) - tl_local
			var corners: PackedVector2Array = PackedVector2Array([
				tl_local,
				tl_local + x_axis,
				tl_local + x_axis + y_axis,
				tl_local + y_axis,
				tl_local,
			])
			var solid: bool = grid.is_solid_world(ctr)
			var occupied_color: Color = color_cell_solid if solid else color_cell_empty
			for i in range(corners.size() - 1):
				draw_line(corners[i], corners[i + 1], occupied_color, 0.5)


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
	if not grid.has_solid_overlapping_circle_world(drill_c, mine_radius_px):
		_mine_accum_time = 0.0
		return

	_mine_accum_time += delta
	while _mine_accum_time >= mine_interval_s:
		_mine_accum_time -= mine_interval_s
		_mine_pending_damage += mine_damage_per_tick
		var whole: int = int(floor(_mine_pending_damage))
		if whole <= 0:
			continue
		_mine_pending_damage -= float(whole)
		drill_c = _drill_center_world()
		var hp_rm: int = grid.mine_solid_in_circle_world(drill_c, mine_radius_px, whole)
		if hp_rm > 0:
			GameStatistics.consume_fuel(float(hp_rm))
