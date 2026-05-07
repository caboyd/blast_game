class_name ShipUpgradeData
extends Resource

@export var id: StringName = &""
## Prep shop text after the +value, e.g. "fuel max", "dmg/tick".
@export var shop_display_name: String = ""
## Extra prep copy when this upgrade has no stat `effects` (e.g. weapon system unlocks).
@export_multiline var shop_description: String = ""
@export var base_cost: int = 10
@export_enum("add", "multiply") var cost_operation: String = "multiply"
@export var cost_value: float = 1.1
## Inclusive max stored level; use -1 for unlimited (subject to money).
@export var max_level: int = -1
@export var effects: Array[ShipUpgradeEffect] = []
