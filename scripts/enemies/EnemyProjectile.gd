class_name EnemyProjectile
extends Area2D

@export var speed: float = 260.0
@export var lifetime_s: float = 4.0
@export var damage: int = 5

var _dir: Vector2 = Vector2.LEFT
var _t: float = 0.0
var _visual: Polygon2D
var _collision_shape: CollisionShape2D


func _ready() -> void:
	add_to_group(&"enemy_projectiles")
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true
	_build_collision()
	_build_visual()


func initialize(world_pos: Vector2, direction: Vector2, speed_override: float, dmg: int, life: float) -> void:
	global_position = world_pos
	_dir = direction.normalized()
	speed = speed_override
	damage = dmg
	lifetime_s = life
	_t = 0.0


func get_damage() -> int:
	return damage


func _build_collision() -> void:
	_collision_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	_collision_shape.shape = circle
	add_child(_collision_shape)


func _build_visual() -> void:
	_visual = Polygon2D.new()
	_visual.color = Color(0.9, 0.2, 0.85, 1.0)
	_visual.polygon = _circle_poly(3.0, 10)
	add_child(_visual)


func _circle_poly(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime_s:
		queue_free()
		return
	position += _dir * speed * delta
