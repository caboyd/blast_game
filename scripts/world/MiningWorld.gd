class_name MiningWorld
extends Node2D

const CHUNK_SIZE := 40
const CELL_SIZE_PX := 8.0

const TYPE_EMPTY := 0
const TYPE_DIRT := 1
const TYPE_STONE := 2
const TYPE_GOLD := 3
const TYPE_FUEL := 4
const TYPE_COUNT := 5

static var TYPE_MAX_HP: PackedInt32Array = PackedInt32Array([0, 5, 50, 5, 1])
static var TYPE_MONEY: PackedInt32Array = PackedInt32Array([0, 1, 2, 15, 0])
static var TYPE_COLOR: PackedColorArray = PackedColorArray([
	Color(0.0, 0.0, 0.0, 0.0),
	Color(0.42, 0.28, 0.18, 1.0),
	Color(0.52, 0.52, 0.55, 1.0),
	Color(1.0, 0.82, 0.2, 1.0),
	# Shader uses dedicated fuel look; keep brown for any CPU fallbacks.
	Color(0.22, 0.15, 0.10, 1.0),
])

const SHADER_TYPE_COLOR_MAX := 8
const APRON_COLUMNS := 0


## World-space center of the square covered by one chunk (`CHUNK_SIZE` cells per side).
static func get_chunk_center_world(chunk: Vector2i) -> Vector2:
	var s: float = float(CHUNK_SIZE) * CELL_SIZE_PX
	return Vector2((float(chunk.x) + 0.5) * s, (float(chunk.y) + 0.5) * s)


## Landmarks in absolute world cell coordinates (post-generation stamp).
const STATIC_CELLS: Array[Dictionary] = [
	{"cell": Vector2i(0, -10), "type": TYPE_GOLD, "hp": 5},
]

@export var stage_id: StringName = &"planet1"
@export var stage_seed: int = 0
@export var view_margin_cells: int = 2
@export var reveal_save_debounce_s: float = 1.0
## Probability per cell during gold pass (after dirt + rock splats). Sparse by default.
@export_range(0.0, 1.0, 0.0001) var gold_density: float = 0.012


const _VEIN_NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## 4-way connectivity for stone “glob” flood (matches filled splats without corner-only bridges).
const _STONE_BLOB_DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

var _chunks: Dictionary = {} # Vector2i -> { cells, hp, revealed PackedByteArray }

var _view_origin_cell: Vector2i = Vector2i.ZERO
var _view_size_cells: Vector2i = Vector2i.ZERO

var _mask_image: Image
var _type_image: Image
var _reveal_image: Image
var _mask_texture: ImageTexture
var _type_texture: ImageTexture
var _reveal_texture: ImageTexture
var _visual_dirty: bool = true

var _reveal_dirty_chunks: Dictionary = {} # Vector2i -> true
var _reveal_save_accum: float = 0.0

@onready var _world_visual: Sprite2D = $WorldVisual
@onready var _fog_visual: Sprite2D = $FogVisual


func _ready() -> void:
	_init_visuals()
	_load_persisted_reveals()
	set_process(true)


func _exit_tree() -> void:
	if not _reveal_dirty_chunks.is_empty():
		_reveal_save_accum = reveal_save_debounce_s
		_flush_reveal_save()


func _process(delta: float) -> void:
	if _reveal_dirty_chunks.is_empty():
		return
	_reveal_save_accum += delta
	if _reveal_save_accum >= reveal_save_debounce_s:
		_reveal_save_accum = 0.0
		_flush_reveal_save()


func _stage_seed_effective() -> int:
	if stage_seed != 0:
		return stage_seed
	return hash(stage_id)


func _chunk_rng_seed(chunk: Vector2i) -> int:
	return hash(Vector3i(_stage_seed_effective(), chunk.x, chunk.y))


func _floor_div(a: int, b: int) -> int:
	return int(floor(float(a) / float(b)))


func _cell_to_chunk_coord(cell: Vector2i) -> Vector2i:
	return Vector2i(_floor_div(cell.x, CHUNK_SIZE), _floor_div(cell.y, CHUNK_SIZE))


