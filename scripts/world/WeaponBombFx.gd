extends Node2D
## One-shot burst ring for the global Bomb weapon; parented under [member ShipBase.grid].

const _FADE_S := 0.22

var _radius_px: float = 32.0
var _t: float = 0.0


func setup(radius_px: float) -> void:
	_radius_px = maxf(4.0, radius_px)


func _ready() -> void:
	z_index = 6
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= _FADE_S:
		queue_free()


func _draw() -> void:
	var a: float = clampf(1.0 - _t / _FADE_S, 0.0, 1.0)
	var c0 := Color(0.35, 0.92, 1.0, 0.55 * a)
	var c1 := Color(1.0, 0.45, 0.15, 0.42 * a)
	var r0: float = _radius_px * 0.2
	var r1: float = _radius_px * 0.85
	draw_arc(Vector2.ZERO, r0, 0.0, TAU, 36, c0, 2.8, true)
	draw_arc(Vector2.ZERO, r1, 0.0, TAU, 64, c1, 2.0, true)
