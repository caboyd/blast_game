extends Control

## Pixels at bottom of window reserved for `BottomHUD`; 2D gameplay only uses area above.
const HUD_RESERVE_PX: int = 200
const GAME_VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720 - HUD_RESERVE_PX)

const CELLS_PER_HALF_VIEW: int = 10
const CELL_SIZE_PX: float = 8.0

@export var planet_id: StringName = &"planet1"

@onready var _mining_grid: MiningGrid = %MiningGrid
@onready var _vessel: MiningVessel = %MiningVessel
@onready var _viewport_info: Label = %ViewportInfo
@onready var _game_camera: Camera2D = %GameCamera2D
@onready var _subviewport_container: SubViewportContainer = $GameplayBlock/AspectRatioContainer/ViewportFrame/SubViewportContainer
@onready var _bottom_hud: BottomHUD = get_node_or_null("UI/BottomHUD") as BottomHUD

var _vp_w: int = 1280
var _vp_h: int = 520


func _ready() -> void:
	GameSession.start_mission_timer()
	_apply_game_viewport_layout()
	if _mining_grid:
		_mining_grid.stage_id = planet_id
	if _vessel and _mining_grid:
		_vessel.grid = _mining_grid
		# Hull origin at the middle of chunk (0,0) in grid/world space.
		_vessel.position = _mining_grid.get_chunk_center_world(Vector2i.ZERO)
		_vessel.carve_hull_terrain_on_spawn()
	if _vessel and not _vessel.out_of_fuel.is_connected(_on_vessel_out_of_fuel):
		_vessel.out_of_fuel.connect(_on_vessel_out_of_fuel)
	if _subviewport_container != null and not _subviewport_container.resized.is_connected(_on_subviewport_container_resized):
		_subviewport_container.resized.connect(_on_subviewport_container_resized)
	if _bottom_hud != null:
		if not _bottom_hud.resized.is_connected(_on_bottom_hud_layout_changed):
			_bottom_hud.resized.connect(_on_bottom_hud_layout_changed)
		if not _bottom_hud.item_rect_changed.is_connected(_on_bottom_hud_layout_changed):
			_bottom_hud.item_rect_changed.connect(_on_bottom_hud_layout_changed)
	if not resized.is_connected(_on_main_resized_for_viewport):
		resized.connect(_on_main_resized_for_viewport)
	if not get_viewport().size_changed.is_connected(_on_main_resized_for_viewport):
		get_viewport().size_changed.connect(_on_main_resized_for_viewport)
	call_deferred("_apply_game_viewport_layout")


func _on_vessel_out_of_fuel() -> void:
	GameSession.end_current_run_to_prep()


func _on_subviewport_container_resized() -> void:
	_apply_game_viewport_layout()


func _on_bottom_hud_layout_changed() -> void:
	call_deferred("_apply_game_viewport_layout")


func _on_main_resized_for_viewport() -> void:
	call_deferred("_apply_game_viewport_layout")


func _hud_bottom_reserve_px() -> float:
	if _bottom_hud != null:
		return float(_bottom_hud.get_occlusion_bottom_reserve_px())
	return float(HUD_RESERVE_PX)


func _apply_game_viewport_layout() -> void:
	var block := get_node_or_null("GameplayBlock") as Control
	if block != null:
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
	if _game_camera == null or _vessel == null or _mining_grid == null:
		return
	_game_camera.global_position = _vessel.global_position
	var z: float = _game_camera.zoom.x
	if z <= 0.0:
		return
	var half := Vector2(float(_vp_w) / (2.0 * z), float(_vp_h) / (2.0 * z))
	var r := Rect2(_vessel.global_position - half, half * 2.0)
	_mining_grid.set_camera_view_world_rect(r)
