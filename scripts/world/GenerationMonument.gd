class_name GenerationMonument
extends Node2D

## 5×5 cells on grid; half-extent in pixels (2.5 × cell).
const BUILDING_HALF_PX: float = 2.5 * MiningWorld.CELL_SIZE_PX
const PULSE_INTERVAL_S: float = 1.0

var _ship: ShipBase
var _turrets: Array[MonumentLaserTurret] = []
var _pulse_accum: float = 0.0


func setup(ship: ShipBase, center_world: Vector2) -> void:
	_ship = ship
	global_position = center_world
	z_index = 1

	var poly := Polygon2D.new()
	poly.color = Color(0.48, 0.74, 0.96, 0.78)
	poly.polygon = PackedVector2Array([
		Vector2(-BUILDING_HALF_PX, -BUILDING_HALF_PX),
		Vector2(BUILDING_HALF_PX, -BUILDING_HALF_PX),
		Vector2(BUILDING_HALF_PX, BUILDING_HALF_PX),
		Vector2(-BUILDING_HALF_PX, BUILDING_HALF_PX),
	])
	add_child(poly)

	var corners: Array[Vector2] = [
		Vector2(-BUILDING_HALF_PX, -BUILDING_HALF_PX),
		Vector2(BUILDING_HALF_PX, -BUILDING_HALF_PX),
		Vector2(BUILDING_HALF_PX, BUILDING_HALF_PX),
		Vector2(-BUILDING_HALF_PX, BUILDING_HALF_PX),
	]
	for c: Vector2 in corners:
		var t := MonumentLaserTurret.new()
		t.position = c
		t.setup(ship)
		add_child(t)
		_turrets.append(t)
	set_process(true)


func _process(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	_pulse_accum += delta
	if _pulse_accum >= PULSE_INTERVAL_S:
		_pulse_accum -= PULSE_INTERVAL_S
		for t in _turrets:
			t.pulse_fire_if_in_range()
