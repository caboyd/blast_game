class_name ShipData
extends Resource

@export var id: StringName = &""
@export var display_name: String = "Ship"
@export var move_speed_px_s: float = 8.0
@export var vision_radius_cells: int = 3
@export var mine_damage_per_tick: float = 1.0
@export var mine_interval_s: float = 0.2
@export var fuel_max_base: float = 30.0
## Passive fuel drain while mining (units per second).
@export var fuel_drain_per_second: float = 1.0
@export var ship_scene: PackedScene
## When set, this ship is playable only when every upgrade on the prerequisite ship is maxed.
@export var unlock_after_ship_all_upgrades_maxed: StringName = &""
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
		"money_double_chance":
			return 0.0
		_:
			return 0.0
