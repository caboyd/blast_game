extends PlanetBase

## Planet 2: warped concentric ring biomes around chunk (0,0), monument
## placement per ring/sector slot, and a black-hole scene at the spawn chunk.

## Planet 2 warped-ring generation (distance in chunk space from origin).
const RING_0_MAX := 0.5
const RING_1_MAX := 2.5
const RING_2_MAX := 6.0
const WARP_SCALE := 4
const WARP_AMPLITUDE := 0.05
## Substrate noise scale in world cells; higher values produce larger, smoother regions.
const CELL_NOISE_SCALE := 140
const CELL_NOISE_X_MULTIPLIER := 11.31
const CELL_NOISE_Y_MULTIPLIER := 12.07
## In rings 0–2: base terrain (`bt`) when cellular noise ≤ this; harder substrate (`ht`) when noise is greater.
const RING_SUBSTRATE_HARD_NOISE_MIN := 0.18
## Ore tuning shared by every ring. *_NOISE_SCALE controls pattern size
## (lower = larger/smoother), *_RARITY_MIN controls how often deposits appear
## (higher = rarer), and shape thresholds control thickness/size inside deposits.
const RING_VEIN_TYPE := MiningWorld.TYPE_COPPER
const RING_VEIN_NOISE_SCALE := 0.045
const RING_VEIN_RARITY_SCALE := 0.012
const RING_VEIN_RARITY_MIN := 0.62
const RING_VEIN_ABS_MAX := 0.018
const RING_BLOB_TYPE := MiningWorld.TYPE_TIN
const RING_BLOB_NOISE_SCALE := 0.055
const RING_BLOB_RARITY_SCALE := 0.014
const RING_BLOB_RARITY_MIN := 0.68
const RING_BLOB_MIN := 0.56
const _MONUMENT_SCAN := int(ceili(RING_2_MAX)) + 20

const STATIC_CELLS: Array[Dictionary] = []

const PRIMARY_MATERIAL_TYPE := MiningWorld.TYPE_DIRT

## Edit colors here (int keys = `MiningWorld.TYPE_*`). Omitted types use `MiningWorld.TYPE_COLOR` at runtime.
const CELL_MATERIAL_COLORS: Dictionary = {
	MiningWorld.TYPE_EMPTY: Color(0.0, 0.0, 0.0, 0.0),
	MiningWorld.TYPE_DIRT: Color(0.843, 0.800, 0.784, 1.0),
	MiningWorld.TYPE_STONE: Color(0.52, 0.52, 0.55, 1.0),
	MiningWorld.TYPE_GOLD: Color(1.0, 0.82, 0.2, 1.0),
	MiningWorld.TYPE_FUEL: Color(0.22, 0.15, 0.10, 1.0),
	MiningWorld.TYPE_RUBY: Color(0.92, 0.18, 0.38, 1.0),
	MiningWorld.TYPE_PACKED_EARTH: Color(0.38, 0.32, 0.22, 1.0),
	MiningWorld.TYPE_CLAY: Color(0.553, 0.431, 0.388, 1.0),
	MiningWorld.TYPE_SHALE: Color(0.45, 0.46, 0.48, 1.0),
	MiningWorld.TYPE_COPPER: Color(0.72, 0.45, 0.22, 1.0),
	MiningWorld.TYPE_TIN: Color(0.62, 0.66, 0.72, 1.0),
	MiningWorld.TYPE_SANDSTONE: Color(0.243, 0.153, 0.137, 1.0),
	MiningWorld.TYPE_OBSIDIAN: Color(0.18, 0.12, 0.22, 1.0),
	MiningWorld.TYPE_IRON: Color(0.48, 0.28, 0.22, 1.0),
	MiningWorld.TYPE_SILVER: Color(0.88, 0.90, 0.92, 1.0),
}

