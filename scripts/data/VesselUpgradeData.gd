class_name VesselUpgradeData
extends Resource

@export var id: StringName = &""
@export var base_cost: int = 10
@export_enum("add", "multiply") var cost_operation: String = "multiply"
@export var cost_value: float = 1.1
## Inclusive max stored level; use -1 for unlimited (subject to money).
@export var max_level: int = -1
@export var effects: Array = []