func _cell_to_local_in_chunk(cell: Vector2i, chunk: Vector2i) -> int:
	var lx: int = cell.x - chunk.x * CHUNK_SIZE
	var ly: int = cell.y - chunk.y * CHUNK_SIZE
	return ly * CHUNK_SIZE + lx


func _ensure_chunk(chunk: Vector2i) -> void:
	if _chunks.has(chunk):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_rng_seed(chunk)

	var n: int = CHUNK_SIZE * CHUNK_SIZE
	var cells := PackedByteArray()
	cells.resize(n)
	var hp := PackedByteArray()
	hp.resize(n)
	var revealed := PackedByteArray()
	revealed.resize(n)

	var dirt_hp: int = clampi(int(TYPE_MAX_HP[TYPE_DIRT]), 0, 255)
	var stone_hp: int = clampi(int(TYPE_MAX_HP[TYPE_STONE]), 0, 255)
	var gold_hp: int = clampi(int(TYPE_MAX_HP[TYPE_GOLD]), 0, 255)

	for i in n:
		cells[i] = TYPE_DIRT
		hp[i] = dirt_hp

	var num_splats: int = rng.randi_range(1, 3)
	for _s in num_splats:
		var splat_r: int = rng.randi_range(2, 5)
		var cx: int = rng.randi_range(0, CHUNK_SIZE - 1)
		var cy: int = rng.randi_range(0, CHUNK_SIZE - 1)
		var r2: int = splat_r * splat_r
		for ly in CHUNK_SIZE:
			for lx in CHUNK_SIZE:
				var dx: int = lx - cx
				var dy: int = ly - cy
				if dx * dx + dy * dy > r2:
					continue
				var idx: int = ly * CHUNK_SIZE + lx
				cells[idx] = TYPE_STONE
				hp[idx] = stone_hp

	var order: Array[int] = []
	order.resize(n)
	for i in n:
		order[i] = i
	for ii in range(n - 1, 0, -1):
		var jj: int = rng.randi_range(0, ii)
		var tmp: int = order[ii]
		order[ii] = order[jj]
		order[jj] = tmp

	for idx_cell in order:
		if rng.randf() >= gold_density:
			continue
		var t: int = int(cells[idx_cell])
		if t == TYPE_DIRT:
			cells[idx_cell] = TYPE_GOLD
			hp[idx_cell] = gold_hp
		elif t == TYPE_STONE:
			# Replace the entire connected stone splat with gold; one-cell stone shell and one dirt entrance.
			var inside: Array[int] = []
			var seen_stone: PackedByteArray = PackedByteArray()
			seen_stone.resize(n)
			var stack: Array[int] = [idx_cell]
			seen_stone[idx_cell] = 1
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				inside.append(cur)
				var cx: int = cur % CHUNK_SIZE
				@warning_ignore("integer_division")
				var cy: int = cur / CHUNK_SIZE
				for dir in _STONE_BLOB_DIRS:
					var nx: int = cx + dir.x
					var ny: int = cy + dir.y
					if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE:
						continue
					var nidx: int = ny * CHUNK_SIZE + nx
					if seen_stone[nidx] != 0:
						continue
					if int(cells[nidx]) != TYPE_STONE:
						continue
					seen_stone[nidx] = 1
					stack.append(nidx)
			var inside_set: Dictionary = {}
			for id_i in inside:
				inside_set[id_i] = true
			for id_i in inside:
				cells[id_i] = TYPE_GOLD
				hp[id_i] = gold_hp
			var halo: Array[int] = []
			var halo_seen: Dictionary = {}
			for id_i in inside:
				var ix: int = id_i % CHUNK_SIZE
				@warning_ignore("integer_division")
				var iy: int = id_i / CHUNK_SIZE
				for dir in _VEIN_NEIGHBOR_DIRS:
					var hx: int = ix + dir.x
					var hy: int = iy + dir.y
					if hx < 0 or hx >= CHUNK_SIZE or hy < 0 or hy >= CHUNK_SIZE:
						continue
					var hidx: int = hy * CHUNK_SIZE + hx
					if inside_set.has(hidx) or halo_seen.has(hidx):
						continue
					halo_seen[hidx] = true
					halo.append(hidx)
			if not halo.is_empty():
				var entrance_h: int = rng.randi_range(0, halo.size() - 1)
				for hi in halo.size():
					var hid: int = halo[hi]
					if hi == entrance_h:
						cells[hid] = TYPE_DIRT
						hp[hid] = dirt_hp
					else:
						cells[hid] = TYPE_STONE
						hp[hid] = stone_hp

	# One 2×2 fuel pickup per chunk (any tile destroyed removes the whole cluster).
	# Skip spawn chunk so the starting area has no fuel cell.
	var chunk_data: Dictionary = {
		"cells": cells,
		"hp": hp,
		"revealed": revealed,
	}
	if chunk != Vector2i.ZERO:
		var fax: int = rng.randi_range(0, CHUNK_SIZE - 2)
		var fay: int = rng.randi_range(0, CHUNK_SIZE - 2)
		var fuel_hp: int = clampi(int(TYPE_MAX_HP[TYPE_FUEL]), 0, 255)
		for fy in 2:
			for fx in 2:
				var fi: int = (fay + fy) * CHUNK_SIZE + (fax + fx)
				cells[fi] = TYPE_FUEL
				hp[fi] = fuel_hp
		chunk_data["fuel_anchor"] = Vector2i(fax, fay)
	_chunks[chunk] = chunk_data
	_apply_static_overrides_for_chunk(chunk)


