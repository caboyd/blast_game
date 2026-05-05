extends Node2D
class_name BlackHoleSphere

@export var sphere_color := Color(0.02, 0.025, 0.06, 1.0)
var radius_px: float = 16.0


func configure_radius(px: float) -> void:
	radius_px = maxf(px, 1.0)
	queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius_px, sphere_color)
