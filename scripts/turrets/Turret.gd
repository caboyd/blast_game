class_name Turret
extends Node2D

@onready var barrel: Node2D = %Barrel


## Uses DestructibleTarget row-leftmost cache; `from_local` in target space (e.g. `dt.to_local(global_position)`).
func pick_closest_row_leftmost_cell(dt: DestructibleTarget, from_local: Vector2) -> Vector2i:
	if dt == null or dt.is_destroyed():
		return Vector2i(-1, -1)
	return dt.get_closest_row_leftmost_cell(from_local)
