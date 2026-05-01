class_name MiningWorld
extends Node2D

const CHUNK_SIZE := 40
const CELL_SIZE_PX := 8.0

const TYPE_EMPTY := 0
const TYPE_DIRT := 1
const TYPE_STONE := 2
const TYPE_GOLD := 3
const TYPE_FUEL := 4
const TYPE_RUBY := 5
const TYPE_COUNT := 6

static var TYPE_MAX_HP: PackedInt32Array = PackedInt32Array([0, 5, 50, 5, 1, 100])
static var TYPE_MONEY: PackedInt32Array = PackedInt32Array([0, 1, 2, 15, 0, 1000])
static var TYPE_COLOR: PackedColorArray = PackedColorArray([
	Color(0.0, 0.0, 0.0, 0.0),
	Color(0.42, 0.28, 0.18, 1.0),
	Color(0.52, 0.52, 0.55, 1.0),
	Color(1.0, 0.82, 0.2, 1.0),
	# Fuel shader uses this as its tint anchor; brown preserves the current look.
	Color(0.22, 0.15, 0.10, 1.0),
	Color(0.92, 0.18, 0.38, 1.0),
])

const SHADER_TYPE_COLOR_MAX := 8
const APRON_COLUMNS := 0

const SPAWN_REVEAL_NORMAL := &"normal"
const SPAWN_REVEAL_FULL := &"full"

const _GENERIC_PART_GROUND_PICKUP := preload(
	"res://scenes/ship_parts/ground/part_ground_pickup.tscn"
)


static func fog_dark_tint_for_mid(mid: Color) -> Color:
	var r: float = mid.r * 0.09
	var g: float = mid.g * 0.09
	var b: float = mid.b * 0.09
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), 1.0)


## World-space center of the square covered by one chunk (`CHUNK_SIZE` cells per side).
static func get_chunk_center_world(chunk: Vector2i) -> Vector2:
	var s: float = float(CHUNK_SIZE) * CELL_SIZE_PX
	return Vector2((float(chunk.x) + 0.5) * s, (float(chunk.y) + 0.5) * s)


@export var stage_id: StringName = &"planet1"
@export var stage_seed: int = 0
@export var view_margin_cells: int = 2
@export var reveal_save_debounce_s: float = 1.0


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
var _terrain_dirty: bool = true
var _fog_dirty: bool = true
var _type_colors: PackedColorArray = TYPE_COLOR.duplicate()
var _fog_mid: Color = TYPE_COLOR[TYPE_DIRT]
var _fog_dark: Color = fog_dark_tint_for_mid(TYPE_COLOR[TYPE_DIRT])

var _reveal_dirty_chunks: Dictionary = {} # Vector2i -> true
var _reveal_save_accum: float = 0.0

var _chunk_generator: Callable = Callable()

@onready var _world_visual: Sprite2D = $WorldVisual
@onready var _fog_visual: Sprite2D = $FogVisual


func _ready() -> void:
	add_to_group(&"mining_world")
	_init_visuals()
	if _fog_visual:
		_fog_visual.z_index = 2
	apply_debug_fog_visibility()
	set_process(true)


func apply_debug_fog_visibility() -> void:
	var fog: Sprite2D = _fog_visual if _fog_visual else get_node_or_null("FogVisual") as Sprite2D
	if fog:
		fog.visible = not GameStatistics.debug_fog_disabled


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


func configure_stage_generation(new_stage_id: StringName, chunk_generator: Callable) -> void:
	stage_id = new_stage_id
	_chunk_generator = chunk_generator
	_chunks.clear()
	_reveal_dirty_chunks.clear()
	_reveal_save_accum = 0.0
	_load_persisted_reveals()
	_terrain_dirty = true
	_fog_dirty = true


## Sets per-material shader colors for this stage. Missing entries fall back to `TYPE_COLOR`.
func set_cell_material_colors(colors: PackedColorArray) -> void:
	var normalized := PackedColorArray()
	normalized.resize(TYPE_COUNT)
	for i in TYPE_COUNT:
		normalized[i] = colors[i] if i < colors.size() else TYPE_COLOR[i]
	_type_colors = normalized
	_push_shader_type_colors()
	_terrain_dirty = true


## Sets the main fog tint and derives `fog_dark` as a deep, same-hue layer (e.g. planet1 → dirt).
func set_fog_base_color(color: Color) -> void:
	var rgb := Color(color.r, color.g, color.b, 1.0)
	_fog_mid = rgb
	_fog_dark = fog_dark_tint_for_mid(rgb)
	_push_fog_shader_colors()