func _apply_static_overrides_for_chunk(chunk: Vector2i) -> void:
	var data: Dictionary = _chunks[chunk]
	var cells: PackedByteArray = data["cells"]
	var hparr: PackedByteArray = data["hp"]

	for o in STATIC_CELLS:
		var wc: Vector2i = o["cell"]
		if _cell_to_chunk_coord(wc) != chunk:
			continue
		var idx: int = _cell_to_local_in_chunk(wc, chunk)
		var tid: int = int(o["type"])
		var h: int = int(o["hp"])
		cells[idx] = tid
		hparr[idx] = clampi(h, 0, 255)


## Soft terrain fill: Chebyshev radius `radius_cells` (square: ±radius on both axes). Ensures chunks.
func stamp_dirt_chebyshev_from_world(world_pos: Vector2, radius_cells: int) -> void:
	if radius_cells < 0:
		return
	var center_cell := world_pos_to_cell(world_pos)
	var dirt_hp: int = clampi(int(TYPE_MAX_HP[TYPE_DIRT]), 0, 255)
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var c := Vector2i(center_cell.x + dx, center_cell.y + dy)
			var ch := _cell_to_chunk_coord(c)
			_ensure_chunk(ch)
			var data: Dictionary = _chunks[ch]
			var cells_ba: PackedByteArray = data["cells"]
			var hp_ba: PackedByteArray = data["hp"]
			var idx: int = _cell_to_local_in_chunk(c, ch)
			cells_ba[idx] = TYPE_DIRT
			hp_ba[idx] = dirt_hp
	_visual_dirty = true


func _load_persisted_reveals() -> void:
	var loaded: Dictionary = GameSession.load_stage_reveal(stage_id)
	for k in loaded:
		var chunk: Vector2i = k
		_ensure_chunk(chunk)
		var barr: PackedByteArray = loaded[k]
		var data: Dictionary = _chunks[chunk]
		var rev: PackedByteArray = data["revealed"]
		var lim: int = mini(rev.size(), barr.size())
		for i in lim:
			rev[i] = barr[i]
	_visual_dirty = true


## Mineable block types for prep UI (per-stage list; uses TYPE_MAX_HP / TYPE_MONEY).
static func get_stage_block_type_rows() -> Array[Dictionary]:
	return [
		{"type_id": TYPE_DIRT, "label": "Dirt"},
		{"type_id": TYPE_STONE, "label": "Stone"},
		{"type_id": TYPE_GOLD, "label": "Gold"},
		{"type_id": TYPE_FUEL, "label": "Fuel cell"},
	]


