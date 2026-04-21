extends Node

const LASER_TURRET_SCENE := preload("res://scenes/turrets/LaserTurret.tscn")

## World X for laser turret (left of playfield; viewport 1280-wide).
@export var laser_turret_position_x: float = 140.0
## Vertical spacing between multiple laser turrets.
@export var laser_turret_stack_spacing_y: float = 48.0

@onready var target_conveyor: TargetConveyor = %TargetConveyor
@onready var _turret_manager: Node2D = $GameRoot/World2D/TurretManager


func _ready() -> void:
	target_conveyor.ensure_targets_spawned()
	_sync_laser_turret_count()
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	if id == &"laser_count":
		_spawn_laser_turret()


func _desired_laser_turret_count() -> int:
	return 1 + UpgradeBus.get_level(&"laser_count")


func _sync_laser_turret_count() -> void:
	var want := _desired_laser_turret_count()
	while _turret_manager.get_child_count() < want:
		_spawn_laser_turret()


func _spawn_laser_turret() -> void:
	var idx := _turret_manager.get_child_count()
	var turret: Node2D = LASER_TURRET_SCENE.instantiate()
	turret.name = "LaserTurret_%d" % idx
	var y := target_conveyor.active_target_position.y + float(idx) * laser_turret_stack_spacing_y
	turret.position = Vector2(laser_turret_position_x, y)
	_turret_manager.add_child(turret)