## Sets both fog shader colors explicitly (matches `fog_mid` / `fog_dark` uniforms on `fog_of_war_marching.gdshader`).
func set_fog_shader_colors(mid: Color, dark: Color) -> void:
	_fog_mid = Color(mid.r, mid.g, mid.b, 1.0)
	_fog_dark = Color(dark.r, dark.g, dark.b, 1.0)
	_push_fog_shader_colors()


func _floor_div(a: int, b: int) -> int:
	return int(floor(float(a) / float(b)))


func _cell_to_chunk_coord(cell: Vector2i) -> Vector2i:
	return Vector2i(_floor_div(cell.x, CHUNK_SIZE), _floor_div(cell.y, CHUNK_SIZE))


func _cell_to_local_in_chunk(cell: Vector2i, chunk: Vector2i) -> int:
	var lx: int = cell.x - chunk.x * CHUNK_SIZE
	var ly: int = cell.y - chunk.y * CHUNK_SIZE
	return ly * CHUNK_SIZE + lx


func ensure_chunk(chunk: Vector2i) -> void:
	_ensure_chunk(chunk)


func _hp_for_type(type_id: int) -> int:
	if type_id < 0 or type_id >= TYPE_MAX_HP.size():
		return 0
	return clampi(int(TYPE_MAX_HP[type_id]), 0, 255)


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

	var chunk_data: Dictionary = {
		"cells": cells,
		"hp": hp,
		"revealed": revealed,
	}
	_chunks[chunk] = chunk_data

	if _chunk_generator.is_valid():
		_chunk_generator.call(self, chunk, rng, chunk_data)
	else:
		fill_chunk_with_type(chunk_data, TYPE_DIRT)
	_terrain_dirty = true


func fill_chunk_with_type(chunk_data: Dictionary, type_id: int) -> void:
	var cells: PackedByteArray = chunk_data["cells"]
	var hparr: PackedByteArray = chunk_data["hp"]
	var hp_value: int = _hp_for_type(type_id)
	var n: int = mini(cells.size(), hparr.size())
	for i in n:
		cells[i] = type_id
		hparr[i] = hp_value


func add_random_stone_splats_to_chunk(
	chunk_data: Dictionary,
	rng: RandomNumberGenerator,
	min_splats: int,
	max_splats: int,
	min_radius: int,
	max_radius: int
) -> void:
	var cells: PackedByteArray = chunk_data["cells"]
	var hparr: PackedByteArray = chunk_data["hp"]
	var stone_hp: int = _hp_for_type(TYPE_STONE)
	var num_splats: int = rng.randi_range(min_splats, max_splats)
	for _s in num_splats:
		var splat_r: int = rng.randi_range(min_radius, max_radius)
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
				hparr[idx] = stone_hp


