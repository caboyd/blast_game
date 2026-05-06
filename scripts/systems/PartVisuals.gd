class_name PartVisuals
extends RefCounted


static func attach_to_ship(ship: Node2D) -> void:
	if ship == null:
		return
	var chained_follower: bool = ship is ShipBase and (ship as ShipBase).follower_visual_only
	var treads_slot: Marker2D = ship.get_node_or_null(^"%Attachment_Treads") as Marker2D
	var drill_slot: Marker2D = ship.get_node_or_null(^"%Attachment_Drill") as Marker2D
	var fuel_tank_slot: Marker2D = ship.get_node_or_null(^"%Attachment_FuelTank") as Marker2D
	if treads_slot == null or drill_slot == null or fuel_tank_slot == null:
		push_error(
			"PartVisuals: ship '%s' missing %%Attachment_Treads, %%Attachment_Drill, or %%Attachment_FuelTank (Marker2D)."
			% ship.name
		)
		return
	_clear_slot_children(treads_slot)
	_clear_slot_children(drill_slot)
	_clear_slot_children(fuel_tank_slot)
	_instantiate_part(treads_slot, &"treads")
	if chained_follower:
		return
	_instantiate_part(drill_slot, &"drill")
	_instantiate_part(fuel_tank_slot, &"fuel_tank")


static func _clear_slot_children(slot: Node2D) -> void:
	for c in slot.get_children():
		c.queue_free()


static func _instantiate_part(slot: Node2D, type_key: StringName) -> void:
	var pid: StringName = PartRegistry.get_equipped_for_type_key(type_key)
	var pd: PartData = PartRegistry.get_part_data(pid)
	if pd == null or pd.visuals == null:
		return
	var ps: PackedScene = pd.visuals.ship_scene
	if ps == null:
		return
	var vis: Node = ps.instantiate()
	slot.add_child(vis)
