class_name GlobalPartData
extends Resource

const TYPE_FUEL_TANK := &"fuel_tank"
const TYPE_DRILL := &"drill"
const TYPE_TREADS := &"treads"

@export var id: StringName = &""
@export_enum("fuel_tank", "drill", "treads") var part_type: String = "fuel_tank"
@export var display_name: String = ""

@export var max_level: int = 1
## Part line for UI / rules: `_t0` = 0, `_t1` = 1. Only tier 1 has world pickups (`pickup_index` 0 … max_level−1).
@export var tier: int = 0

@export var visuals: GlobalPartVisualData

@export var effects: Array[GlobalPartEffect] = []

## If non-empty, drill mines only these `MiningWorld.TYPE_*` cell ids.
@export var allowed_mine_type_ids: PackedInt32Array = PackedInt32Array()
