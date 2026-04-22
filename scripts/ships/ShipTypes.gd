class_name ShipTypes
extends RefCounted

## Returns ship type preset; unknown id falls back to scout.
static func get_ship_type(type_id: StringName) -> ShipType:
	match type_id:
		&"scout":
			return _make_scout()
		_:
			return _make_scout()


static func _make_scout() -> ShipType:
	var st := ShipType.new()
	st.id = &"scout"
	st.display_name = "Scout"
	st.max_health = 100
	# Trapezoid-ish hull, ~120 wide, faces +X
	st.hull_polygon = PackedVector2Array(
		[
			Vector2(-58, -22),
			Vector2(32, -28),
			Vector2(52, -12),
			Vector2(52, 12),
			Vector2(32, 28),
			Vector2(-58, 22),
		]
	)
	st.hull_color = Color(0.32, 0.38, 0.45, 1.0)
	# Four small mountable on right flank; medium/large stubs (blocked for now)
	st.slots = [
		{"size": &"small", "position": Vector2(44, -30), "stub": false},
		{"size": &"small", "position": Vector2(48, -10), "stub": false},
		{"size": &"small", "position": Vector2(48, 10), "stub": false},
		{"size": &"small", "position": Vector2(44, 30), "stub": false},
		{"size": &"medium", "position": Vector2(-8, -38), "stub": true},
		{"size": &"large", "position": Vector2(-8, 38), "stub": true},
	]
	return st
