class_name PartVisuals
extends RefCounted


static func attach_to_ship(ship: Node2D) -> void:
	if ship == null:
		return
	var chained_follower: bool = ship is ShipBase and (ship as ShipBase).follower_visual_only
	var treads_slot: Marker2D = _find_marker(ship, &"Attachment_Treads")
	var drill_slot: Marker2D = _find_marker(ship, &"Attachment_Drill")
	var fuel_tank_slot: Marker2D = _find_marker(ship, &"Attachment_FuelTank")
	if treads_slot == null or drill_slot == null or fuel_tank_slot == null:
		push_error(
			"PartVisuals: ship '%s' missing %%Attachment_Treads, %%Attachment_Drill, or %%Attachment_FuelTank (Marker2D)."
			% ship.name
		)
		return
	var treads_transform: Transform2D = _first_child_transform_or_identity(treads_slot)
	var drill_transform: Transform2D = _first_child_transform_or_identity(drill_slot)
	var fuel_tank_transform: Transform2D = _first_child_transform_or_identity(fuel_tank_slot)
	_clear_slot_children(treads_slot)
	_clear_slot_children(drill_slot)
	_clear_slot_children(fuel_tank_slot)
	_instantiate_part(treads_slot, &"treads", treads_transform)
	if chained_follower:
		return
	_instantiate_part(drill_slot, &"drill", drill_transform)
	_instantiate_part(fuel_tank_slot, &"fuel_tank", fuel_tank_transform)


static func _find_marker(ship: Node2D, marker_name: StringName) -> Marker2D:
	var unique_marker: Marker2D = ship.get_node_or_null(NodePath("%" + String(marker_name))) as Marker2D
	if unique_marker != null:
		return unique_marker
	return _find_marker_recursive(ship, marker_name)


static func _find_marker_recursive(node: Node, marker_name: StringName) -> Marker2D:
	for child in node.get_children():
		if child.name == marker_name and child is Marker2D:
			return child as Marker2D
		var nested: Marker2D = _find_marker_recursive(child, marker_name)
		if nested != null:
			return nested
	return null


static func _first_child_transform_or_identity(slot: Node2D) -> Transform2D:
	for child in slot.get_children():
		var child_2d: Node2D = child as Node2D
		if child_2d != null:
			return child_2d.transform
	return Transform2D.IDENTITY


static func _clear_slot_children(slot: Node2D) -> void:
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()


static func _instantiate_part(
	slot: Node2D, type_key: StringName, layout_transform: Transform2D
) -> void:
	var pid: StringName = PartRegistry.get_equipped_for_type_key(type_key)
	var pd: PartData = PartRegistry.get_part_data(pid)
	if pd == null or pd.visuals == null:
		return
	var ps: PackedScene = pd.visuals.ship_scene
	if ps == null:
		return
	var vis: Node2D = ps.instantiate() as Node2D
	if vis == null:
		return
	vis.transform = layout_transform
	slot.add_child(vis)