func _flush_reveal_save() -> void:
	if _reveal_dirty_chunks.is_empty():
		return
	var merged: Dictionary = GameSession.load_stage_reveal(stage_id)
	for k in _reveal_dirty_chunks:
		var chunk: Vector2i = k
		if not _chunks.has(chunk):
			continue
		merged[chunk] = _chunks[chunk]["revealed"].duplicate()
	GameSession.save_stage_reveal(stage_id, merged)
	_reveal_dirty_chunks.clear()


func world_pos_to_cell(world: Vector2) -> Vector2i:
	return Vector2i(int(floor(world.x / CELL_SIZE_PX)), int(floor(world.y / CELL_SIZE_PX)))


## Chunk index `(floor(cell.x / CHUNK_SIZE), …)` in world / grid space.
func get_chunk_for_world_pos(world: Vector2) -> Vector2i:
	return _cell_to_chunk_coord(world_pos_to_cell(world))


func cell_top_left_world(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) * CELL_SIZE_PX, float(cell.y) * CELL_SIZE_PX)


func is_solid_world(world: Vector2) -> bool:
	var c := world_pos_to_cell(world)
	return _is_cell_solid(c)


func _is_cell_solid(cell: Vector2i) -> bool:
	var ch := _cell_to_chunk_coord(cell)
	if not _chunks.has(ch):
		return false
	var data: Dictionary = _chunks[ch]
	var idx: int = _cell_to_local_in_chunk(cell, ch)
	return int(data["cells"][idx]) != TYPE_EMPTY


func mine_at_world(world_pos: Vector2, damage: int, mine_radius_px: float) -> int:
	if damage <= 0:
		return 0
	var center := world_pos_to_cell(world_pos)
	var r_cells: int = int(ceil(mine_radius_px / CELL_SIZE_PX))
	var r2: int = r_cells * r_cells
	var hp_removed_total: int = 0

	for dy in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			if dx * dx + dy * dy > r2:
				continue
			var c := Vector2i(center.x + dx, center.y + dy)
			hp_removed_total += _damage_cell_abs(c, damage)

	if hp_removed_total > 0:
		_visual_dirty = true
	return hp_removed_total


## Mines only the single grid cell that contains `world_pos` (one world point → one cell).
func mine_cell_at_world_point(world_pos: Vector2, damage: int) -> int:
	if damage <= 0:
		return 0
	var hp_removed: int = _damage_cell_abs(world_pos_to_cell(world_pos), damage)
	if hp_removed > 0:
		_visual_dirty = true
	return hp_removed


## Mines only grid cells whose world-space cell square overlaps the hull polygon (convex quad is fine).
func mine_cells_under_hull_world(world_hull: PackedVector2Array, damage: int) -> int:
	if damage <= 0 or world_hull.size() < 3:
		return 0
	var wb := Rect2(world_hull[0], Vector2.ZERO)
	for i in range(1, world_hull.size()):
		wb = wb.expand(world_hull[i])
	var c_tl := world_pos_to_cell(wb.position)
	var c_br := world_pos_to_cell(wb.end - Vector2(0.001, 0.001))
	var min_cx: int = mini(c_tl.x, c_br.x)
	var min_cy: int = mini(c_tl.y, c_br.y)
	var max_cx: int = maxi(c_tl.x, c_br.x)
	var max_cy: int = maxi(c_tl.y, c_br.y)
	var hp_removed_total: int = 0
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			if _cell_world_rect_overlaps_hull(cx, cy, world_hull):
				hp_removed_total += _damage_cell_abs(Vector2i(cx, cy), damage)
	if hp_removed_total > 0:
		_visual_dirty = true
	return hp_removed_total