func add_gold_veins_to_chunk(
	chunk_data: Dictionary,
	rng: RandomNumberGenerator,
	density: float
) -> void:
	var cells: PackedByteArray = chunk_data["cells"]
	var hparr: PackedByteArray = chunk_data["hp"]
	var n: int = CHUNK_SIZE * CHUNK_SIZE
	var dirt_hp: int = _hp_for_type(TYPE_DIRT)
	var stone_hp: int = _hp_for_type(TYPE_STONE)
	var gold_hp: int = _hp_for_type(TYPE_GOLD)

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
		if rng.randf() >= density:
			continue
		var t: int = int(cells[idx_cell])
		if t == TYPE_DIRT:
			cells[idx_cell] = TYPE_GOLD
			hparr[idx_cell] = gold_hp
		elif t == TYPE_STONE:
			# Replace the entire connected stone splat with gold; stone shell around it and a 2×2 dirt mouth.
			# The mouth may overlap halo + gold and one step beyond the halo (open dirt) so a 2×2 always fits.
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
				hparr[id_i] = gold_hp
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
			if halo.is_empty():
				# No in-chunk neighbor to carve an opening (edge-sealed blob); leave as ordinary stone.
				for id_i in inside:
					cells[id_i] = TYPE_STONE
					hparr[id_i] = stone_hp
			else:
				var halo_set: Dictionary = {}
				for h_i in halo:
					halo_set[h_i] = true
				var mouth_ok: Dictionary = {}
				for id_i in inside_set:
					mouth_ok[id_i] = true
				for h_i in halo:
					mouth_ok[h_i] = true
				for h_i in halo:
					var hix: int = h_i % CHUNK_SIZE
					@warning_ignore("integer_division")
					var hiy: int = h_i / CHUNK_SIZE
					for dir in _STONE_BLOB_DIRS:
						var mx: int = hix + dir.x
						var my: int = hiy + dir.y
						if mx < 0 or mx >= CHUNK_SIZE or my < 0 or my >= CHUNK_SIZE:
							continue
						var midx: int = my * CHUNK_SIZE + mx
						if inside_set.has(midx):
							continue
						mouth_ok[midx] = true
				var anchors_2x2: Array[Vector2i] = []
				var mouth_failed: bool = false
				while true:
					anchors_2x2.clear()
					for ay in CHUNK_SIZE - 1:
						for ax in CHUNK_SIZE - 1:
							var b00: int = ay * CHUNK_SIZE + ax
							var b10: int = ay * CHUNK_SIZE + (ax + 1)
							var b01: int = (ay + 1) * CHUNK_SIZE + ax
							var b11: int = (ay + 1) * CHUNK_SIZE + (ax + 1)
							if not mouth_ok.has(b00) or not mouth_ok.has(b10) or not mouth_ok.has(b01) or not mouth_ok.has(b11):
								continue
							if not halo_set.has(b00) and not halo_set.has(b10) and not halo_set.has(b01) and not halo_set.has(b11):
								continue
							anchors_2x2.append(Vector2i(ax, ay))
					if not anchors_2x2.is_empty():
						break
					var pending: Dictionary = {}
					for mk in mouth_ok:
						var mix: int = mk % CHUNK_SIZE
						@warning_ignore("integer_division")
						var miy: int = mk / CHUNK_SIZE
						for dir in _STONE_BLOB_DIRS:
							var ex: int = mix + dir.x
							var ey: int = miy + dir.y
							if ex < 0 or ex >= CHUNK_SIZE or ey < 0 or ey >= CHUNK_SIZE:
								continue
							var eix: int = ey * CHUNK_SIZE + ex
							if inside_set.has(eix) or mouth_ok.has(eix):
								continue
							pending[eix] = true
					if pending.is_empty():
						push_error("MiningWorld: gold vein has no 2×2 mouth (generation bug); reverting blob to stone.")
						for id_i in inside:
							cells[id_i] = TYPE_STONE
							hparr[id_i] = stone_hp
						mouth_failed = true
						break
					for pk in pending:
						mouth_ok[pk] = true
				if not mouth_failed:
					var pick: Vector2i = anchors_2x2[rng.randi_range(0, anchors_2x2.size() - 1)]
					var entrance_indices: Dictionary = {}
					for dy in 2:
						for dx in 2:
							var eidx: int = (pick.y + dy) * CHUNK_SIZE + (pick.x + dx)
							entrance_indices[eidx] = true
							cells[eidx] = TYPE_DIRT
							hparr[eidx] = dirt_hp
					for hi in halo.size():
						var hid: int = halo[hi]
						if entrance_indices.has(hid):
							continue
						cells[hid] = TYPE_STONE
						hparr[hid] = stone_hp


func stamp_fuel_cluster(
	chunk_data: Dictionary,
	local_anchor: Vector2i,
	size_cells: Vector2i = Vector2i(2, 2)
) -> void:
	var cells: PackedByteArray = chunk_data["cells"]
	var hparr: PackedByteArray = chunk_data["hp"]
	var fuel_hp: int = _hp_for_type(TYPE_FUEL)
	for fy in size_cells.y:
		for fx in size_cells.x:
			var lx: int = local_anchor.x + fx
			var ly: int = local_anchor.y + fy
			if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE:
				continue
			var idx: int = ly * CHUNK_SIZE + lx
			cells[idx] = TYPE_FUEL
			hparr[idx] = fuel_hp
	chunk_data["fuel_anchor"] = local_anchor
	chunk_data["fuel_size"] = size_cells


