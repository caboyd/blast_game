class_name GlobalPartGroundPickup
extends Area2D

@export var pickup_id: StringName = &""
@export var part_id: StringName = &""
## Which tier-up pickup this is for this part (`0` … `GlobalPartData.max_level - 1`).
@export var pickup_index: int = 0
## See `GlobalPartRegistry.PICKUP_PERSISTENCE_*`.
@export var persistence: StringName = &"once"

var _collected: bool = false


func _ready() -> void:
	collision_mask = ShipBase.PHYSICS_LAYER_MINING_SHIP_FOR_PICKUPS
	monitoring = true
	add_to_group(&"pickup_debug_redraw")
	_mount_visual_if_needed()
	area_entered.connect(_on_area_entered)


func _pickup_collision_shape() -> CollisionShape2D:
	return get_node_or_null(^"%PickupCollision") as CollisionShape2D


func _pickup_circle_radius_local() -> float:
	var cs := _pickup_collision_shape()
	if cs == null or not (cs.shape is CircleShape2D):
		return 0.0
	var circ := cs.shape as CircleShape2D
	var s: float = maxf(absf(cs.scale.x), absf(cs.scale.y))
	return circ.radius * s


func _draw() -> void:
	if _collected or not GameStatistics.debug_world_visuals:
		return
	var cs := _pickup_collision_shape()
	if cs == null:
		return
	var r: float = _pickup_circle_radius_local()
	if r <= 0.0:
		return
	var ctr: Vector2 = cs.position
	draw_circle(ctr, r, Color(0.98, 0.78, 0.12, 0.2))
	draw_arc(ctr, r, 0.0, TAU, 64, Color(1.0, 0.82, 0.18, 0.92), 2.0, true)


func _mount_visual_if_needed() -> void:
	var holder := get_node_or_null(^"%VisualHolder") as Node2D
	if holder == null:
		return
	for c in holder.get_children():
		c.queue_free()
	var pd: GlobalPartData = GlobalPartRegistry.get_part_data(part_id)
	if pd == null or pd.visuals == null:
		return
	var gs: PackedScene = pd.visuals.ground_scene
	if gs == null:
		return
	var vis: Node = gs.instantiate()
	holder.add_child(vis)


func _on_area_entered(area: Area2D) -> void:
	_try_collect_from_collider(area)


func _try_collect_from_collider(node: Node) -> void:
	var ship := _resolve_ship_base(node)
	if ship == null or ship.follower_visual_only:
		return
	_collect()


func _resolve_ship_base(node: Node) -> ShipBase:
	var cur: Node = node
	for _i in 8:
		if cur == null:
			return null
		if cur is ShipBase:
			return cur as ShipBase
		cur = cur.get_parent()
	return null


func _collect() -> void:
	if _collected:
		return
	if part_id == &"":
		queue_free()
		return
	if persistence == GlobalPartRegistry.PICKUP_PERSISTENCE_ONCE and GlobalPartRegistry.is_slot_pickup_collected(part_id, pickup_index):
		queue_free()
		return
	_collected = true
	GlobalPartRegistry.collect_part(part_id)
	if persistence == GlobalPartRegistry.PICKUP_PERSISTENCE_ONCE:
		GlobalPartRegistry.mark_once_global_part_pickup(part_id, pickup_index, pickup_id)
	GameSession.save_career()
	queue_free()
