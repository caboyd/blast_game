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
	# Hex hull, faces +X; fits V turret layout + center medium
	st.hull_polygon = PackedVector2Array(
		[
			Vector2(-80, 0),
			Vector2(-66, -54),
			Vector2(20, -62),
			Vector2(92, 0),
			Vector2(20, 62),
			Vector2(-66, 54),
		]
	)
	st.hull_color = Color(0.32, 0.38, 0.45, 1.0)
	# Five small in V toward +X; one medium at centroid (mount when game uses medium slots)
	st.slots = [
		{"size": &"small", "position": Vector2(54, 0), "stub": false},
		{"size": &"small", "position": Vector2(38, -26), "stub": false},
		{"size": &"small", "position": Vector2(22, -42), "stub": false},
		{"size": &"small", "position": Vector2(38, 26), "stub": false},
		{"size": &"small", "position": Vector2(22, 42), "stub": false},
		{"size": &"medium", "position": Vector2(2, 0), "stub": false},
	]
	return st
