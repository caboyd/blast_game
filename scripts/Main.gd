extends Node

const LASER_TURRET_SCENE := preload("res://scenes/turrets/LaserTurret.tscn")
const CANNON_TURRET_SCENE := preload("res://scenes/turrets/CannonTurret.tscn")

## World X for laser turret column (left of playfield; viewport 1280-wide).
@export var laser_turret_position_x: float = 140.0
## Vertical spacing between turrets of the same type (even indices below center, odd above).
@export var laser_turret_stack_spacing_y: float = 48.0
@export var cannon_turret_stack_spacing_y: float = 48.0
## Half-width of `LaserTurret` Visual polygon (local ±this).
@export var laser_turret_body_half_width: float = 14.0
## Half-width of `CannonTurret` Visual polygon (local ±this).
@export var cannon_turret_body_half_width: float = 16.0

@onready var target_conveyor: TargetConveyor = %TargetConveyor
@onready var _turret_manager: Node2D = $GameRoot/World2D/TurretManager


func _ready() -> void:
	target_conveyor.ensure_targets_spawned()
	_sync_laser_turret_count()
	_sync_cannon_turret_count()
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)


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
		_spawn_laser_turret()


func _spawn_laser_turret() -> void:
	var idx := get_tree().get_nodes_in_group(&"laser_turrets").size()
	var turret: Node2D = LASER_TURRET_SCENE.instantiate()
	turret.name = "LaserTurret_%d" % idx
	var y := _turret_stack_y(target_conveyor.active_target_position.y, idx, laser_turret_stack_spacing_y)
	turret.position = Vector2(laser_turret_position_x, y)
	_turret_manager.add_child(turret)


func _desired_cannon_turret_count() -> int:
	return 1 + UpgradeBus.get_level(&"cannon_count")


func _sync_cannon_turret_count() -> void:
	var want := _desired_cannon_turret_count()
	while get_tree().get_nodes_in_group(&"cannon_turrets").size() < want:
		_spawn_cannon_turret()


func _spawn_cannon_turret() -> void:
	var idx := get_tree().get_nodes_in_group(&"cannon_turrets").size()
	var turret: Node2D = CANNON_TURRET_SCENE.instantiate()
	turret.name = "CannonTurret_%d" % idx
	var y := _turret_stack_y(target_conveyor.active_target_position.y, idx, cannon_turret_stack_spacing_y) + 0.5 * cannon_turret_stack_spacing_y
	turret.position = Vector2(_cannon_turret_center_x(), y)
	_turret_manager.add_child(turret)


## Even index: below `base_y`; odd index: above. New turrets attach to top or bottom of the column.
func _turret_stack_y(base_y: float, idx: int, spacing: float) -> float:
	if idx % 2 == 0:
		return base_y + float(idx >> 1) * spacing
	return base_y - float((idx + 1) >> 1) * spacing


## Cannon column sits left of lasers: gap = half stack spacing + both body half-widths.
func _cannon_turret_center_x() -> float:
	return laser_turret_position_x - (
		0.5 * laser_turret_stack_spacing_y + laser_turret_body_half_width + cannon_turret_body_half_width
	)
