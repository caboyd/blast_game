extends Control

class _ShipChainFollowerTick extends Node:
	var host: Node

	func _physics_process(delta: float) -> void:
		if host != null:
			host.call(&"update_mission_ship_chain_followers", delta)


## Internal SubViewport baseline; 16:9 ratio drives letterboxing via `AspectRatioContainer`.
const GAME_VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720)

const CELLS_PER_HALF_VIEW: int = 10
const CELL_SIZE_PX: float = 8.0
const DEBUG_CAMERA_ZOOM_STEP: float = 1.15
const DEBUG_CAMERA_ZOOM_MIN: float = 0.01
const DEBUG_CAMERA_ZOOM_MAX: float = 2.0

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


static func _cell_material_colors_packed() -> PackedColorArray:
	var out: PackedColorArray = PackedColorArray()
	out.resize(MiningWorld.TYPE_COUNT)
	for i in MiningWorld.TYPE_COUNT:
		out[i] = CELL_MATERIAL_COLORS[i] if CELL_MATERIAL_COLORS.has(i) else MiningWorld.TYPE_COLOR[i]
	return out

const PART_PICKUP_DEFS: Array[Dictionary] = []

@export var planet_id: StringName = &"planet2"

@onready var _mining_world: MiningWorld = %MiningWorld
@onready var _black_hole_sphere: BlackHoleSphere = %BlackHoleSphere
@onready var _black_hole_emitter: BlackHoleDebrisEmitter = %BlackHoleDebrisEmitter
@onready var _black_hole_currency_mgr: Node = %BlackHoleCurrencyManager
@onready var _ship_spawn: Node2D = %ShipSpawn
var _ship: Node2D
var _ship_chain_followers: Array[ShipBase] = []
## Older positions first; tail segments sample arc length backward from live head along this polyline.
var _ship_chain_path: Array[Vector2] = []
var _ship_chain_follow_tick: _ShipChainFollowerTick

const _MISSION_SHIP_CHAIN_FOLLOW_LERP := 16.0
const _MISSION_SHIP_CHAIN_PATH_MAX_POINTS := 4096
const _MISSION_SHIP_CHAIN_PATH_MIN_DIST_SQ := 1.0
const _MISSION_SHIP_CHAIN_PATH_TANGENT_DELTA_PX := 6.0
## Max rotation speed (rad/s) for the first chained ship; each further link is multiplied by `_MISSION_SHIP_CHAIN_TURN_RATE_LINK_FACTOR`.
const _MISSION_SHIP_CHAIN_TAIL_TURN_RATE_RAD_S := 5.5
## Per chain index: turn_rate *= factor^index (e.g. 0.7 → each segment turns 70% as fast as the one in front).
const _MISSION_SHIP_CHAIN_TURN_RATE_LINK_FACTOR := 0.68
## Floor so the last segments still steer (set 0 to allow arbitrarily slow tails).
const _MISSION_SHIP_CHAIN_TAIL_TURN_RATE_MIN_RAD_S := 0.35
@onready var _viewport_info: Label = %ViewportInfo
@onready var _cell_hover_overlay: Label = %CellHoverOverlay
@onready var _game_sub_viewport: SubViewport = %GameSubViewport
@onready var _game_camera: Camera2D = %GameCamera2D
@onready var _subviewport_container: SubViewportContainer = $GameplayBlock/AspectRatioContainer/ViewportFrame/SubViewportContainer
@onready var _bottom_player_stats: BottomPlayerStatsStrip = get_node_or_null(
	"UI/BottomPlayerStats"
) as BottomPlayerStatsStrip

var _vp_w: int = 1280
var _vp_h: int = 720
## Vector2i chunk → monument definition for this save’s layout.
var _monument_chunk_to_def: Dictionary = {}
var _monument_layout_resolved: bool = false


