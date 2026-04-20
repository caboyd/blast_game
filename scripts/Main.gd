extends Node

const LASER_TURRET_SCENE := preload("res://scenes/turrets/LaserTurret.tscn")

## World X for laser turret (left of playfield; viewport 1280-wide).
@export var laser_turret_position_x: float = 140.0

@onready var target_conveyor: TargetConveyor = %TargetConveyor
@onready var _turret_manager: Node2D = $GameRoot/World2D/TurretManager


func _ready() -> void:
	target_conveyor.ensure_targets_spawned()
	_spawn_laser_turret()


func _spawn_laser_turret() -> void:
	var turret: Node2D = LASER_TURRET_SCENE.instantiate()
	turret.name = "LaserTurret"
	var y := target_conveyor.active_target_position.y
	turret.position = Vector2(laser_turret_position_x, y)
	_turret_manager.add_child(turret)
