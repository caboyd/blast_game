class_name MiningVessel
extends Node2D

## Local +X is forward (toward the cursor). Author Body/Arrow polygons in the scene; mining uses `global_position` only.

signal out_of_fuel

@export var move_speed_px_s: float = 8.0
@export var vision_radius_cells: int = 3
@export var mine_damage_per_tick: int = 9999

var grid: MiningGrid
var _fuel_out_emitted: bool = false


func _physics_process(delta: float) -> void:
	if grid == null:
		return
	var mouse := get_global_mouse_position()
	var dir := mouse - global_position
	if dir.length_squared() > 0.0001:
		rotation = dir.angle()
		global_position += dir.normalized() * move_speed_px_s * delta

	var hp_rm: int = grid.mine_cell_at_world_point(global_position, mine_damage_per_tick)
	if hp_rm > 0:
		GameStatistics.consume_fuel(float(hp_rm))

	grid.update_vision(global_position, vision_radius_cells)

	if GameStatistics.fuel <= 0.0 and not _fuel_out_emitted:
		_fuel_out_emitted = true
		out_of_fuel.emit()
