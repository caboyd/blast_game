class_name Turret
extends Node2D

## When true, draw attack-range debug rings on enemies and turrets that define range (DebugOverlay).
static var debug_show_attack_ranges: bool = false

@onready var barrel: Node2D = %Barrel


func _resolve_conveyor() -> TargetConveyor:
	var p: Node = self
	while p != null:
		var tc := p.get_node_or_null("TargetConveyor") as TargetConveyor
		if tc != null:
			return tc
		p = p.get_parent()
	return null


## Uses destructible slab row-leftmost cache when available; `from_local` in target space.
func pick_closest_row_leftmost_cell(dt: Node2D, from_local: Vector2) -> Vector2i:
	if dt == null:
		return Vector2i(-1, -1)
	if dt.has_method(&"is_destroyed") and bool(dt.call(&"is_destroyed")):
		return Vector2i(-1, -1)
	if not dt.has_method(&"get_closest_row_leftmost_cell"):
		return Vector2i(-1, -1)
	return dt.call(&"get_closest_row_leftmost_cell", from_local) as Vector2i
