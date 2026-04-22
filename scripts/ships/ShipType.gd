class_name ShipType
extends Resource

## Unique id e.g. &"scout"
@export var id: StringName = &"scout"
@export var display_name: String = "Scout"
@export var max_health: int = 100
@export var hull_polygon: PackedVector2Array = PackedVector2Array()
@export var hull_color: Color = Color(0.35, 0.4, 0.48, 1.0)
## Each entry: { "size": &"small"|&"medium"|&"large", "position": Vector2, "stub": bool }
@export var slots: Array[Dictionary] = []
