extends Node

const LASER_TURRET_SCENE := preload("res://scenes/turrets/LaserTurret.tscn")
const CANNON_TURRET_SCENE := preload("res://scenes/turrets/CannonTurret.tscn")
@export var ship_type_id: StringName = &"scout"

@onready var target_conveyor: TargetConveyor = %TargetConveyor
@onready var _ship: Ship = %Ship


func _ready() -> void:
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
