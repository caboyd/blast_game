class_name LaserTurret
extends Turret

const TARGET_SPOTTER_SCENE := preload("res://scenes/target/TargetSpotter.tscn")

@export var damage: int = 1
@export var update_frequency_hz: float = 10.0
@export var beam_color: Color = Color(1.0, 0.25, 0.25, 0.9)
@export var beam_width: float = 2.5
@export var spotter_line_width: float = 0.0

@onready var _beam: Line2D = $Beam

var _spotter: TargetSpotter

var _tick_accum: float = 0.0
var _conveyor: TargetConveyor


func _ready() -> void:
	process_priority = 1
	_conveyor = _resolve_conveyor()
	_spotter = TARGET_SPOTTER_SCENE.instantiate() as TargetSpotter
	_spotter.name = "TargetSpotter"
	_spotter.line_width = spotter_line_width
	var beam_idx := _beam.get_index()
	add_child(_spotter)
	move_child(_spotter, beam_idx)
	_beam.width = beam_width
	_beam.default_color = beam_color
	_beam.joint_mode = Line2D.LINE_JOINT_ROUND
	_beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_beam.end_cap_mode = Line2D.LINE_CAP_ROUND


func _resolve_conveyor() -> TargetConveyor:
	var p := get_parent()
	if p == null:
		return null
	var world := p.get_parent() as Node2D
	if world == null:
		return null
	return world.get_node_or_null("TargetConveyor") as TargetConveyor


func _process(delta: float) -> void:
	if _conveyor == null:
		_conveyor = _resolve_conveyor()
	if _conveyor == null:
		_clear_beam()
		_tick_accum = 0.0
		return

	var dt := _conveyor.get_active_target() as DestructibleTarget
	if dt == null or dt.is_destroyed():
		_clear_beam()
		_tick_accum = 0.0
		return

	var cell := _spotter.get_tracked_cell()
	if cell.x < 0 or not dt.is_cell_solid(cell):
		_clear_beam()
		_tick_accum = 0.0
		return

	var start_local := barrel.position
	var end_world := dt.to_global(dt.cell_center_local(cell))
	_beam.clear_points()
	_beam.add_point(start_local)
	_beam.add_point(to_local(end_world))

	_tick_accum += delta
	var interval := 1.0 / maxf(update_frequency_hz, 0.0001)
	while _tick_accum >= interval:
		_tick_accum -= interval
		if not is_instance_valid(dt) or dt.is_destroyed():
			break
		if not dt.is_cell_solid(cell):
			break
		dt.apply_damage_cell(cell, damage)
		if not dt.is_cell_solid(cell):
			break


func _clear_beam() -> void:
	_beam.clear_points()
