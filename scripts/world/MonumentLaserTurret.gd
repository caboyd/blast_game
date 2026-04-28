class_name MonumentLaserTurret
extends Node2D

const ATTACK_RADIUS_CELLS: float = 6.0
const FUEL_PER_HIT: float = 2.0
const BEAM_DURATION_S: float = 0.12

var _ship: Node2D
var _beam_ttl: float = 0.0


func setup(ship: Node2D) -> void:
	_ship = ship
	set_process(true)


func pulse_fire_if_in_range() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var r: float = ATTACK_RADIUS_CELLS * MiningWorld.CELL_SIZE_PX
	if global_position.distance_to(_ship.global_position) > r:
		return
	GameStatistics.consume_fuel(FUEL_PER_HIT)
	_beam_ttl = BEAM_DURATION_S
	queue_redraw()


func _process(delta: float) -> void:
	if _beam_ttl > 0.0:
		_beam_ttl = maxf(0.0, _beam_ttl - delta)
		queue_redraw()


func _draw() -> void:
	if _ship == null or not is_instance_valid(_ship) or _beam_ttl <= 0.0:
		return
	var to_ship: Vector2 = to_local(_ship.global_position)
	draw_line(Vector2.ZERO, to_ship, Color(0.95, 0.12, 0.1, 0.9), 2.0)
