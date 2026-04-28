extends Control

## Pixels at bottom of window reserved for `BottomHUD`; 2D gameplay only uses area above.
const HUD_RESERVE_PX: int = 200
const GAME_VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720 - HUD_RESERVE_PX)

const CELLS_PER_HALF_VIEW: int = 10
const CELL_SIZE_PX: float = 8.0

@export var planet_id: StringName = &"planet1"

@onready var _mining_world: MiningWorld = %MiningWorld
@onready var _ship_spawn: Node2D = %ShipSpawn
var _ship: Node2D
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
	_ship.position = Vector2.ZERO
	_ship_spawn.add_child(_ship)


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
