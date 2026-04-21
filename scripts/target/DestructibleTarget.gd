class_name DestructibleTarget
extends Node2D

signal fully_destroyed

const TYPE_EMPTY := 0
const TYPE_ROCK := 1
const TYPE_GOLD := 2
const TYPE_COUNT := 3

## Not const: Packed* constructors are not compile-time constants in GDScript.
static var TYPE_MAX_HP: PackedInt32Array = PackedInt32Array([0, 5, 50])
## Money granted when a cell of this type is fully destroyed (index = type id).
static var TYPE_MONEY: PackedInt32Array = PackedInt32Array([0, 1, 15])
static var TYPE_COLOR: PackedColorArray = PackedColorArray([
	Color(0.0, 0.0, 0.0, 0.0),
	Color(0.55, 0.55, 0.58, 1.0),
	Color(1.0, 0.82, 0.2, 1.0),
])

const SHADER_TYPE_COLOR_MAX := 8
## Extra mask columns on left/right so marching shader sees real neighbor cells at seams (not clamped edge).
const APRON_COLUMNS := 1

@export var target_size_px: Vector2 = Vector2(640.0, 360.0)
@export var cell_size_px: float = 8.0
@export var fill_solid_on_reset: bool = true

@export var generation_mode: StringName = &"default"
@export var gold_density: float = 0.015
@export var gold_cluster_size: int = 3
@export var generation_seed: int = 0

@export var debug_destroy_on_key: bool = true
@export var debug_destroy_key: Key = KEY_K
@export var debug_damage_on_click: bool = true

var _destroyed: bool = false
var _mouse_held: bool = false
## Seconds banked toward the next allowed click shot (shared by manual press + hold).
var _click_fire_time_bank_s: float = 0.0
var _click_pending_edge: bool = false
var _pending_press_local: Vector2 = Vector2.ZERO

var _grid_w: int = 0
var _grid_h: int = 0
## Per cell: type id (0 = empty).
var _cells: PackedByteArray
var _cell_hp: PackedByteArray

var _leftmost_solid_cell_x: int = 0
var _leftmost_solid_dirty: bool = true

var _mask_image: Image
var _mask_texture: ImageTexture
var _type_image: Image
var _type_texture: ImageTexture
var _mask_dirty: bool = true

## Per row: grid X of leftmost solid cell, or -1. _row_leftmost_pos_local[y] = cell center in local space (invalid if x < 0).
var _row_leftmost_x: PackedInt32Array = PackedInt32Array()
var _row_leftmost_pos_local: PackedVector2Array = PackedVector2Array()
var _row_leftmost_cache_dirty: bool = true

## Adjacent slabs (same cell_size_px / grid height). Used only to fill apron columns on mask textures.
var _left_neighbor: DestructibleTarget
var _right_neighbor: DestructibleTarget

@onready var _visual: Sprite2D = $Visual


func is_destroyed() -> bool:
	return _destroyed


func set_target_visible(v: bool) -> void:
	if _visual != null:
		_visual.visible = v


func reset_target() -> void:
	_destroyed = false
	if _visual != null:
		_visual.visible = true
	_init_grid()
	_init_mask_visuals()
	_try_mark_destroyed()
	_leftmost_solid_dirty = true
	_row_leftmost_cache_dirty = true
	if not _destroyed:
		_invalidate_mask_and_neighbor_seams()
	_click_fire_time_bank_s = _click_interval_s()
	_click_pending_edge = false