func pick_random_cell_in_chunk(chunk: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	_ensure_chunk(chunk)
	var lx: int = rng.randi_range(0, CHUNK_SIZE - 1)
	var ly: int = rng.randi_range(0, CHUNK_SIZE - 1)
	return Vector2i(chunk.x * CHUNK_SIZE + lx, chunk.y * CHUNK_SIZE + ly)


func stamp_cell_overrides_for_chunk(chunk: Vector2i, overrides: Array[Dictionary]) -> void:
	var data: Dictionary = _chunks[chunk]
	var cells: PackedByteArray = data["cells"]
	var hparr: PackedByteArray = data["hp"]

	for o in overrides:
		var wc: Vector2i = o["cell"]
		if _cell_to_chunk_coord(wc) != chunk:
			continue
		var idx: int = _cell_to_local_in_chunk(wc, chunk)
		var tid: int = int(o["type"])
		var h: int = int(o.get("hp", _hp_for_type(tid)))
		cells[idx] = tid
		hparr[idx] = clampi(h, 0, 255)


func stamp_square_shell_for_chunk(
	chunk: Vector2i,
	center_cell: Vector2i,
	radius_cells: int,
	shell_type: int,
	center_type: int
) -> void:
	var data: Dictionary = _chunks[chunk]
	var cells: PackedByteArray = data["cells"]
	var hparr: PackedByteArray = data["hp"]
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var wc: Vector2i = Vector2i(center_cell.x + dx, center_cell.y + dy)
			if _cell_to_chunk_coord(wc) != chunk:
				continue
			var idx: int = _cell_to_local_in_chunk(wc, chunk)
			var type_id: int = center_type if dx == 0 and dy == 0 else shell_type
			cells[idx] = type_id
			hparr[idx] = _hp_for_type(type_id)


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
	_terrain_dirty = true


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
	_fog_dirty = true


## Mineable block types for prep UI (per-stage list; uses TYPE_MAX_HP / TYPE_MONEY).
static func get_stage_block_type_rows() -> Array[Dictionary]:
	return [
		{"type_id": TYPE_DIRT, "label": "Dirt"},
		{"type_id": TYPE_STONE, "label": "Stone"},
		{"type_id": TYPE_GOLD, "label": "Gold"},
		{"type_id": TYPE_FUEL, "label": "Fuel cell"},
		{"type_id": TYPE_RUBY, "label": "Ruby"},
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


func cell_center_world(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * CELL_SIZE_PX, (float(cell.y) + 0.5) * CELL_SIZE_PX)


func _peek_cell_type(cell: Vector2i) -> int:
	var ch := _cell_to_chunk_coord(cell)
	_ensure_chunk(ch)
	var data: Dictionary = _chunks[ch]
	var idx: int = _cell_to_local_in_chunk(cell, ch)
	return int(data["cells"][idx])


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
		_terrain_dirty = true
	return hp_removed_total


## Mines only the single grid cell that contains `world_pos` (one world point → one cell).
func mine_cell_at_world_point(world_pos: Vector2, damage: int) -> int:
	if damage <= 0:
		return 0
	var hp_removed: int = _damage_cell_abs(world_pos_to_cell(world_pos), damage)
	if hp_removed > 0:
		_terrain_dirty = true
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
		_terrain_dirty = true
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
	var size_var: Variant = data.get("fuel_size", Vector2i(2, 2))
	var size: Vector2i = size_var as Vector2i if size_var is Vector2i else Vector2i(2, 2)
	return Rect2i(a.x, a.y, size.x, size.y)


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
		_terrain_dirty = true


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
## If `allowed_cell_types` is non-empty, only cells whose material id is listed are mined.
func mine_solid_in_circle_world(
	center_world: Vector2,
	radius_world: float,
	damage: int,
	allowed_cell_types: PackedInt32Array = PackedInt32Array(),
) -> int:
	if damage <= 0 or radius_world <= 0.0:
		return 0
	var cs: float = CELL_SIZE_PX
	var r: float = radius_world
	var cx0: int = int(floor((center_world.x - r) / cs))
	var cx1: int = int(floor((center_world.x + r) / cs))
	var cy0: int = int(floor((center_world.y - r) / cs))
	var cy1: int = int(floor((center_world.y + r) / cs))
	var hp_total: int = 0
	var filter: bool = allowed_cell_types.size() > 0
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not _circle_overlaps_cell_aabb_world(center_world, r, cx, cy):
				continue
			var cell_v := Vector2i(cx, cy)
			if filter:
				var ct: int = _peek_cell_type(cell_v)
				var allowed := false
				for i in allowed_cell_types.size():
					if int(allowed_cell_types[i]) == ct:
						allowed = true
						break
				if not allowed:
					continue
			hp_total += _damage_cell_abs(cell_v, damage)
	if hp_total > 0:
		_terrain_dirty = true
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
		_fog_dirty = true


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
		_terrain_dirty = true
		_fog_dirty = true

	if origin_changed or size_changed:
		_update_visual_positions()
		_terrain_dirty = true
		_fog_dirty = true

	if _terrain_dirty:
		_rebuild_terrain_textures()
	if _fog_dirty:
		_rebuild_fog_texture()


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
		var fsm: ShaderMaterial = _fog_visual.material as ShaderMaterial
		fsm.set_shader_parameter("reveal_tex", _reveal_texture)
		fsm.set_shader_parameter("fog_world_origin", Vector2(_view_origin_cell))
		_push_fog_shader_colors()


func _init_visuals() -> void:
	if _world_visual == null:
		push_error("World needs WorldVisual Sprite2D child.")
		return
	_resize_view_textures(32, 32)
	var sm := ShaderMaterial.new()
	var sh: Shader = load("res://shaders/planet1_marching.gdshader")
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
		var fsh: Shader = load("res://shaders/fog_of_war_marching.gdshader")
		if fsh:
			fsm.shader = fsh
			fsm.set_shader_parameter("reveal_tex", _reveal_texture)
			fsm.set_shader_parameter("fog_world_origin", Vector2(_view_origin_cell))
			_push_fog_shader_colors(fsm)
		_fog_visual.material = fsm
		_fog_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_update_visual_positions()


func _push_shader_type_colors(sm: ShaderMaterial = null) -> void:
	var target: ShaderMaterial = sm
	if target == null:
		if _world_visual == null or not (_world_visual.material is ShaderMaterial):
			return
		target = _world_visual.material as ShaderMaterial
	var n: int = mini(TYPE_COUNT, SHADER_TYPE_COLOR_MAX)
	target.set_shader_parameter("type_count", n)
	var pc := PackedColorArray()
	pc.resize(SHADER_TYPE_COLOR_MAX)
	for i in range(SHADER_TYPE_COLOR_MAX):
		pc[i] = _type_colors[i] if i < TYPE_COUNT else Color(0, 0, 0, 0)
	target.set_shader_parameter("type_colors", pc)


func _push_fog_shader_colors(sm: ShaderMaterial = null) -> void:
	var fsm: ShaderMaterial = sm
	if fsm == null:
		if _fog_visual == null or not (_fog_visual.material is ShaderMaterial):
			return
		fsm = _fog_visual.material as ShaderMaterial

	fsm.set_shader_parameter("fog_mid", _fog_mid)
	fsm.set_shader_parameter("fog_dark", _fog_dark)


func _rebuild_terrain_textures() -> void:
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
			var idx: int = _cell_to_local_in_chunk(wc, ch)
			var t: int = int(cells[idx])

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

	_sync_shader_texture_params()
	_terrain_dirty = false


func _rebuild_fog_texture() -> void:
	if _reveal_image == null or _view_size_cells.x < 1:
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
			var rev: PackedByteArray = data["revealed"]
			var idx: int = _cell_to_local_in_chunk(wc, ch)
			var revealed: bool = int(rev[idx]) != 0
			_reveal_image.set_pixel(ix, iy, Color(1, 1, 1, 1) if revealed else Color(0, 0, 0, 1))

	_reveal_texture.update(_reveal_image)

	_sync_shader_texture_params()
	_fog_dirty = false


func stage_rng_seed(salt_a: int, salt_b: int = 0) -> int:
	return hash(Vector3i(_stage_seed_effective(), salt_a, salt_b))


func active_part_pickup_defs(defs: Array[Dictionary]) -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for d in defs:
		var pickup_id: StringName = d["pickup_id"] as StringName
		var part_id: StringName = d["part_id"] as StringName
		var persistence: StringName = d.get(
			"persistence",
			PartRegistry.PICKUP_PERSISTENCE_ONCE
		) as StringName
		if PartRegistry.should_skip_spawn_for_pickup_def(
			persistence, pickup_id, part_id, int(d.get("pickup_index", 0))
		):
			continue
		active.append(d)
	return active


func spawn_part_pickups_at_cells(
	defs: Array[Dictionary],
	cells_by_pickup_id: Dictionary,
	clear_radius_world: float = 8.0
) -> void:
	for def in defs:
		var pid: StringName = def["pickup_id"] as StringName
		if not cells_by_pickup_id.has(pid):
			continue
		var cell: Vector2i = cells_by_pickup_id[pid] as Vector2i
		var cw: Vector2 = cell_center_world(cell)
		clear_solid_in_circle_world(cw, clear_radius_world)
		var node: PartGroundPickup = _GENERIC_PART_GROUND_PICKUP.instantiate() as PartGroundPickup
		if node == null:
			continue
		node.pickup_id = pid
		node.part_id = def["part_id"] as StringName
		node.pickup_index = int(def.get("pickup_index", 0))
		node.persistence = def.get(
			"persistence",
			PartRegistry.PICKUP_PERSISTENCE_ONCE
		) as StringName
		node.global_position = cw
		add_child(node)
		var reveal_mode: StringName = def.get("spawn_reveal_mode", SPAWN_REVEAL_NORMAL) as StringName
		if reveal_mode == SPAWN_REVEAL_FULL:
			update_vision(cw, 1)