func _ready() -> void:
	AudioManager.set_drilling(false, Vector2.ZERO, false)
	MiningMissionUI.attach_fuel_bar_for_mining_host(self)
	GameSession.start_mission_timer()
	_apply_game_viewport_layout()
	if _mining_world:
		_mining_world.configure_stage_generation(planet_id, Callable(self, "_generate_mining_world_chunk"))
		var cell_colors: PackedColorArray = _cell_material_colors_packed()
		_mining_world.set_cell_material_colors(cell_colors)
		if not _mining_world.block_broken.is_connected(_on_mining_block_broken_audio):
			_mining_world.block_broken.connect(_on_mining_block_broken_audio)
		AudioManager.bind_world_audio_mount(_mining_world)
		_configure_black_hole_scene()
	_spawn_mission_ship()
	if _ship and _mining_world:
		_ship.grid = _mining_world
		# Hull origin at the middle of chunk (0,0) in grid/world space.
		var spawn_world: Vector2 = MiningWorld.get_chunk_center_world(Vector2i.ZERO)
		_ship.position = spawn_world
		_ship.add_to_group(&"leading_mining_ship")
		_layout_mission_ship_chain_followers_from_head()
		PartVisuals.attach_to_ship(_ship)
		for tail in _ship_chain_followers:
			PartVisuals.attach_to_ship(tail)
		_mining_world.stamp_dirt_chebyshev_from_world(spawn_world, 4)
		_ship.carve_hull_terrain_on_spawn()
		_spawn_part_pickups(spawn_world)
	if _ship and not _ship.out_of_fuel.is_connected(_on_ship_out_of_fuel):
		_ship.out_of_fuel.connect(_on_ship_out_of_fuel)
	if _bottom_player_stats != null:
		_bottom_player_stats.bind_leading_ship(_ship)
	if _subviewport_container != null and not _subviewport_container.resized.is_connected(_on_subviewport_container_resized):
		_subviewport_container.resized.connect(_on_subviewport_container_resized)
	if not resized.is_connected(_on_main_resized_for_viewport):
		resized.connect(_on_main_resized_for_viewport)
	if not get_viewport().size_changed.is_connected(_on_main_resized_for_viewport):
		get_viewport().size_changed.connect(_on_main_resized_for_viewport)
	call_deferred("_apply_game_viewport_layout")


func _exit_tree() -> void:
	AudioManager.bind_world_audio_mount(null)


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


func _tier_for_part_def(part_id: StringName) -> int:
	var pd: PartData = PartRegistry.get_part_data(part_id)
	if pd == null:
		return 0
	return int(pd.tier)


func _pickup_type_slot_index(part_id: StringName) -> int:
	var pd: PartData = PartRegistry.get_part_data(part_id)
	if pd == null:
		return -1
	match String(pd.part_type):
		"fuel_tank":
			return 0
		"drill":
			return 1
		"treads":
			return 2
		_:
			return -1