func _cell_world_rect_polygon(cx: int, cy: int) -> PackedVector2Array:
	var x0: float = float(cx) * CELL_SIZE_PX
	var y0: float = float(cy) * CELL_SIZE_PX
	var x1: float = x0 + CELL_SIZE_PX
	var y1: float = y0 + CELL_SIZE_PX
	return PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)
	])


func _cell_world_rect_overlaps_hull(cx: int, cy: int, hull_world: PackedVector2Array) -> bool:
	var cell_poly: PackedVector2Array = _cell_world_rect_polygon(cx, cy)
	var inter: Array = Geometry2D.intersect_polygons(cell_poly, hull_world)
	if not inter.is_empty():
		return true
	var x0: float = float(cx) * CELL_SIZE_PX
	var y0: float = float(cy) * CELL_SIZE_PX
	var x1: float = x0 + CELL_SIZE_PX
	var y1: float = y0 + CELL_SIZE_PX
	var ctr := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
	if Geometry2D.is_point_in_polygon(ctr, hull_world):
		return true
	for j in cell_poly.size():
		if Geometry2D.is_point_in_polygon(cell_poly[j], hull_world):
			return true
	for hv in hull_world:
		var ic := world_pos_to_cell(hv)
		if ic.x == cx and ic.y == cy:
			return true
	return false


func _fuel_cluster_local_rect(data: Dictionary) -> Rect2i:
	var anchor: Variant = data.get("fuel_anchor", null)
	if anchor == null or not anchor is Vector2i:
		return Rect2i()
	var a: Vector2i = anchor as Vector2i
	return Rect2i(a.x, a.y, 2, 2)


func _cell_local_in_chunk_vec(cell: Vector2i, chunk: Vector2i) -> Vector2i:
	return Vector2i(cell.x - chunk.x * CHUNK_SIZE, cell.y - chunk.y * CHUNK_SIZE)


func _clear_fuel_cluster_if_cell_inside(
	data: Dictionary, cells: PackedByteArray, hparr: PackedByteArray, cell_local: Vector2i
) -> bool:
	var rect: Rect2i = _fuel_cluster_local_rect(data)
	if rect.size.x < 1 or not rect.has_point(cell_local):
		return false
	for ly in range(rect.position.y, rect.position.y + rect.size.y):
		for lx in range(rect.position.x, rect.position.x + rect.size.x):
			var li: int = ly * CHUNK_SIZE + lx
			if int(cells[li]) == TYPE_FUEL:
				cells[li] = TYPE_EMPTY
				hparr[li] = 0
	return true


func _damage_cell_abs(cell: Vector2i, amount: int) -> int:
	var ch := _cell_to_chunk_coord(cell)
	_ensure_chunk(ch)
	var data: Dictionary = _chunks[ch]
	var cells: PackedByteArray = data["cells"]
	var hparr: PackedByteArray = data["hp"]
	var idx: int = _cell_to_local_in_chunk(cell, ch)
	var t: int = int(cells[idx])
	if t == TYPE_EMPTY or amount <= 0:
		return 0
	GameSession.mark_block_type_discovered(stage_id, t)
	if t == TYPE_FUEL:
		var cl: Vector2i = _cell_local_in_chunk_vec(cell, ch)
		var rect: Rect2i = _fuel_cluster_local_rect(data)
		if rect.size.x >= 1 and rect.has_point(cl):
			var hp_f: int = int(hparr[idx])
			var new_hp_f: int = hp_f - amount
			if new_hp_f <= 0:
				_clear_fuel_cluster_if_cell_inside(data, cells, hparr, cl)
				GameStatistics.add_blocks_destroyed(1)
				GameStatistics.apply_fuel_cell_pickup()
				if TYPE_FUEL >= 0 and TYPE_FUEL < TYPE_MONEY.size():
					GameStatistics.add_mined_cell_reward(int(TYPE_MONEY[TYPE_FUEL]))
				return hp_f
			var nh_f: int = clampi(new_hp_f, 0, 255)
			hparr[idx] = nh_f
			return hp_f - nh_f
	var hp_before: int = int(hparr[idx])
	var new_hp: int = hp_before - amount
	if new_hp <= 0:
		cells[idx] = TYPE_EMPTY
		hparr[idx] = 0
		GameStatistics.add_blocks_destroyed(1)
		if t >= 0 and t < TYPE_MONEY.size():
			GameStatistics.add_mined_cell_reward(int(TYPE_MONEY[t]))
		return hp_before
	var nh: int = clampi(new_hp, 0, 255)
	hparr[idx] = nh
	return hp_before - nh


