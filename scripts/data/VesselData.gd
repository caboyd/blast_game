class_name VesselData
extends Resource

@export var id: StringName = &"scout"
@export var display_name: String = "Mining Vessel"
@export var move_speed_px_s: float = 8.0
@export var vision_radius_cells: int = 3
@export var mine_damage_per_tick: float = 1.0
@export var mine_interval_s: float = 0.2
@export var fuel_max_base: float = 30.0
@export var upgrades: Array = []


func get_base_float_for_stat(stat: StringName) -> float:
	match String(stat):
		"mine_damage_per_tick":
			return mine_damage_per_tick
		"vision_radius_cells":
			return float(vision_radius_cells)
		"move_speed_px_s":
			return move_speed_px_s
		"fuel_max":
			return fuel_max_base
		"drill_range_bonus_game_px":
			return 0.0
		_:
			return 0.0
