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
	var mid_y: float
	if conveyor != null:
		mid_y = conveyor.global_position.y
	else:
		var c := get_viewport().get_camera_2d()
		if c != null:
			mid_y = c.get_screen_center_position().y
		else:
			mid_y = vr.size.y * 0.5
	var y0 := mid_y - 180.0
	var y1 := mid_y - 80.0
	var y := randf_range(y0, y1)
	var right_world_x: float
	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.zoom.x > 0.0:
		right_world_x = cam.get_screen_center_position().x + vr.size.x * 0.5 / cam.zoom.x
	else:
		right_world_x = vr.position.x + vr.size.x
	enemy.global_position = Vector2(right_world_x + spawn_offscreen_px, y)
