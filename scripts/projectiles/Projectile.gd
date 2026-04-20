class_name Projectile
extends Area2D

@export var speed: float = 900.0
@export var lifetime_s: float = 2.0

var _dir: Vector2 = Vector2.RIGHT
var _t: float = 0.0


func setup(direction: Vector2) -> void:
	_dir = direction.normalized()


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime_s:
		queue_free()
		return

	position += _dir * speed * delta