func _neighbor_chunks_chebyshev1(origin_chunk: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			out.append(origin_chunk + Vector2i(dx, dy))
	return out


func _shuffle_chebyshev8_ring(origin_cell: Vector2i, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var ring: Array[Vector2i] = []
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			if maxi(abs(dx), abs(dy)) != 8:
				continue
			ring.append(origin_cell + Vector2i(dx, dy))
	for ii in range(ring.size() - 1, 0, -1):
		var jj: int = rng.randi_range(0, ii)
		var swap: Vector2i = ring[ii]
		ring[ii] = ring[jj]
		ring[jj] = swap
	return ring


func _assign_tier1_pickup_cells(
	defs: Array[Dictionary],
	spawn_world: Vector2,
	rng_ring: RandomNumberGenerator,
	rng_far: RandomNumberGenerator,
	out_cells: Dictionary
) -> void:
	var origin_cell := _mining_world.world_pos_to_cell(spawn_world)
	var ring: Array[Vector2i] = _shuffle_chebyshev8_ring(origin_cell, rng_ring)
	var neighbors: Array[Vector2i] = _neighbor_chunks_chebyshev1(Vector2i.ZERO)
	for ii in range(neighbors.size() - 1, 0, -1):
		var jj: int = rng_far.randi_range(0, ii)
		var nswap: Vector2i = neighbors[ii]
		neighbors[ii] = neighbors[jj]
		neighbors[jj] = nswap

	for d in defs:
		var pid: StringName = d["pickup_id"] as StringName
		var part_id: StringName = d["part_id"] as StringName
		var pidx: int = int(d.get("pickup_index", 0))
		var type_slot: int = _pickup_type_slot_index(part_id)
		if type_slot < 0:
			push_warning("Planet2: tier-1 pickup unknown part_type for %s" % String(part_id))
			continue
		if pidx == 0:
			if type_slot >= ring.size():
				push_warning("Planet2: tier-1 ring has no cell for type slot %d" % type_slot)
				continue
			out_cells[pid] = ring[type_slot]
		else:
			if type_slot >= neighbors.size():
				push_warning("Planet2: tier-1 neighbor ring has no chunk for type slot %d" % type_slot)
				continue
			var ch: Vector2i = neighbors[type_slot]
			var rcell := RandomNumberGenerator.new()
			rcell.seed = _mining_world.stage_rng_seed(771903 + type_slot * 97 + pidx * 31, 404)
			out_cells[pid] = _mining_world.pick_random_cell_in_chunk(ch, rcell)


## Tier 1 only: pickup_index 0 = Chebyshev-8 ring around spawn; pickup_index 1 = random cell in a chunk adjacent to `(0,0)`.
func _spawn_part_pickups(spawn_world: Vector2) -> void:
	var active: Array[Dictionary] = _mining_world.active_part_pickup_defs(PART_PICKUP_DEFS)
	if active.is_empty():
		return
	var tier1_active: Array[Dictionary] = []
	for d in active:
		var part_id_chk: StringName = d["part_id"] as StringName
		var tier: int = _tier_for_part_def(part_id_chk)
		if tier != 1:
			push_warning(
				"Planet2: skip %s - tier=%d has no ground spawns (only tier 1 does)"
				% [String(part_id_chk), tier]
			)
			continue
		tier1_active.append(d)
	if tier1_active.is_empty():
		return
	var cells_by_pickup_id: Dictionary = {}
	var rng_ring := RandomNumberGenerator.new()
	rng_ring.seed = _mining_world.stage_rng_seed(771001, 42)
	var rng_far := RandomNumberGenerator.new()
	rng_far.seed = _mining_world.stage_rng_seed(771002, 43)
	_assign_tier1_pickup_cells(tier1_active, spawn_world, rng_ring, rng_far, cells_by_pickup_id)
	_mining_world.spawn_part_pickups_at_cells(tier1_active, cells_by_pickup_id, 8.0)


func _spawn_mission_ship() -> void:
	if _ship_spawn == null:
		return
	_ship_chain_followers.clear()
	_ship_chain_path.clear()
	for c in _ship_spawn.get_children():
		c.queue_free()
	_ship = null
	var sd: Resource = ShipDataRegistry.get_active()
	if sd == null:
		push_error("Planet2: no active ShipData")
		return
	var ps: Variant = sd.get("ship_scene")
	if ps == null or not (ps is PackedScene):
		push_error("Planet2: ShipData missing ship_scene")
		return
	_ship = (ps as PackedScene).instantiate() as Node2D
	if _ship == null or not _ship.has_method("carve_hull_terrain_on_spawn"):
		push_error("Planet2: ship_scene root must extend ShipBase")
		return
	if _ship is Node:
		_ship.process_physics_priority = 1
	_ship.position = Vector2.ZERO
	_ship_spawn.add_child(_ship)
	var chain: Array[StringName] = ShipDataRegistry.get_mission_ship_chain_ship_ids()
	for i in range(1, chain.size()):
		var sid: StringName = chain[i]
		var sdata: Resource = ShipDataRegistry.get_ship_data(sid)
		if sdata == null:
			continue
		var tps: Variant = sdata.get("ship_scene")
		if tps == null or not (tps is PackedScene):
			continue
		var tail: ShipBase = (tps as PackedScene).instantiate() as ShipBase
		if tail == null:
			continue
		tail.follower_visual_only = true
		tail.scale = Vector2.ONE * ShipChainLayout.FOLLOWER_SCALE
		_ship_spawn.add_child(tail)
		_ship_chain_followers.append(tail)
	_ship_chain_follow_tick = _ShipChainFollowerTick.new()
	_ship_chain_follow_tick.name = "ShipChainFollowerTick"
	_ship_chain_follow_tick.host = self
	_ship_chain_follow_tick.process_physics_priority = 0
	_ship_spawn.add_child(_ship_chain_follow_tick)


func _layout_mission_ship_chain_followers_from_head() -> void:
	if _ship == null:
		return
	_ship_chain_path.clear()
	_ship_chain_path.append(_ship.global_position)
	var prev: Node2D = _ship
	for tail in _ship_chain_followers:
		var back: Vector2 = -prev.global_transform.x.normalized()
		tail.global_position = prev.global_position + back * ShipChainLayout.SEGMENT_SPACING_PX
		tail.rotation = prev.rotation
		prev = tail


func _mission_ship_chain_record_head_sample() -> void:
	if _ship == null:
		return
	var p: Vector2 = _ship.global_position
	if _ship_chain_path.is_empty():
		_ship_chain_path.append(p)
		return
	if p.distance_squared_to(_ship_chain_path[_ship_chain_path.size() - 1]) < _MISSION_SHIP_CHAIN_PATH_MIN_DIST_SQ:
		return
	_ship_chain_path.append(p)
	while _ship_chain_path.size() > _MISSION_SHIP_CHAIN_PATH_MAX_POINTS:
		_ship_chain_path.pop_front()


func _mission_ship_chain_point_at_distance_back_from_tip(dist: float) -> Vector2:
	if _ship == null:
		return Vector2.ZERO
	var tip: Vector2 = _ship.global_position
	if dist <= 0.0:
		return tip
	var remaining: float = dist
	var prev: Vector2 = tip
	var idx: int = _ship_chain_path.size() - 1
	while idx >= 0:
		var cur: Vector2 = _ship_chain_path[idx]
		var seg_len: float = prev.distance_to(cur)
		if seg_len < 1e-5:
			prev = cur
			idx -= 1
			continue
		if remaining <= seg_len:
			return prev.lerp(cur, remaining / seg_len)
		remaining -= seg_len
		prev = cur
		idx -= 1
	return prev


func _mission_ship_chain_path_tangent_toward_head(dist_along_path: float) -> Vector2:
	var p_here: Vector2 = _mission_ship_chain_point_at_distance_back_from_tip(dist_along_path)
	var p_closer: Vector2 = _mission_ship_chain_point_at_distance_back_from_tip(
		maxf(dist_along_path - _MISSION_SHIP_CHAIN_PATH_TANGENT_DELTA_PX, 0.0)
	)
	return p_closer - p_here


func update_mission_ship_chain_followers(delta: float) -> void:
	if _ship == null or _ship_chain_followers.is_empty():
		return
	_mission_ship_chain_record_head_sample()
	var t: float = clampf(_MISSION_SHIP_CHAIN_FOLLOW_LERP * delta, 0.0, 1.0)
	var chain_i: int = 0
	for tail in _ship_chain_followers:
		var dist_along: float = ShipChainLayout.SEGMENT_SPACING_PX * float(chain_i + 1)
		var target_pos: Vector2 = _mission_ship_chain_point_at_distance_back_from_tip(dist_along)
		tail.global_position = tail.global_position.lerp(target_pos, t)
		var tang: Vector2 = _mission_ship_chain_path_tangent_toward_head(dist_along)
		if tang.length_squared() <= 0.25:
			tang = target_pos - tail.global_position
		if tang.length_squared() > 0.25:
			var target_rot: float = tang.angle()
			var turn_cap: float = (
				_MISSION_SHIP_CHAIN_TAIL_TURN_RATE_RAD_S
				* pow(_MISSION_SHIP_CHAIN_TURN_RATE_LINK_FACTOR, float(chain_i))
			)
			turn_cap = maxf(turn_cap, _MISSION_SHIP_CHAIN_TAIL_TURN_RATE_MIN_RAD_S)
			tail.rotation = rotate_toward(tail.rotation, target_rot, turn_cap * delta)
		chain_i += 1


func _on_mining_block_broken_audio(world_pos: Vector2, _type_id: int) -> void:
	AudioManager.play_dirt_fall(world_pos)


func _on_ship_out_of_fuel() -> void:
	GameSession.end_current_run_to_prep()


func _on_subviewport_container_resized() -> void:
	_apply_game_viewport_layout()


func _on_main_resized_for_viewport() -> void:
	call_deferred("_apply_game_viewport_layout")


func _apply_game_viewport_layout() -> void:
	var block := get_node_or_null("GameplayBlock") as Control
	if block != null:
		block.offset_top = 0.0
		block.offset_bottom = 0.0
	var ar := get_node_or_null("GameplayBlock/AspectRatioContainer") as AspectRatioContainer
	if ar != null:
		ar.ratio = float(GAME_VIEWPORT_SIZE.x) / float(GAME_VIEWPORT_SIZE.y)
		ar.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
		ar.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
		ar.stretch_mode = AspectRatioContainer.STRETCH_FIT
	var w: int = 0
	var h: int = 0
	if _subviewport_container != null:
		w = maxi(1, int(floorf(_subviewport_container.size.x)))
		h = maxi(1, int(floorf(_subviewport_container.size.y)))
	else:
		w = int(GAME_VIEWPORT_SIZE.x)
		h = int(GAME_VIEWPORT_SIZE.y)
	_vp_w = w
	_vp_h = h
	if _game_camera != null and w > 0 and h > 0:
		var z: float = float(mini(w, h)) / (CELL_SIZE_PX * float(CELLS_PER_HALF_VIEW * 2))
		_game_camera.zoom = Vector2(z, z) * GameStatistics.debug_camera_zoom_multiplier
	_refresh_viewport_info()


func adjust_debug_camera_zoom(step_delta: int) -> float:
	GameStatistics.debug_camera_zoom_multiplier = clampf(
		GameStatistics.debug_camera_zoom_multiplier * pow(DEBUG_CAMERA_ZOOM_STEP, float(step_delta)),
		DEBUG_CAMERA_ZOOM_MIN,
		DEBUG_CAMERA_ZOOM_MAX
	)
	_apply_game_viewport_layout()
	GameStatistics.save_debug_preferences()
	return GameStatistics.debug_camera_zoom_multiplier


func get_debug_camera_zoom_multiplier() -> float:
	return GameStatistics.debug_camera_zoom_multiplier


func _refresh_viewport_info() -> void:
	if _viewport_info == null:
		return
	var w: int = _vp_w
	var h: int = _vp_h
	var r: float = float(w) / float(h) if h != 0 else 0.0
	var line1: String = "%d×%d px  •  W:H = %.4f:1" % [w, h, r]
	if _mining_world != null and _ship != null:
		var chunk: Vector2i = _mining_world.get_chunk_for_world_pos(_ship.global_position)
		var cell: Vector2i = _mining_world.world_pos_to_cell(_ship.global_position)
		var lx: int = cell.x - chunk.x * MiningWorld.CHUNK_SIZE
		var ly: int = cell.y - chunk.y * MiningWorld.CHUNK_SIZE
		_viewport_info.text = "%s\nchunk (%d, %d)  •  in-chunk (%d, %d)" % [
			line1, chunk.x, chunk.y, lx, ly,
		]
	else:
		_viewport_info.text = line1


func _mouse_world_on_game_viewport() -> Vector2:
	if _game_sub_viewport == null or _subviewport_container == null:
		return Vector2(NAN, NAN)
	var mouse_root: Vector2 = get_viewport().get_mouse_position()
	var gr: Rect2 = _subviewport_container.get_global_rect()
	if not gr.has_point(mouse_root):
		return Vector2(NAN, NAN)
	var loc: Vector2 = mouse_root - gr.position
	var vs: Vector2 = Vector2(_game_sub_viewport.get_visible_rect().size)
	var container_size: Vector2 = gr.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return Vector2(NAN, NAN)
	var sub_pixel := Vector2(
		loc.x / container_size.x * vs.x,
		loc.y / container_size.y * vs.y,
	)
	var inv: Transform2D = _game_sub_viewport.get_canvas_transform().affine_inverse()
	return inv * sub_pixel


func _refresh_cell_hover_overlay() -> void:
	if _cell_hover_overlay == null or _mining_world == null:
		return
	var w: Vector2 = _mouse_world_on_game_viewport()
	if not w.is_finite():
		_cell_hover_overlay.text = ""
		return
	var cell: Vector2i = _mining_world.world_pos_to_cell(w)
	var tid: int = _mining_world.get_cell_type_at(cell)
	var tnm: String = _mining_world.describe_cell_type(tid)
	_cell_hover_overlay.text = "cell (%d, %d)  •  %s  (type %d)" % [cell.x, cell.y, tnm, tid]


func _physics_process(_delta: float) -> void:
	if _game_camera == null or _ship == null or _mining_world == null:
		if _cell_hover_overlay != null:
			_cell_hover_overlay.text = ""
		return
	_game_camera.global_position = _ship.global_position
	var z: float = _game_camera.zoom.x
	if z <= 0.0:
		if _cell_hover_overlay != null:
			_cell_hover_overlay.text = ""
		return
	var half := Vector2(float(_vp_w) / (2.0 * z), float(_vp_h) / (2.0 * z))
	var r := Rect2(_ship.global_position - half, half * 2.0)
	_mining_world.set_camera_view_world_rect(r)
	_refresh_viewport_info()
	_refresh_cell_hover_overlay()
