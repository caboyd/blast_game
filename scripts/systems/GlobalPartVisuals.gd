class_name GlobalPartVisuals
extends RefCounted

## Legacy single root (pre split); removed on attach so old ships clean up.
const LEGACY_ROOT_NAME := &"GlobalPartsVisualRoot"
## Treads render behind the hull (negative z relative to the ship).
const TREADS_ROOT_NAME := &"GlobalPartsTreadsRoot"
## Tank + drill render in front of the hull.
const UPPER_ROOT_NAME := &"GlobalPartsUpperRoot"


static func attach_to_ship(ship: Node2D) -> void:
	if ship == null:
		return
	var chained_follower: bool = ship is ShipBase and (ship as ShipBase).follower_visual_only
	for root_name in [LEGACY_ROOT_NAME, TREADS_ROOT_NAME, UPPER_ROOT_NAME]:
		var existing: Node = ship.get_node_or_null(String(root_name))
		if existing:
			existing.queue_free()
	var treads_root := Node2D.new()
	treads_root.name = String(TREADS_ROOT_NAME)
	treads_root.z_as_relative = true
	treads_root.z_index = -1
	ship.add_child(treads_root)
	_instantiate_part(treads_root, &"treads")
	if chained_follower:
		return
	var upper_root := Node2D.new()
	upper_root.name = String(UPPER_ROOT_NAME)
	upper_root.z_as_relative = true
	upper_root.z_index = 1
	ship.add_child(upper_root)
	var upper_order: Array[StringName] = [&"fuel_tank", &"drill"]
	for type_key in upper_order:
		_instantiate_part(upper_root, type_key)


static func _instantiate_part(parent: Node2D, type_key: StringName) -> void:
	var pid: StringName = GlobalPartRegistry.get_equipped_for_type_key(type_key)
	var pd: GlobalPartData = GlobalPartRegistry.get_part_data(pid)
	if pd == null:
		return
	var ps: PackedScene = pd.ship_scene
	if ps == null:
		return
	var vis: Node = ps.instantiate()
	parent.add_child(vis)