@onready var _black_hole_sphere: BlackHoleSphere = %BlackHoleSphere
@onready var _black_hole_emitter: BlackHoleDebrisEmitter = %BlackHoleDebrisEmitter
@onready var _black_hole_currency_mgr: Node = %BlackHoleCurrencyManager

## Vector2i chunk → monument definition for this save’s layout.
var _monument_chunk_to_def: Dictionary = {}
var _monument_layout_resolved: bool = false


func _cell_material_colors() -> Dictionary:
	return CELL_MATERIAL_COLORS


func _debug_zoom_min() -> float:
	return 0.01


func _post_world_configure() -> void:
	_configure_black_hole_scene()


func _configure_black_hole_scene() -> void:
	if _mining_world == null:
		return
	var hole := MiningWorld.get_chunk_center_world(Vector2i.ZERO)
	var bh_radius := float(MiningWorld.CHUNK_SIZE) * MiningWorld.CELL_SIZE_PX * 0.25
	if _black_hole_sphere != null:
		_black_hole_sphere.global_position = hole
		_black_hole_sphere.configure_radius(bh_radius)
	if _black_hole_emitter != null:
		_black_hole_emitter.global_position = hole
		_black_hole_emitter.bind_mining_world(_mining_world)
		_black_hole_emitter.configure_event_horizon(bh_radius)
	if _black_hole_currency_mgr != null and _black_hole_currency_mgr.has_method(&"configure_hole_world_position"):
		_black_hole_currency_mgr.configure_hole_world_position(hole)


func _generate_mining_world_chunk(
	world: MiningWorld,
	chunk: Vector2i,
	rng: RandomNumberGenerator,
	chunk_data: Dictionary
) -> void:
	_ensure_monument_layout(world)
	var cn: FastNoiseLite = _make_noise(world, 501, 1.0)
	var vein_noise: FastNoiseLite = _make_noise(world, 601, 1.0)
	var vein_rarity_noise: FastNoiseLite = _make_noise(world, 602, 1.0)
	var blob_noise: FastNoiseLite = _make_noise(world, 603, 1.0)
	var blob_rarity_noise: FastNoiseLite = _make_noise(world, 604, 1.0)

	for ly in MiningWorld.CHUNK_SIZE:
		for lx in MiningWorld.CHUNK_SIZE:
			var wx: int = chunk.x * MiningWorld.CHUNK_SIZE + lx
			var wy: int = chunk.y * MiningWorld.CHUNK_SIZE + ly
			var ring_id: int = _biome_id_for_world_cell(wx, wy)
			var n_cell: float = cn.get_noise_2d(
				float(wx) / CELL_NOISE_SCALE * CELL_NOISE_X_MULTIPLIER,
				float(wy) / CELL_NOISE_SCALE * CELL_NOISE_Y_MULTIPLIER
			)
			var bt: int
			var ht: int
			match ring_id:
				0:
					bt = MiningWorld.TYPE_DIRT
					ht = MiningWorld.TYPE_PACKED_EARTH
				1:
					bt = MiningWorld.TYPE_CLAY
					ht = MiningWorld.TYPE_SHALE
				2:
					bt = MiningWorld.TYPE_SANDSTONE
					ht = MiningWorld.TYPE_OBSIDIAN
				_:
					bt = MiningWorld.TYPE_OBSIDIAN
					ht = MiningWorld.TYPE_OBSIDIAN
			var mat: int = ht if (ring_id < 3 and n_cell > RING_SUBSTRATE_HARD_NOISE_MIN) else bt
			if ring_id >= 3:
				mat = MiningWorld.TYPE_OBSIDIAN
			_set_local_cell(world, chunk_data, lx, ly, mat)

			var vein_rarity: float = vein_rarity_noise.get_noise_2d(float(wx) * RING_VEIN_RARITY_SCALE, float(wy) * RING_VEIN_RARITY_SCALE)
			var vein: float = vein_noise.get_noise_2d(float(wx) * RING_VEIN_NOISE_SCALE, float(wy) * RING_VEIN_NOISE_SCALE)
			if vein_rarity > RING_VEIN_RARITY_MIN and absf(vein) < RING_VEIN_ABS_MAX:
				_set_local_cell(world, chunk_data, lx, ly, RING_VEIN_TYPE)

			var blob_rarity: float = blob_rarity_noise.get_noise_2d(float(wx) * RING_BLOB_RARITY_SCALE, float(wy) * RING_BLOB_RARITY_SCALE)
			var blob: float = blob_noise.get_noise_2d(float(wx) * RING_BLOB_NOISE_SCALE, float(wy) * RING_BLOB_NOISE_SCALE)
			if blob_rarity > RING_BLOB_RARITY_MIN and blob > RING_BLOB_MIN:
				_set_local_cell(world, chunk_data, lx, ly, RING_BLOB_TYPE)

	if _monument_chunk_to_def.has(chunk):
		_stamp_monument(world, rng, chunk_data, _monument_chunk_to_def[chunk] as Dictionary)
	world.stamp_cell_overrides_for_chunk(chunk, STATIC_CELLS)


