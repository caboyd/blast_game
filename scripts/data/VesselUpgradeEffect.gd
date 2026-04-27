class_name VesselUpgradeEffect
extends Resource

## Gameplay stat this effect modifies (e.g. &"mine_damage_per_tick", &"fuel_max").
@export var stat: StringName = &""
@export_enum("add", "multiply") var operation: String = "add"
@export var value: float = 0.0
@export var clamp_min: float = -1e20
@export var clamp_max: float = 1e20