## Clears solid in every cell whose world AABB touches `center_world` + `radius_world` circle. No money / destroy stats.
func clear_solid_in_circle_world(center_world: Vector2, radius_world: float) -> void:
	if radius_world <= 0.0:
		return
	var cs: float = CELL_SIZE_PX
	var r: float = radius_world
	var cx0: int = int(floor((center_world.x - r) / cs))
	var cx1: int = int(floor((center_world.x + r) / cs))
	var cy0: int = int(floor((center_world.y - r) / cs))
	var cy1: int = int(floor((center_world.y + r) / cs))
	var any: bool = false
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_aabb_world(center_world, r, cx, cy):
				continue
			if _set_cell_type_empty_silent(Vector2i(cx, cy)):
				any = true
	if any:
		_visual_dirty = true


## True if any solid cell’s world AABB intersects the circle (Chunks are ensured so overlap isn’t missed.)
func has_solid_overlapping_circle_world(center_world: Vector2, radius_world: float) -> bool:
	if radius_world <= 0.0:
		return false
	var cs: float = CELL_SIZE_PX
	var r: float = radius_world
	var cx0: int = int(floor((center_world.x - r) / cs))
	var cx1: int = int(floor((center_world.x + r) / cs))
	var cy0: int = int(floor((center_world.y - r) / cs))
	var cy1: int = int(floor((center_world.y + r) / cs))
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_aabb_world(center_world, r, cx, cy):
				continue
			var c := Vector2i(cx, cy)
			_ensure_chunk(_cell_to_chunk_coord(c))
			if _is_cell_solid(c):
				return true
	return false


## Applies `damage` to every solid cell whose AABB hits the world circle. Returns total HP removed.
func mine_solid_in_circle_world(center_world: Vector2, radius_world: float, damage: int) -> int:
	if damage <= 0 or radius_world <= 0.0:
		return 0
	var cs: float = CELL_SIZE_PX
	var r: float = radius_world
	var cx0: int = int(floor((center_world.x - r) / cs))
	var cx1: int = int(floor((center_world.x + r) / cs))
	var cy0: int = int(floor((center_world.y - r) / cs))
	var cy1: int = int(floor((center_world.y + r) / cs))
	var hp_total: int = 0
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_aabb_world(center_world, r, cx, cy):
				continue
			hp_total += _damage_cell_abs(Vector2i(cx, cy), damage)
	if hp_total > 0:
		_visual_dirty = true
	return hp_total


func _circle_overlaps_cell_aabb_world(center: Vector2, radius: float, cell_x: int, cell_y: int) -> bool:
	var cs: float = CELL_SIZE_PX
	var L: float = float(cell_x) * cs
	var T: float = float(cell_y) * cs
	var R: float = L + cs
	var B: float = T + cs
	var px: float = clampf(center.x, L, R)
	var py: float = clampf(center.y, T, B)
	var dx: float = center.x - px
	var dy: float = center.y - py
	return dx * dx + dy * dy <= radius * radius


## Returns true if a cell was solid and got cleared.
func _set_cell_type_empty_silent(cell: Vector2i) -> bool:
	var ch := _cell_to_chunk_coord(cell)
	_ensure_chunk(ch)
	var data: Dictionary = _chunks[ch]
	var cells: PackedByteArray = data["cells"]
	var hparr: PackedByteArray = data["hp"]
	var idx: int = _cell_to_local_in_chunk(cell, ch)
	if int(cells[idx]) == TYPE_EMPTY:
		return false
	if int(cells[idx]) == TYPE_FUEL:
		var cl: Vector2i = _cell_local_in_chunk_vec(cell, ch)
		if _clear_fuel_cluster_if_cell_inside(data, cells, hparr, cl):
			return true
	cells[idx] = TYPE_EMPTY
	hparr[idx] = 0
	return true


