class_name GlobalPartData
extends Resource

const TYPE_FUEL_TANK := &"fuel_tank"
const TYPE_DRILL := &"drill"
const TYPE_TREADS := &"treads"

@export var id: StringName = &""
@export_enum("fuel_tank", "drill", "treads") var part_type: String = "fuel_tank"
@export var display_name: String = ""

@export var prep_icon_scene: PackedScene
## Pickup in world (before collection).
@export var ground_scene: PackedScene
## Cosmetic attachment on ship.
@export var ship_scene: PackedScene

@export var effects: Array[GlobalPartEffect] = []

## If non-empty, drill mines only these `MiningWorld.TYPE_*` cell ids.
@export var allowed_mine_type_ids: PackedInt32Array = PackedInt32Array()

@export var movement_stop_every_s: float = 0.0
@export var movement_stop_duration_s: float = 0.0