func apply_damage_circle_local(
	local_pos: Vector2,
	radius_px: float,
	amount: int = 9999,
	damage_source: StringName = GameStatistics.DAMAGE_SOURCE_CLICK
) -> void:
	if _destroyed:
		return

	var r_cells := int(ceil(radius_px / cell_size_px))
	var center := _local_to_cell(local_pos)

	var changed_any := false
	var destroyed_count := 0
	var damage_batch := 0
	var money_batch := 0
	for dy in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			if dx * dx + dy * dy > r_cells * r_cells:
				continue
			var cx := center.x + dx
			var cy := center.y + dy
			if cx < 0 or cy < 0 or cx >= _grid_w or cy >= _grid_h:
				continue
			var idx := cy * _grid_w + cx
			if _cells[idx] == TYPE_EMPTY:
				continue
			var old_type := int(_cells[idx])
			var dres := _damage_cell_idx(idx, amount)
			var code := dres.x
			var hp_rm := dres.y
			if hp_rm > 0:
				damage_batch += hp_rm
			if code > 0:
				changed_any = true
			if code == 2:
				destroyed_count += 1
				if old_type >= 0 and old_type < TYPE_MONEY.size():
					money_batch += int(TYPE_MONEY[old_type])

	if destroyed_count > 0:
		GameStatistics.add_blocks_destroyed(destroyed_count)
	if money_batch > 0:
		GameStatistics.add_money(money_batch)
	if damage_batch > 0:
		GameStatistics.add_block_damage(damage_batch, damage_source)

	if changed_any:
		_try_mark_destroyed()
		_leftmost_solid_dirty = true
		_row_leftmost_cache_dirty = true
		if not _destroyed:
			_invalidate_mask_and_neighbor_seams()


## True if any solid cell lies inside a circle (local space) of given radius. Cell-space disk test.
func overlaps_solid_circle_local(local_pos: Vector2, radius_px: float) -> bool:
	if _destroyed:
		return false
	var r_cells := int(ceil(radius_px / cell_size_px))
	var center := _local_to_cell(local_pos)
	var r2 := r_cells * r_cells
	for dy in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			if dx * dx + dy * dy > r2:
				continue
			var cx := center.x + dx
			var cy := center.y + dy
			if cx < 0 or cy < 0 or cx >= _grid_w or cy >= _grid_h:
				continue
			if _cells[cy * _grid_w + cx] != TYPE_EMPTY:
				return true
	return false


## Returns true if the cell became empty (destroyed) this tick.
func apply_damage_cell(
	cell: Vector2i,
	amount: int,
	damage_source: StringName = GameStatistics.DAMAGE_SOURCE_LASER_TURRET
) -> bool:
	if _destroyed:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_w or cell.y >= _grid_h:
		return false
	var idx := cell.y * _grid_w + cell.x
	if _cells[idx] == TYPE_EMPTY:
		return false
	var old_type := int(_cells[idx])
	var dres := _damage_cell_idx(idx, amount)
	var code := dres.x
	var hp_rm := dres.y
	if code == 0:
		return false
	if hp_rm > 0:
		GameStatistics.add_block_damage(hp_rm, damage_source)
	if code == 2:
		GameStatistics.add_blocks_destroyed(1)
		if old_type >= 0 and old_type < TYPE_MONEY.size():
			GameStatistics.add_money(int(TYPE_MONEY[old_type]))
	_try_mark_destroyed()
	_leftmost_solid_dirty = true
	_row_leftmost_cache_dirty = true
	if not _destroyed:
		_invalidate_mask_and_neighbor_seams()
	return code == 2


func debug_destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	_row_leftmost_cache_dirty = true
	if _visual != null:
		_visual.visible = false
	_invalidate_neighbor_seams_only()
	fully_destroyed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not debug_destroy_on_key:
		pass
	else:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == debug_destroy_key:
				debug_destroy()
				return

	if debug_damage_on_click and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_mouse_held = true
			_click_pending_edge = true
			_pending_press_local = to_local(mb.position)
		else:
			_mouse_held = false
			_click_pending_edge = false


func _ready() -> void:
	reset_target()


func _process(delta: float) -> void:
	if debug_damage_on_click and not _destroyed:
		_click_fire_time_bank_s += delta
		var interval_s: float = _click_interval_s()
		if _click_pending_edge and _click_fire_time_bank_s >= interval_s:
			_click_fire_time_bank_s -= interval_s
			_apply_click_damage_at_local(_pending_press_local)
			_click_pending_edge = false
		while _mouse_held and _click_fire_time_bank_s >= interval_s:
			_click_fire_time_bank_s -= interval_s
			_apply_click_damage_at_local(get_local_mouse_position())
	_update_mask_texture_if_dirty()
	_rebuild_row_leftmost_cache_if_dirty()