func update_vision(center_world: Vector2, radius_cells: int) -> void:
	var cc := world_pos_to_cell(center_world)
	var r2: int = radius_cells * radius_cells
	var any_new: bool = false
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			if dx * dx + dy * dy > r2:
				continue
			var c := Vector2i(cc.x + dx, cc.y + dy)
			var ch := _cell_to_chunk_coord(c)
			_ensure_chunk(ch)
			var data: Dictionary = _chunks[ch]
			var rev: PackedByteArray = data["revealed"]
			var idx: int = _cell_to_local_in_chunk(c, ch)
			if int(rev[idx]) == 0:
				rev[idx] = 1
				_reveal_dirty_chunks[ch] = true
				var cells_ba: PackedByteArray = data["cells"]
				var t: int = int(cells_ba[idx])
				if t != TYPE_EMPTY:
					GameSession.mark_block_type_discovered(stage_id, t)
				any_new = true
	if any_new:
		_visual_dirty = true


## Visible world rectangle in pixels (SubViewport / camera space).
func set_camera_view_world_rect(rect: Rect2) -> void:
	# Size in cells must depend only on rect dimensions (constant for a given window + zoom).
	# If we resized whenever the top-left *cell* moved with the camera, we would recreate
	# ImageTextures every frame and break RenderingDevice shader versions.
	var w_cells: int = int(ceili(rect.size.x / CELL_SIZE_PX)) + 2 * view_margin_cells
	var h_cells: int = int(ceili(rect.size.y / CELL_SIZE_PX)) + 2 * view_margin_cells
	var new_size := Vector2i(w_cells, h_cells)

	var tl_cell := world_pos_to_cell(rect.position)
	var new_origin := Vector2i(tl_cell.x - view_margin_cells, tl_cell.y - view_margin_cells)

	var size_changed: bool = new_size != _view_size_cells
	var origin_changed: bool = new_origin != _view_origin_cell

	_view_origin_cell = new_origin

	if size_changed:
		_view_size_cells = new_size
		_resize_view_textures(new_size.x, new_size.y)
		_visual_dirty = true

	if origin_changed or size_changed:
		_update_visual_positions()
		_visual_dirty = true

	if _visual_dirty:
		_rebuild_view_textures()


func _resize_view_textures(w: int, h: int) -> void:
	if w < 1 or h < 1:
		return
	_mask_image = Image.create(w, h, false, Image.FORMAT_L8)
	_type_image = Image.create(w, h, false, Image.FORMAT_RG8)
	_reveal_image = Image.create(w, h, false, Image.FORMAT_L8)
	# `ImageTexture.update(image)` requires image size to match the texture; view size changes
	# after the first frame, so always recreate when dimensions change.
	_mask_texture = ImageTexture.create_from_image(_mask_image)
	_type_texture = ImageTexture.create_from_image(_type_image)
	_reveal_texture = ImageTexture.create_from_image(_reveal_image)

	if _world_visual:
		_world_visual.texture = _mask_texture
		_world_visual.region_enabled = false
		_world_visual.scale = Vector2(CELL_SIZE_PX, CELL_SIZE_PX)
		_world_visual.centered = false

	if _fog_visual:
		_fog_visual.texture = _reveal_texture
		_fog_visual.scale = Vector2(CELL_SIZE_PX, CELL_SIZE_PX)
		_fog_visual.centered = false

	_sync_shader_texture_params()


func _update_visual_positions() -> void:
	var tl := cell_top_left_world(_view_origin_cell)
	if _world_visual:
		_world_visual.position = tl
	if _fog_visual:
		_fog_visual.position = tl


