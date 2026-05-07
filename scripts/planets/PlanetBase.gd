extends Control
class_name PlanetBase

## Shared base for `Planet1`/`Planet2` (and future planets). Owns the viewport,
## camera, ship spawn + chain, mining-world wiring, audio hooks, hover overlay,
## and debug zoom. Subclasses provide planet-specific generation + decoration
## via the override hooks at the bottom of this file.

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
const DEBUG_CAMERA_ZOOM_MAX: float = 2.0

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

@export var planet_id: StringName = &""

@onready var _mining_world: MiningWorld = %MiningWorld
@onready var _ship_spawn: Node2D = %ShipSpawn
@onready var _game_sub_viewport: SubViewport = %GameSubViewport
@onready var _game_camera: Camera2D = %GameCamera2D
@onready var _subviewport_container: SubViewportContainer = $GameplayBlock/AspectRatioContainer/ViewportFrame/SubViewportContainer
@onready var _bottom_player_stats: BottomPlayerStatsStrip = get_node_or_null(
	"UI/BottomPlayerStats"
) as BottomPlayerStatsStrip
## Looked up via `find_child` rather than `%` because the labels live inside the
## instanced `ViewportInfoOverlay` scene, whose owner is the overlay root, not
## the planet root, so unique-name resolution wouldn't reach them otherwise.
var _viewport_info: Label
var _type_texture_info: Label
var _cell_hover_overlay: Label

var _ship: Node2D
var _ship_chain_followers: Array[ShipBase] = []
## Older positions first; tail segments sample arc length backward from live head along this polyline.
var _ship_chain_path: Array[Vector2] = []
var _ship_chain_follow_tick: _ShipChainFollowerTick

var _vp_w: int = 1280
var _vp_h: int = 720


func _ready() -> void:
	_viewport_info = find_child("ViewportInfo", true, false) as Label
	_type_texture_info = find_child("TypeTextureInfo", true, false) as Label
	_cell_hover_overlay = find_child("CellHoverOverlay", true, false) as Label
	AudioManager.set_drilling(false, Vector2.ZERO, false)
	MiningMissionUI.attach_fuel_bar_for_mining_host(self)
	GameSession.start_mission_timer()
	_apply_game_viewport_layout()
	if _mining_world:
		_mining_world.configure_stage_generation(planet_id, Callable(self, "_generate_mining_world_chunk"))
		_mining_world.set_cell_material_colors(_cell_material_colors_packed())
		if not _mining_world.block_broken.is_connected(_on_mining_block_broken_audio):
			_mining_world.block_broken.connect(_on_mining_block_broken_audio)
		if not _mining_world.type_texture_resized.is_connected(_on_mining_world_type_texture_resized):
			_mining_world.type_texture_resized.connect(_on_mining_world_type_texture_resized)
		_on_mining_world_type_texture_resized(_mining_world.get_type_texture_pixel_size())
		AudioManager.bind_world_audio_mount(_mining_world)
		_post_world_configure()
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
		_post_ship_spawn(spawn_world)
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
	if _mining_world != null and _mining_world.type_texture_resized.is_connected(_on_mining_world_type_texture_resized):
		_mining_world.type_texture_resized.disconnect(_on_mining_world_type_texture_resized)
	AudioManager.bind_world_audio_mount(null)


func _cell_material_colors_packed() -> PackedColorArray:
	var colors: Dictionary = _cell_material_colors()
	var out: PackedColorArray = PackedColorArray()
	out.resize(MiningWorld.TYPE_COUNT)
	for i in MiningWorld.TYPE_COUNT:
		out[i] = colors[i] if colors.has(i) else MiningWorld.TYPE_COLOR[i]
	return out


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
			push_warning("PlanetBase: tier-1 pickup unknown part_type for %s" % String(part_id))
			continue
		if pidx == 0:
			if type_slot >= ring.size():
				push_warning("PlanetBase: tier-1 ring has no cell for type slot %d" % type_slot)
				continue
			out_cells[pid] = ring[type_slot]
		else:
			if type_slot >= neighbors.size():
				push_warning("PlanetBase: tier-1 neighbor ring has no chunk for type slot %d" % type_slot)
				continue
			var ch: Vector2i = neighbors[type_slot]
			var rcell := RandomNumberGenerator.new()
			rcell.seed = _mining_world.stage_rng_seed(771903 + type_slot * 97 + pidx * 31, 404)
			out_cells[pid] = _mining_world.pick_random_cell_in_chunk(ch, rcell)