func _click_interval_s() -> float:
	return maxf(GameStatistics.click_fire_rate_ms, 1.0) / 1000.0


func _apply_click_damage_at_local(lp: Vector2) -> void:
	var r_px: float = float(GameStatistics.click_radius_cells) * cell_size_px
	apply_damage_circle_local(lp, r_px, GameStatistics.click_damage)


func _init_mask_visuals() -> void:
	if _visual == null:
		push_error("DestructibleTarget requires a child Sprite2D named 'Visual'.")
		return

	_visual.centered = true

	var tw := _texture_width()
	_mask_image = Image.create(tw, _grid_h, false, Image.FORMAT_L8)
	_mask_image.fill(Color(1, 1, 1, 1))

	_type_image = Image.create(tw, _grid_h, false, Image.FORMAT_RG8)
	_type_image.fill(Color(0, 0, 0, 1))

	_mask_texture = ImageTexture.create_from_image(_mask_image)
	_type_texture = ImageTexture.create_from_image(_type_image)

	_visual.texture = _mask_texture
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Texture is (grid_w + 2*APRON) x grid_h; sprite only renders the interior so neighbor slabs
	# don't overdraw each other at the seam. Apron texels still readable by shader via UV*texSize.
	_visual.region_enabled = true
	_visual.region_rect = Rect2(float(APRON_COLUMNS), 0.0, float(_grid_w), float(_grid_h))
	_visual.scale = Vector2(cell_size_px, cell_size_px)

	var sm := ShaderMaterial.new()
	var sh: Shader = load("res://shaders/destructible_target_marching.gdshader")
	if sh == null:
		push_error("Failed to load res://shaders/destructible_target_marching.gdshader")
		return
	sm.shader = sh
	sm.set_shader_parameter("mask_tex", _mask_texture)
	sm.set_shader_parameter("type_tex", _type_texture)
	_push_shader_type_colors(sm)
	_visual.material = sm
	clear_highlight()


func _push_shader_type_colors(sm: ShaderMaterial) -> void:
	var n := mini(TYPE_COUNT, SHADER_TYPE_COLOR_MAX)
	sm.set_shader_parameter("type_count", n)
	var pc := PackedColorArray()
	pc.resize(SHADER_TYPE_COLOR_MAX)
	for i in range(SHADER_TYPE_COLOR_MAX):
		pc[i] = TYPE_COLOR[i] if i < TYPE_COUNT else Color(0, 0, 0, 0)
	sm.set_shader_parameter("type_colors", pc)


func _texture_width() -> int:
	return _grid_w + 2 * APRON_COLUMNS


func _write_empty_mask_type(dst_x: int, dst_y: int) -> void:
	_mask_image.set_pixel(dst_x, dst_y, Color(0, 0, 0, 1))
	_type_image.set_pixel(dst_x, dst_y, Color(0, 0, 0, 1))


func _write_interior_cell_to_images(dst_x: int, dst_y: int, idx: int) -> void:
	var t := int(_cells[idx])
	if t == TYPE_EMPTY:
		_write_empty_mask_type(dst_x, dst_y)
	else:
		_mask_image.set_pixel(dst_x, dst_y, Color(1, 1, 1, 1))
		var max_hp := maxi(1, int(TYPE_MAX_HP[t]))
		var hp := clampi(int(_cell_hp[idx]), 0, max_hp)
		var hp_ratio := float(hp) / float(max_hp)
		var type_r := clampf(float(t) / 255.0, 0.0, 1.0)
		_type_image.set_pixel(dst_x, dst_y, Color(type_r, hp_ratio, 0, 1))