func _sync_shader_texture_params() -> void:
	if _world_visual != null and _world_visual.material is ShaderMaterial:
		var sm: ShaderMaterial = _world_visual.material as ShaderMaterial
		sm.set_shader_parameter("mask_tex", _mask_texture)
		sm.set_shader_parameter("type_tex", _type_texture)
		sm.set_shader_parameter("fuel_world_origin", Vector2(_view_origin_cell))
	if _fog_visual != null and _fog_visual.material is ShaderMaterial:
		(_fog_visual.material as ShaderMaterial).set_shader_parameter("reveal_tex", _reveal_texture)


func _init_visuals() -> void:
	if _world_visual == null:
		push_error("World needs WorldVisual Sprite2D child.")
		return
	_resize_view_textures(32, 32)
	var sm := ShaderMaterial.new()
	var sh: Shader = load("res://shaders/destructible_target_marching.gdshader")
	if sh:
		sm.shader = sh
		sm.set_shader_parameter("mask_tex", _mask_texture)
		sm.set_shader_parameter("type_tex", _type_texture)
		_push_shader_type_colors(sm)
	_world_visual.material = sm
	_world_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_update_visual_positions()

	if _fog_visual:
		var fsm := ShaderMaterial.new()
		var fsh: Shader = load("res://shaders/fog_of_war.gdshader")
		if fsh:
			fsm.shader = fsh
			fsm.set_shader_parameter("reveal_tex", _reveal_texture)
		_fog_visual.material = fsm
		_fog_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_update_visual_positions()


func _push_shader_type_colors(sm: ShaderMaterial) -> void:
	var n: int = mini(TYPE_COUNT, SHADER_TYPE_COLOR_MAX)
	sm.set_shader_parameter("type_count", n)
	var pc := PackedColorArray()
	pc.resize(SHADER_TYPE_COLOR_MAX)
	for i in range(SHADER_TYPE_COLOR_MAX):
		pc[i] = TYPE_COLOR[i] if i < TYPE_COUNT else Color(0, 0, 0, 0)
	sm.set_shader_parameter("type_colors", pc)


func _rebuild_view_textures() -> void:
	if _mask_image == null or _view_size_cells.x < 1:
		return
	var ox: int = _view_origin_cell.x
	var oy: int = _view_origin_cell.y
	var w: int = _view_size_cells.x
	var h: int = _view_size_cells.y

	for iy in h:
		for ix in w:
			var wc := Vector2i(ox + ix, oy + iy)
			var ch := _cell_to_chunk_coord(wc)
			_ensure_chunk(ch)
			var data: Dictionary = _chunks[ch]
			var cells: PackedByteArray = data["cells"]
			var hparr: PackedByteArray = data["hp"]
			var rev: PackedByteArray = data["revealed"]
			var idx: int = _cell_to_local_in_chunk(wc, ch)
			var t: int = int(cells[idx])
			var revealed: bool = int(rev[idx]) != 0

			if not revealed:
				_mask_image.set_pixel(ix, iy, Color(0, 0, 0, 1))
				_type_image.set_pixel(ix, iy, Color(0, 0, 0, 1))
				_reveal_image.set_pixel(ix, iy, Color(0, 0, 0, 1))
				continue

			_reveal_image.set_pixel(ix, iy, Color(1, 1, 1, 1))

			if t == TYPE_EMPTY:
				_mask_image.set_pixel(ix, iy, Color(0, 0, 0, 1))
				_type_image.set_pixel(ix, iy, Color(0, 0, 0, 1))
			else:
				_mask_image.set_pixel(ix, iy, Color(1, 1, 1, 1))
				var max_hp: int = maxi(1, int(TYPE_MAX_HP[t]))
				var hp: int = clampi(int(hparr[idx]), 0, max_hp)
				var hp_ratio: float = float(hp) / float(max_hp)
				var type_r: float = clampf(float(t) / 255.0, 0.0, 1.0)
				_type_image.set_pixel(ix, iy, Color(type_r, hp_ratio, 0, 1))

	_mask_texture.update(_mask_image)
	_type_texture.update(_type_image)
	_reveal_texture.update(_reveal_image)

	_sync_shader_texture_params()
	_visual_dirty = false
