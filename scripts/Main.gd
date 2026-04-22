extends Control

## Pixels at bottom of window reserved for `BottomHUD`; 2D gameplay only uses area above.
const HUD_RESERVE_PX: int = 200
## Fixed game world resolution (width matches project; height leaves room above UI).
const GAME_VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720 - HUD_RESERVE_PX)
## World-space playfield the game is authored for. SubViewport can differ; camera zoom keeps this window filling the subviewport.
const GAMEPLAY_REFERENCE: Vector2i = Vector2i(1280, 520)

const LASER_TURRET_SCENE := preload("res://scenes/turrets/LaserTurret.tscn")
const CANNON_TURRET_SCENE := preload("res://scenes/turrets/CannonTurret.tscn")
@export var ship_type_id: StringName = &"scout"

@onready var target_conveyor: TargetConveyor = %TargetConveyor
@onready var _ship: Ship = %Ship
@onready var _viewport_info: Label = %ViewportInfo
@onready var _game_camera: Camera2D = %GameCamera2D
@onready var _game_subviewport: SubViewport = %GameSubViewport
@onready var _subviewport_container: SubViewportContainer = $GameplayBlock/AspectRatioContainer/ViewportFrame/SubViewportContainer


func _ready() -> void:
	_apply_game_viewport_layout()
	if _ship and _ship.ship_type_id != ship_type_id:
		_ship.ship_type_id = ship_type_id
		_ship.apply_type_from_id()
	target_conveyor.ensure_targets_spawned()
	_sync_ship_position()
	if not target_conveyor.active_target_changed.is_connected(_on_active_target_changed):
		target_conveyor.active_target_changed.connect(_on_active_target_changed)
	_sync_laser_turret_count()
	_sync_cannon_turret_count()
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	if _subviewport_container != null and not _subviewport_container.resized.is_connected(_on_subviewport_container_resized):
		_subviewport_container.resized.connect(_on_subviewport_container_resized)
	call_deferred("_apply_game_viewport_layout")


func _on_subviewport_container_resized() -> void:
	_apply_game_viewport_layout()


func _apply_game_viewport_layout() -> void:
	var block := get_node_or_null("GameplayBlock") as Control
	if block != null:
		block.offset_bottom = -float(HUD_RESERVE_PX)
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
	if _game_subviewport != null:
		_game_subviewport.size = Vector2i(w, h)
	if _game_camera != null and GAMEPLAY_REFERENCE.x > 0 and GAMEPLAY_REFERENCE.y > 0:
		# Center the reference playfield in the subviewport: screen center in world, zero offset in screen space.
		_game_camera.position = 0.5 * Vector2(GAMEPLAY_REFERENCE)
		_game_camera.offset = Vector2.ZERO
		_game_camera.zoom = Vector2(
			float(w) / float(GAMEPLAY_REFERENCE.x),
			float(h) / float(GAMEPLAY_REFERENCE.y)
		)
	if _viewport_info != null:
		var r := float(w) / float(h) if h != 0 else 0.0
		_viewport_info.text = "%d×%d px  •  W:H = %.4f:1" % [w, h, r]


func _physics_process(_delta: float) -> void:
	_sync_ship_position()


func _sync_ship_position() -> void:
	if _ship == null or target_conveyor == null:
		return
	_ship.global_position = Vector2(_ship.position_x, target_conveyor.global_position.y)


func _on_active_target_changed(_new_target: Node2D) -> void:
	_sync_ship_position()


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	if id == &"laser_count":
		_spawn_laser_turret()
	elif id == &"cannon_count":
		_spawn_cannon_turret()


func _desired_laser_turret_count() -> int:
	return 1 + UpgradeBus.get_level(&"laser_count")


func _sync_laser_turret_count() -> void:
	var want := _desired_laser_turret_count()
	while get_tree().get_nodes_in_group(&"laser_turrets").size() < want:
		if not _spawn_laser_turret():
			break


func _spawn_laser_turret() -> bool:
	if _ship == null:
		return false
	var slot := _ship.get_free_slot(&"small")
	if slot == null:
		return false
	var idx := get_tree().get_nodes_in_group(&"laser_turrets").size()
	var turret: Node2D = LASER_TURRET_SCENE.instantiate()
	turret.name = "LaserTurret_%d" % idx
	_ship.mount_turret(slot, turret)
	return true


func _desired_cannon_turret_count() -> int:
	return 1 + UpgradeBus.get_level(&"cannon_count")


func _sync_cannon_turret_count() -> void:
	var want := _desired_cannon_turret_count()
	while get_tree().get_nodes_in_group(&"cannon_turrets").size() < want:
		if not _spawn_cannon_turret():
			break


func _spawn_cannon_turret() -> bool:
	if _ship == null:
		return false
	var slot := _ship.get_free_slot(&"small")
	if slot == null:
		return false
	var idx := get_tree().get_nodes_in_group(&"cannon_turrets").size()
	var turret: Node2D = CANNON_TURRET_SCENE.instantiate()
	turret.name = "CannonTurret_%d" % idx
	_ship.mount_turret(slot, turret)
	return true