func _write_peer_cell_to_images(dst_x: int, dst_y: int, peer: DestructibleTarget, src_x: int, src_y: int) -> void:
	if peer == null or peer._destroyed:
		_write_empty_mask_type(dst_x, dst_y)
		return
	if src_x < 0 or src_y < 0 or src_x >= peer._grid_w or src_y >= peer._grid_h:
		_write_empty_mask_type(dst_x, dst_y)
		return
	var idx := src_y * peer._grid_w + src_x
	var t := int(peer._cells[idx])
	if t == TYPE_EMPTY:
		_write_empty_mask_type(dst_x, dst_y)
	else:
		_mask_image.set_pixel(dst_x, dst_y, Color(1, 1, 1, 1))
		var max_hp := maxi(1, int(TYPE_MAX_HP[t]))
		var hp := clampi(int(peer._cell_hp[idx]), 0, max_hp)
		var hp_ratio := float(hp) / float(max_hp)
		var type_r := clampf(float(t) / 255.0, 0.0, 1.0)
		_type_image.set_pixel(dst_x, dst_y, Color(type_r, hp_ratio, 0, 1))


func _fill_apron_columns_from_neighbors() -> void:
	var tw := _texture_width()
	for y in range(_grid_h):
		for a in range(APRON_COLUMNS):
			# Left apron copies right edge of left neighbor.
			var src_lx := -1
			if _left_neighbor != null:
				src_lx = _left_neighbor._grid_w - APRON_COLUMNS + a
			_write_peer_cell_to_images(a, y, _left_neighbor, src_lx, y)
			# Right apron copies left edge of right neighbor.
			_write_peer_cell_to_images(tw - APRON_COLUMNS + a, y, _right_neighbor, a, y)


func _update_mask_texture_if_dirty() -> void:
	if not _mask_dirty:
		return
	if _destroyed:
		return
	if _mask_image == null or _mask_texture == null or _type_image == null or _type_texture == null:
		return

	var ox := APRON_COLUMNS
	for y in range(_grid_h):
		var row := y * _grid_w
		for x in range(_grid_w):
			var idx := row + x
			_write_interior_cell_to_images(ox + x, y, idx)

	_fill_apron_columns_from_neighbors()

	_mask_texture.update(_mask_image)
	_type_texture.update(_type_image)
	_mask_dirty = false


func cell_center_local(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * cell_size_px - target_size_px.x * 0.5,
		(float(cell.y) + 0.5) * cell_size_px - target_size_px.y * 0.5
	)


func is_cell_solid(cell: Vector2i) -> bool:
	if _destroyed:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_w or cell.y >= _grid_h:
		return false
	return _cells[cell.y * _grid_w + cell.x] != TYPE_EMPTY


func get_grid_width_cells() -> int:
	return _grid_w


## Max over rows of each row's rightmost empty column index; -1 if no empty cells (all solid).
func get_furthest_right_empty_cell_x() -> int:
	var best := -1
	for y in range(_grid_h):
		var row := y * _grid_w
		var row_best := -1
		for x in range(_grid_w - 1, -1, -1):
			if _cells[row + x] == TYPE_EMPTY:
				row_best = x
				break
		if row_best > best:
			best = row_best
	return best


func _rebuild_row_leftmost_cache_if_dirty() -> void:
	if not _row_leftmost_cache_dirty:
		return
	_row_leftmost_cache_dirty = false
	if _destroyed:
		_row_leftmost_x.clear()
		_row_leftmost_pos_local.clear()
		return
	if _row_leftmost_x.size() != _grid_h:
		_row_leftmost_x.resize(_grid_h)
		_row_leftmost_pos_local.resize(_grid_h)
	for y in range(_grid_h):
		var lx := -1
		var row := y * _grid_w
		for x in range(_grid_w):
			if _cells[row + x] != TYPE_EMPTY:
				lx = x
				break
		_row_leftmost_x[y] = lx
		if lx < 0:
			_row_leftmost_pos_local[y] = Vector2.ZERO
		else:
			_row_leftmost_pos_local[y] = cell_center_local(Vector2i(lx, y))