static func _make_noise(world: MiningWorld, salt: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = world.stage_rng_seed(salt & 65535, (salt >> 16) & 65535)
	n.frequency = frequency
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


func _warped_chunk_space_point(p: Vector2) -> Vector2:
	return Vector2(
		p.x + sin(p.y * TAU * WARP_SCALE) * WARP_AMPLITUDE,
		p.y + cos(p.x * TAU * WARP_SCALE) * WARP_AMPLITUDE
	)


func _warped_chunk_xy(chunk: Vector2i) -> Vector2:
	return _warped_chunk_space_point(Vector2(float(chunk.x) + 0.5, float(chunk.y) + 0.5))


func _warped_chunk_anchor() -> Vector2:
	## Rings must wrap chunk (0,0); naive `.length()` uses (0,0) in warped space, but warp moves the spawn chunk off the origin.
	return _warped_chunk_xy(Vector2i.ZERO)


func _warped_distance(chunk: Vector2i) -> float:
	return _warped_chunk_xy(chunk).distance_to(_warped_chunk_anchor())


func _biome_id_for_chunk(chunk: Vector2i) -> int:
	var d: float = _warped_distance(chunk)
	return _biome_id_for_warped_distance(d)


func _biome_id_for_world_cell(wx: int, wy: int) -> int:
	var p := Vector2(
		(float(wx) + 0.5) / float(MiningWorld.CHUNK_SIZE),
		(float(wy) + 0.5) / float(MiningWorld.CHUNK_SIZE)
	)
	var d: float = _warped_chunk_space_point(p).distance_to(_warped_chunk_anchor())
	return _biome_id_for_warped_distance(d)


func _biome_id_for_warped_distance(d: float) -> int:
	if d <= RING_0_MAX:
		return 0
	if d <= RING_1_MAX:
		return 1
	if d <= RING_2_MAX:
		return 2
	return 3


func _chunk_ring_sector(chunk: Vector2i) -> Vector2i:
	var rel := _warped_chunk_xy(chunk) - _warped_chunk_anchor()
	var d := rel.length()
	if d <= RING_0_MAX:
		return Vector2i(0, 0)
	if d <= RING_1_MAX:
		var ang := atan2(rel.y, rel.x)
		var sec := int(floor((ang + PI) / (PI * 0.5)))
		sec = ((sec % 4) + 4) % 4
		return Vector2i(1, sec)
	if d <= RING_2_MAX:
		var ang2 := atan2(rel.y, rel.x)
		var sec2 := int(floor((ang2 + PI) / (PI * 0.25)))
		sec2 = ((sec2 % 8) + 8) % 8
		return Vector2i(2, sec2)
	return Vector2i(-1, -1)


func _slot_matches_chunk(ring: int, sector: int, chunk: Vector2i) -> bool:
	var rs := _chunk_ring_sector(chunk)
	return rs.x == ring and rs.y == sector


func _biome_allowed(def: Dictionary, biome: int) -> bool:
	var ab: Variant = def.get("allowed_biomes", PackedInt32Array())
	if typeof(ab) != TYPE_PACKED_INT32_ARRAY:
		return true
	var arr := ab as PackedInt32Array
	if arr.is_empty():
		return true
	for i in arr.size():
		if int(arr[i]) == biome:
			return true
	return false


func _set_local_cell(world: MiningWorld, chunk_data: Dictionary, lx: int, ly: int, type_id: int) -> void:
	if lx < 0 or ly < 0 or lx >= MiningWorld.CHUNK_SIZE or ly >= MiningWorld.CHUNK_SIZE:
		return
	var idx: int = ly * MiningWorld.CHUNK_SIZE + lx
	var cells: PackedByteArray = chunk_data["cells"]
	var hparr: PackedByteArray = chunk_data["hp"]
	cells[idx] = type_id as int
	hparr[idx] = world._hp_for_type(type_id)


func _stamp_monument(
	world: MiningWorld, rng: RandomNumberGenerator, chunk_data: Dictionary, def: Dictionary
) -> void:
	var footprint: Variant = def.get("footprint", Vector2i(3, 3))
	var fp := footprint as Vector2i if footprint is Vector2i else Vector2i(3, 3)
	var style: StringName = def["stamping_style"] as StringName
	var tmpl: Array = def.get("template", []) as Array

	var ax: int = rng.randi_range(0, maxi(0, MiningWorld.CHUNK_SIZE - fp.x))
	var ay: int = rng.randi_range(0, maxi(0, MiningWorld.CHUNK_SIZE - fp.y))

	if style == &"clear_then_stamp":
		for fy in fp.y:
			for fx in fp.x:
				var cx: int = ax + fx
				var cy: int = ay + fy
				_set_local_cell(world, chunk_data, cx, cy, MiningWorld.TYPE_EMPTY)

	for e in tmpl:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var cel: Variant = e
		var d: Dictionary = cel as Dictionary
		var lx: int = ax + int(d["lx"])
		var ly: int = ay + int(d["ly"])
		var tid: int = int(d["type"])
		if style == &"stamp_only" or style == &"clear_then_stamp":
			_set_local_cell(world, chunk_data, lx, ly, tid)


func _mstub(
	id: StringName,
	category: StringName,
	rings: PackedInt32Array,
	biomes: PackedInt32Array,
	fp: Vector2i,
	style: StringName,
	tmpl: Array
) -> Dictionary:
	return {
		"id": id,
		"category": category,
		"allowed_rings": rings,
		"allowed_biomes": biomes,
		"footprint": fp,
		"stamping_style": style,
		"template": tmpl,
	}


func _monument_defs_uniques() -> Array[Dictionary]:
	var T := MiningWorld
	return [
		_mstub(
			&"p2_mu_r0_spawn",
			&"unique",
			PackedInt32Array([0]),
			PackedInt32Array([0]),
			Vector2i(4, 4),
			&"clear_then_stamp",
			[
				{"lx": 1, "ly": 1, "type": T.TYPE_PACKED_EARTH},
				{"lx": 2, "ly": 1, "type": T.TYPE_PACKED_EARTH},
				{"lx": 1, "ly": 2, "type": T.TYPE_DIRT},
				{"lx": 2, "ly": 2, "type": T.TYPE_SILVER},
			]
		),
		_mstub(
			&"p2_mu_r1_a",
			&"unique",
			PackedInt32Array([1]),
			PackedInt32Array([1, 2]),
			Vector2i(5, 5),
			&"stamp_only",
			[
				{"lx": 0, "ly": 0, "type": T.TYPE_CLAY}, {"lx": 4, "ly": 0, "type": T.TYPE_CLAY},
				{"lx": 2, "ly": 2, "type": T.TYPE_IRON}, {"lx": 1, "ly": 2, "type": T.TYPE_COPPER},
				{"lx": 3, "ly": 2, "type": T.TYPE_COPPER},
			]
		),
		_mstub(
			&"p2_mu_r2_a",
			&"unique",
			PackedInt32Array([2]),
			PackedInt32Array([2, 3]),
			Vector2i(6, 4),
			&"clear_then_stamp",
			[
				{"lx": 1, "ly": 1, "type": T.TYPE_SILVER}, {"lx": 2, "ly": 1, "type": T.TYPE_SILVER},
				{"lx": 3, "ly": 1, "type": T.TYPE_SILVER}, {"lx": 2, "ly": 2, "type": T.TYPE_OBSIDIAN},
			]
		),
		_mstub(
			&"p2_mu_r2_b",
			&"unique",
			PackedInt32Array([2]),
			PackedInt32Array([3]),
			Vector2i(4, 4),
			&"stamp_only",
			[
				{"lx": 1, "ly": 1, "type": T.TYPE_OBSIDIAN}, {"lx": 2, "ly": 1, "type": T.TYPE_IRON},
				{"lx": 1, "ly": 2, "type": T.TYPE_IRON}, {"lx": 2, "ly": 2, "type": T.TYPE_SILVER},
			]
		),
	]


func _monument_defs_rep_r1() -> Array[Dictionary]:
	var T := MiningWorld
	return [
		_mstub(&"p2_mr1_0", &"repeatable", PackedInt32Array([1]), PackedInt32Array([1]),
			Vector2i(3, 3), &"stamp_only", [{"lx": 1, "ly": 0, "type": T.TYPE_CLAY}, {"lx": 1, "ly": 2, "type": T.TYPE_TIN}]
		),
		_mstub(&"p2_mr1_1", &"repeatable", PackedInt32Array([1]), PackedInt32Array([1, 2]),
			Vector2i(3, 3), &"stamp_only", [{"lx": 0, "ly": 1, "type": T.TYPE_SHALE}, {"lx": 2, "ly": 1, "type": T.TYPE_COPPER}]
		),
		_mstub(&"p2_mr1_2", &"repeatable", PackedInt32Array([1]), PackedInt32Array([1]),
			Vector2i(3, 2), &"clear_then_stamp", [{"lx": 1, "ly": 0, "type": T.TYPE_SILVER}]
		),
	]


func _monument_defs_rep_r2() -> Array[Dictionary]:
	var T := MiningWorld
	return [
		_mstub(&"p2_mr2_0", &"repeatable", PackedInt32Array([2]), PackedInt32Array([2]),
			Vector2i(3, 3), &"stamp_only", [{"lx": 1, "ly": 1, "type": T.TYPE_SANDSTONE}]
		),
		_mstub(&"p2_mr2_1", &"repeatable", PackedInt32Array([2]), PackedInt32Array([2, 3]),
			Vector2i(3, 3), &"stamp_only", [{"lx": 1, "ly": 0, "type": T.TYPE_IRON}, {"lx": 1, "ly": 2, "type": T.TYPE_IRON}]
		),
		_mstub(&"p2_mr2_2", &"repeatable", PackedInt32Array([2]), PackedInt32Array([3]),
			Vector2i(3, 2), &"stamp_only", [{"lx": 0, "ly": 0, "type": T.TYPE_OBSIDIAN}, {"lx": 2, "ly": 1, "type": T.TYPE_SILVER}]
		),
		_mstub(&"p2_mr2_3", &"repeatable", PackedInt32Array([2]), PackedInt32Array([2]),
			Vector2i(4, 2), &"clear_then_stamp", [{"lx": 1, "ly": 0, "type": T.TYPE_TIN}]
		),
		_mstub(&"p2_mr2_4", &"repeatable", PackedInt32Array([2]), PackedInt32Array([2]),
			Vector2i(2, 4), &"stamp_only", [{"lx": 0, "ly": 2, "type": T.TYPE_COPPER}]
		),
		_mstub(&"p2_mr2_5", &"repeatable", PackedInt32Array([2]), PackedInt32Array([3]),
			Vector2i(2, 2), &"stamp_only", [{"lx": 0, "ly": 0, "type": T.TYPE_IRON}]
		),
	]


func _ensure_monument_layout(world: MiningWorld) -> void:
	if _monument_layout_resolved:
		return
	_monument_layout_resolved = true
	_monument_chunk_to_def.clear()

	var slots: Array[Dictionary] = []
	slots.append({"ring": 0, "sector": 0})
	for si in range(4):
		slots.append({"ring": 1, "sector": si})
	for si in range(8):
		slots.append({"ring": 2, "sector": si})

	var slot_assign: Array = []
	slot_assign.resize(slots.size())

	var remain: Array[Dictionary] = _monument_defs_uniques().duplicate()
	for si in slots.size():
		var ring_i: int = int(slots[si]["ring"])
		var picked_idx := -1
		for uu in remain.size():
			var defu: Dictionary = remain[uu]
			var rsa: PackedInt32Array = defu["allowed_rings"] as PackedInt32Array
			var hit := false
			for kk in rsa.size():
				if int(rsa[kk]) == ring_i:
					hit = true
					break
			if hit:
				picked_idx = uu
				break
		if picked_idx >= 0:
			slot_assign[si] = remain[picked_idx]
			remain.remove_at(picked_idx)

	var rep1 := _monument_defs_rep_r1()
	var rep2 := _monument_defs_rep_r2()
	var ci1 := 0
	var ci2 := 0
	for si in slots.size():
		if slot_assign[si] != null:
			continue
		var rl: int = int(slots[si]["ring"])
		if rl == 1:
			slot_assign[si] = rep1[ci1 % rep1.size()]
			ci1 += 1
		elif rl == 2:
			slot_assign[si] = rep2[ci2 % rep2.size()]
			ci2 += 1

	for si in slots.size():
		var sl: Dictionary = slots[si]
		var defsv: Variant = slot_assign[si]
		if defsv == null or typeof(defsv) != TYPE_DICTIONARY:
			continue
		var def_dict: Dictionary = defsv as Dictionary
		var cand_chunks: Array[Vector2i] = []
		for cy in range(-_MONUMENT_SCAN, _MONUMENT_SCAN + 1):
			for cx in range(-_MONUMENT_SCAN, _MONUMENT_SCAN + 1):
				var chk := Vector2i(cx, cy)
				if not _slot_matches_chunk(int(sl["ring"]), int(sl["sector"]), chk):
					continue
				if not _biome_allowed(def_dict, _biome_id_for_chunk(chk)):
					continue
				if _monument_chunk_to_def.has(chk):
					continue
				cand_chunks.append(chk)
		if cand_chunks.is_empty():
			for cy in range(-_MONUMENT_SCAN, _MONUMENT_SCAN + 1):
				for cx in range(-_MONUMENT_SCAN, _MONUMENT_SCAN + 1):
					var chk2 := Vector2i(cx, cy)
					if not _slot_matches_chunk(int(sl["ring"]), int(sl["sector"]), chk2):
						continue
					if _monument_chunk_to_def.has(chk2):
						continue
					cand_chunks.append(chk2)
		if cand_chunks.is_empty():
			continue
		var rng_place := RandomNumberGenerator.new()
		rng_place.seed = world.stage_rng_seed(31000 + int(sl["ring"]), int(sl["sector"]))
		var pick_ch: Vector2i = cand_chunks[rng_place.randi_range(0, cand_chunks.size() - 1)]
		_monument_chunk_to_def[pick_ch] = def_dict
