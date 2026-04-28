extends Control

class _ShipChainFollowerTick extends Node:
	var host: Node

	func _physics_process(delta: float) -> void:
		if host != null:
			host.call(&"update_mission_ship_chain_followers", delta)


## Pixels at bottom of window reserved for `BottomHUD`; 2D gameplay only uses area above.
const HUD_RESERVE_PX: int = 200
const GAME_VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720 - HUD_RESERVE_PX)

const CELLS_PER_HALF_VIEW: int = 10
const CELL_SIZE_PX: float = 8.0

@export var planet_id: StringName = &"planet1"

@onready var _mining_world: MiningWorld = %MiningWorld
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
@onready var _game_camera: Camera2D = %GameCamera2D
@onready var _subviewport_container: SubViewportContainer = $GameplayBlock/AspectRatioContainer/ViewportFrame/SubViewportContainer
@onready var _bottom_hud: BottomHUD = get_node_or_null("UI/BottomHUD") as BottomHUD

var _vp_w: int = 1280
var _vp_h: int = 520


func _ready() -> void:
	MiningMissionUI.attach_fuel_bar_for_mining_host(self)
	GameSession.start_mission_timer()
	_apply_game_viewport_layout()
	_spawn_mission_ship()
	if _mining_world:
		_mining_world.stage_id = planet_id
	if _ship and _mining_world:
		_ship.grid = _mining_world
		# Hull origin at the middle of chunk (0,0) in grid/world space.
		var spawn_world: Vector2 = MiningWorld.get_chunk_center_world(Vector2i.ZERO)
		_ship.position = spawn_world
		_layout_mission_ship_chain_followers_from_head()
		_mining_world.stamp_dirt_chebyshev_from_world(spawn_world, 4)
		_ship.carve_hull_terrain_on_spawn()
	if _ship and not _ship.out_of_fuel.is_connected(_on_ship_out_of_fuel):
		_ship.out_of_fuel.connect(_on_ship_out_of_fuel)
	if _subviewport_container != null and not _subviewport_container.resized.is_connected(_on_subviewport_container_resized):
		_subviewport_container.resized.connect(_on_subviewport_container_resized)
	if _bottom_hud != null:
		if not _bottom_hud.resized.is_connected(_on_bottom_hud_layout_changed):
			_bottom_hud.resized.connect(_on_bottom_hud_layout_changed)
		if not _bottom_hud.item_rect_changed.is_connected(_on_bottom_hud_layout_changed):
			_bottom_hud.item_rect_changed.connect(_on_bottom_hud_layout_changed)
	if not MiningMissionUI.top_fuel_layout_changed.is_connected(_on_top_fuel_bar_layout_changed):
		MiningMissionUI.top_fuel_layout_changed.connect(_on_top_fuel_bar_layout_changed)
	if not resized.is_connected(_on_main_resized_for_viewport):
		resized.connect(_on_main_resized_for_viewport)
	if not get_viewport().size_changed.is_connected(_on_main_resized_for_viewport):
		get_viewport().size_changed.connect(_on_main_resized_for_viewport)
	call_deferred("_apply_game_viewport_layout")


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
		push_error("Planet1: no active ShipData")
		return
	var ps: Variant = sd.get("ship_scene")
	if ps == null or not (ps is PackedScene):
		push_error("Planet1: ShipData missing ship_scene")
		return
	_ship = (ps as PackedScene).instantiate() as Node2D
	if _ship == null or not _ship.has_method("carve_hull_terrain_on_spawn"):
		push_error("Planet1: ship_scene root must extend ShipBase")
		return
	if _ship is Node:
		_ship.process_physics_priority = 1
	_ship.position = Vector2.ZERO
	_ship_spawn.add_child(_ship)
	var chain: Array[StringName] = ShipDataRegistry.get_mission_ship_chain_chain_ship_ids()
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


func _on_ship_out_of_fuel() -> void:
	GameSession.end_current_run_to_prep()


func _on_subviewport_container_resized() -> void:
	_apply_game_viewport_layout()


func _on_bottom_hud_layout_changed() -> void:
	call_deferred("_apply_game_viewport_layout")


func _on_top_fuel_bar_layout_changed() -> void:
	call_deferred("_apply_game_viewport_layout")


func _on_main_resized_for_viewport() -> void:
	call_deferred("_apply_game_viewport_layout")


func _hud_bottom_reserve_px() -> float:
	if _bottom_hud != null and _bottom_hud.is_inside_tree():
		return float(_bottom_hud.get_occlusion_bottom_reserve_px())
	return float(HUD_RESERVE_PX)


func _top_fuel_band_px() -> float:
	return MiningMissionUI.get_top_fuel_band_px()


func _apply_game_viewport_layout() -> void:
	var block := get_node_or_null("GameplayBlock") as Control
	if block != null:
		block.offset_top = _top_fuel_band_px()
		block.offset_bottom = -_hud_bottom_reserve_px()
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
		_game_camera.zoom = Vector2(z, z)
	if _viewport_info != null:
		var r := float(w) / float(h) if h != 0 else 0.0
		_viewport_info.text = "%d×%d px  •  W:H = %.4f:1" % [w, h, r]


func _physics_process(_delta: float) -> void:
	if _game_camera == null or _ship == null or _mining_world == null:
		return
	_game_camera.global_position = _ship.global_position
	var z: float = _game_camera.zoom.x
	if z <= 0.0:
		return
	var half := Vector2(float(_vp_w) / (2.0 * z), float(_vp_h) / (2.0 * z))
	var r := Rect2(_ship.global_position - half, half * 2.0)
	_mining_world.set_camera_view_world_rect(r)