## Tier 1 only: pickup_index 0 = Chebyshev-8 ring around spawn; pickup_index 1 = random cell in a chunk adjacent to `(0,0)`.
func _spawn_part_pickups(spawn_world: Vector2) -> void:
	var defs: Array[Dictionary] = _part_pickup_defs()
	if defs.is_empty():
		return
	var active: Array[Dictionary] = _mining_world.active_part_pickup_defs(defs)
	if active.is_empty():
		return
	var tier1_active: Array[Dictionary] = []
	for d in active:
		var part_id_chk: StringName = d["part_id"] as StringName
		var tier: int = _tier_for_part_def(part_id_chk)
		if tier != 1:
			push_warning(
				"PlanetBase: skip %s - tier=%d has no ground spawns (only tier 1 does)"
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
		push_error("PlanetBase: no active ShipData")
		return
	var ps: Variant = sd.get("ship_scene")
	if ps == null or not (ps is PackedScene):
		push_error("PlanetBase: ShipData missing ship_scene")
		return
	_ship = (ps as PackedScene).instantiate() as Node2D
	if _ship == null or not _ship.has_method("carve_hull_terrain_on_spawn"):
		push_error("PlanetBase: ship_scene root must extend ShipBase")
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
		_debug_zoom_min(),
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
	var body: String = line1
	if _mining_world != null and _ship != null:
		var chunk: Vector2i = _mining_world.get_chunk_for_world_pos(_ship.global_position)
		var cell: Vector2i = _mining_world.world_pos_to_cell(_ship.global_position)
		var lx: int = cell.x - chunk.x * MiningWorld.CHUNK_SIZE
		var ly: int = cell.y - chunk.y * MiningWorld.CHUNK_SIZE
		body = "%s\nchunk (%d, %d)  •  in-chunk (%d, %d)" % [
			line1, chunk.x, chunk.y, lx, ly,
		]
	if _mining_world != null:
		body += "\nchunks stream +%d/s  −%d/s" % [
			_mining_world.get_chunk_stream_in_per_sec(),
			_mining_world.get_chunk_stream_out_per_sec(),
		]
	_viewport_info.text = body


func _on_mining_world_type_texture_resized(pixel_size: Vector2i) -> void:
	if _type_texture_info == null:
		return
	if pixel_size.x > 0 and pixel_size.y > 0:
		_type_texture_info.text = "type_tex %d×%d px" % [pixel_size.x, pixel_size.y]
	else:
		_type_texture_info.text = "type_tex —"


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


# ---------------------------------------------------------------------------
# Override hooks (subclasses fill these in).
# ---------------------------------------------------------------------------

## Per-cell-type display colors. Keys are `MiningWorld.TYPE_*` ints. Missing
## entries fall back to `MiningWorld.TYPE_COLOR`.
func _cell_material_colors() -> Dictionary:
	return {}


## Tier-1 part-pickup definitions for `_spawn_part_pickups`. Empty disables ground pickups.
func _part_pickup_defs() -> Array[Dictionary]:
	return []


## Lower bound for `GameStatistics.debug_camera_zoom_multiplier`.
func _debug_zoom_min() -> float:
	return 0.2


## Per-chunk generation. Subclasses MUST override to populate the world.
func _generate_mining_world_chunk(
	_world: MiningWorld,
	_chunk: Vector2i,
	_rng: RandomNumberGenerator,
	_chunk_data: Dictionary
) -> void:
	pass


## Called right after `MiningWorld` is configured + audio-bound, before the ship spawns.
func _post_world_configure() -> void:
	pass


## Called after the leading ship + chain + initial pickups are in place.
func _post_ship_spawn(_spawn_world: Vector2) -> void:
	pass