## Among each row's leftmost solid cell, returns grid cell whose cached center is closest to `from_local`.
func get_closest_row_leftmost_cell(from_local: Vector2) -> Vector2i:
	if _destroyed:
		return Vector2i(-1, -1)
	_rebuild_row_leftmost_cache_if_dirty()
	var best: Vector2i = Vector2i(-1, -1)
	var best_d2 := INF
	for y in range(_grid_h):
		var x := _row_leftmost_x[y]
		if x < 0:
			continue
		var d2 := _row_leftmost_pos_local[y].distance_squared_to(from_local)
		if d2 < best_d2:
			best_d2 = d2
			best = Vector2i(x, y)
	return best


func get_row_leftmost_cell_for_row(row_y: int) -> Vector2i:
	if row_y < 0 or row_y >= _grid_h:
		return Vector2i(-1, -1)
	_rebuild_row_leftmost_cache_if_dirty()
	var x := _row_leftmost_x[row_y]
	if x < 0:
		return Vector2i(-1, -1)
	return Vector2i(x, row_y)


func get_cached_row_leftmost_local_pos(row_y: int) -> Vector2:
	if row_y < 0 or row_y >= _grid_h:
		return Vector2.ZERO
	_rebuild_row_leftmost_cache_if_dirty()
	return _row_leftmost_pos_local[row_y]


const HIGHLIGHT_SHADER_MAX: int = 8


func set_highlight_cells(cells: Array[Vector2i]) -> void:
	if _visual == null:
		return
	var sm := _visual.material as ShaderMaterial
	if sm == null:
		return
	var packed := PackedVector2Array()
	var n := 0
	if not _destroyed:
		for c in cells:
			if n >= HIGHLIGHT_SHADER_MAX:
				break
			if c.x < 0 or c.y < 0:
				continue
			# Shader compares texel coords; interior grid starts at x = APRON_COLUMNS in texture.
			packed.append(Vector2(float(c.x + APRON_COLUMNS), float(c.y)))
			n += 1
	while packed.size() < HIGHLIGHT_SHADER_MAX:
		packed.append(Vector2(-1.0, -1.0))
	sm.set_shader_parameter("highlight_cells", packed)
	sm.set_shader_parameter("highlight_count", n)


