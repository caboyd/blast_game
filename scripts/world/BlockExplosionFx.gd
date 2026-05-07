extends Node2D
## One-shot ring flash at world position; parented under `MiningWorld`.

const _FADE_S := 0.2

var _radius_px: float = 24.0
var _t: float = 0.0


func setup(radius_px: float) -> void:
	_radius_px = maxf(4.0, radius_px)


func _ready() -> void:
	z_index = 5
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= _FADE_S:
		queue_free()


func _draw() -> void:
	var a: float = clampf(1.0 - _t / _FADE_S, 0.0, 1.0)
	var c0 := Color(1.0, 0.58, 0.18, 0.62 * a)
	var c1 := Color(1.0, 0.85, 0.35, 0.38 * a)
	var r0: float = _radius_px * 0.28
	var r1: float = _radius_px * 0.72
	draw_arc(Vector2.ZERO, r0, 0.0, TAU, 40, c0, 2.4, true)
	draw_arc(Vector2.ZERO, r1, 0.0, TAU, 56, c1, 1.6, true)
