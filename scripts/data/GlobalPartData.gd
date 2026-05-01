class_name GlobalPartData
extends Resource

const TYPE_FUEL_TANK := &"fuel_tank"
const TYPE_DRILL := &"drill"
const TYPE_TREADS := &"treads"

@export var id: StringName = &""
@export_enum("fuel_tank", "drill", "treads") var part_type: String = "fuel_tank"
@export var display_name: String = ""

## Part line for UI / rules: `_t0` = 0, `_t1` = 1. Only tier 1 has world pickups (`pickup_index` 0 … `get_max_level()` − 1).
@export var tier: int = 0

@export var visuals: GlobalPartVisualData

## One entry per level: index 0 = level 1, index 1 = level 2, … `get_max_level()` is `maxi(1, size)`.
@export var effect_sets_by_level: Array[GlobalPartEffectSet] = []

## If non-empty, drill mines only these `MiningWorld.TYPE_*` cell ids.
@export var allowed_mine_type_ids: PackedInt32Array = PackedInt32Array()


func get_max_level() -> int:
	return maxi(1, effect_sets_by_level.size())


func get_effects_for_level(level: int) -> Array[GlobalPartEffect]:
	var mx: int = get_max_level()
	var idx: int = clampi(level, 1, mx) - 1
	if idx < 0 or idx >= effect_sets_by_level.size():
		return []
	var eset: GlobalPartEffectSet = effect_sets_by_level[idx]
	if eset == null:
		return []
	return eset.effects