func set_highlight_cell(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0:
		clear_highlight()
	else:
		set_highlight_cells([cell])


func clear_highlight() -> void:
	set_highlight_cells([])


func set_neighbors(left: DestructibleTarget, right: DestructibleTarget) -> void:
	_left_neighbor = left
	_right_neighbor = right
	_invalidate_mask_and_neighbor_seams()


func _invalidate_mask_and_neighbor_seams() -> void:
	_mask_dirty = true
	_invalidate_neighbor_seams_only()


func _invalidate_neighbor_seams_only() -> void:
	if is_instance_valid(_left_neighbor):
		_left_neighbor._mask_dirty = true
	if is_instance_valid(_right_neighbor):
		_right_neighbor._mask_dirty = true


func get_leftmost_solid_local_x() -> float:
	# Local-space X of the left edge of the leftmost undestroyed cell.
	if _leftmost_solid_dirty:
		_leftmost_solid_cell_x = _find_leftmost_solid_cell_x()
		_leftmost_solid_dirty = false
	return float(_leftmost_solid_cell_x) * cell_size_px - target_size_px.x * 0.5


func _find_leftmost_solid_cell_x() -> int:
	# Scan columns left->right; first column containing any solid cell wins.
	for x in range(_grid_w):
		for y in range(_grid_h):
			if _cells[y * _grid_w + x] != TYPE_EMPTY:
				return x
	return 0


func _init_grid() -> void:
	_grid_w = max(1, int(round(target_size_px.x / cell_size_px)))
	_grid_h = max(1, int(round(target_size_px.y / cell_size_px)))

	_cells = PackedByteArray()
	_cells.resize(_grid_w * _grid_h)
	_cell_hp = PackedByteArray()
	_cell_hp.resize(_grid_w * _grid_h)

	if fill_solid_on_reset:
		_generate_cells()
	else:
		for i in range(_cells.size()):
			_cells[i] = TYPE_EMPTY
			_cell_hp[i] = 0


func _generate_cells() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed if generation_seed != 0 else Time.get_ticks_usec()

	for i in range(_cells.size()):
		_cells[i] = TYPE_ROCK
		_cell_hp[i] = clampi(int(TYPE_MAX_HP[TYPE_ROCK]), 0, 255)

	match generation_mode:
		&"default":
			_gen_default(rng)
		_:
			_gen_default(rng)


func _gen_default(rng: RandomNumberGenerator) -> void:
	var total := _cells.size()
	var n_seeds := int(round(gold_density * float(total)))
	n_seeds = clampi(n_seeds, 0, total)
	var cluster_r := maxi(0, gold_cluster_size)

	for _s in n_seeds:
		var sx := rng.randi_range(0, _grid_w - 1)
		var sy := rng.randi_range(0, _grid_h - 1)
		_paint_gold_blob(Vector2i(sx, sy), cluster_r, rng)


func _paint_gold_blob(origin: Vector2i, radius_cells: int, rng: RandomNumberGenerator) -> void:
	if radius_cells <= 0:
		_set_cell_type(origin.x, origin.y, TYPE_GOLD)
		return
	var q: Array[Vector2i] = [origin]
	var visited: Dictionary = {}
	var budget := (radius_cells * 2 + 1) * (radius_cells * 2 + 1)
	while not q.is_empty() and budget > 0:
		budget -= 1
		var c: Vector2i = q.pop_front()
		var key := Vector2i(c.x, c.y)
		if visited.has(key):
			continue
		visited[key] = true
		if c.x < 0 or c.y < 0 or c.x >= _grid_w or c.y >= _grid_h:
			continue
		if origin.distance_squared_to(c) > float(radius_cells * radius_cells):
			continue
		_set_cell_type(c.x, c.y, TYPE_GOLD)
		var dirs: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]
		for di in range(dirs.size() - 1, 0, -1):
			var j := rng.randi_range(0, di)
			var tmp := dirs[di]
			dirs[di] = dirs[j]
			dirs[j] = tmp
		for d in dirs:
			if rng.randf() < 0.65:
				q.append(c + d)


func _set_cell_type(cx: int, cy: int, type_id: int) -> void:
	var idx := cy * _grid_w + cx
	if type_id == TYPE_EMPTY:
		_cells[idx] = TYPE_EMPTY
		_cell_hp[idx] = 0
		return
	_cells[idx] = type_id
	var mh := clampi(int(TYPE_MAX_HP[type_id]), 0, 255)
	_cell_hp[idx] = mh


## x: 0 = no change, 1 = hp reduced, 2 = cell destroyed. y: HP actually removed from the cell.
func _damage_cell_idx(idx: int, amount: int) -> Vector2i:
	if _cells[idx] == TYPE_EMPTY or amount <= 0:
		return Vector2i(0, 0)
	var hp_before := int(_cell_hp[idx])
	var new_hp := hp_before - amount
	if new_hp <= 0:
		_cells[idx] = TYPE_EMPTY
		_cell_hp[idx] = 0
		return Vector2i(2, hp_before)
	var nh := clampi(new_hp, 0, 255)
	_cell_hp[idx] = nh
	return Vector2i(1, hp_before - nh)


func _local_to_cell(local_pos: Vector2) -> Vector2i:
	var gx := int(floor((local_pos.x + target_size_px.x * 0.5) / cell_size_px))
	var gy := int(floor((local_pos.y + target_size_px.y * 0.5) / cell_size_px))
	return Vector2i(gx, gy)


func _try_mark_destroyed() -> void:
	if _destroyed:
		return

	for i in range(_cells.size()):
		if _cells[i] != TYPE_EMPTY:
			return

	_destroyed = true
	_row_leftmost_cache_dirty = true
	if _visual != null:
		_visual.visible = false
	_invalidate_neighbor_seams_only()
	fully_destroyed.emit()
