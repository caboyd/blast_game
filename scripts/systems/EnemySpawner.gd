extends Node

const BASIC_ENEMY_SCENE := preload("res://scenes/enemies/BasicEnemy.tscn")

@export var first_spawn_delay_s: float = 5.0
@export var spawn_interval_s: float = 30.0
@export var spawn_offscreen_px: float = 40.0

var _timer: Timer
var _enemy_manager: Node2D


func _ready() -> void:
	_enemy_manager = get_parent().get_node_or_null("EnemyManager") as Node2D
	if _enemy_manager == null:
		_enemy_manager = get_parent() as Node2D
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = first_spawn_delay_s
	add_child(_timer)
	_timer.timeout.connect(_on_first_timeout)
	_timer.start()


func _on_first_timeout() -> void:
	_spawn_enemy()
	_timer.timeout.disconnect(_on_first_timeout)
	_timer.timeout.connect(_on_repeating_spawn)
	_timer.wait_time = spawn_interval_s
	_timer.one_shot = false
	_timer.start()


func _on_repeating_spawn() -> void:
	_spawn_enemy()


func _spawn_enemy() -> void:
	var enemy: Node2D = BASIC_ENEMY_SCENE.instantiate()
	_enemy_manager.add_child(enemy)
	var vr := get_viewport().get_visible_rect()
	var conveyor := get_parent().get_node_or_null("TargetConveyor") as TargetConveyor
	var mid_y: float = 360.0
	if conveyor != null:
		mid_y = conveyor.global_position.y
	var y0 := mid_y - 180.0
	var y1 := mid_y - 80.0
	var y := randf_range(y0, y1)
	var x := vr.position.x + vr.size.x + spawn_offscreen_px
	enemy.global_position = Vector2(x, y)
