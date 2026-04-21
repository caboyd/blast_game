class_name CannonExplosionFX
extends Node2D
## Expanding ring filled with `color`; scales from 0 to `radius_px` world units, then frees itself.

const SEGMENTS := 40

@export var expand_duration_s: float = 0.32

var _fill: Polygon2D


static func spawn(parent: Node2D, world_pos: Vector2, radius_px: float, color: Color) -> void:
	var fx := CannonExplosionFX.new()
	parent.add_child(fx)
	fx.global_position = world_pos
	fx._begin(radius_px, color)


func _begin(radius_px: float, color: Color) -> void:
	z_index = 10
	_fill = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in SEGMENTS:
		var a := TAU * float(i) / float(SEGMENTS)
		pts.append(Vector2(cos(a), sin(a)))
	_fill.polygon = pts
	_fill.color = Color(color.r, color.g, color.b, 0.88)
	add_child(_fill)
	scale = Vector2.ZERO
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(radius_px, radius_px), expand_duration_s)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fill, "color:a", 0.0, expand_duration_s)
	tw.chain().tween_callback(queue_free)
