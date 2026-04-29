class_name GlobalPartGroundPickup
extends Area2D

@export var pickup_id: StringName = &""
@export var part_id: StringName = &""

const _COLLECT_RADIUS_PX := 28.0

var _collected: bool = false


func _ready() -> void:
	set_physics_process(true)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(_delta: float) -> void:
	if _collected:
		return
	var lead := get_tree().get_first_node_in_group(&"leading_mining_ship") as Node2D
	if lead == null:
		return
	if lead is ShipBase and (lead as ShipBase).follower_visual_only:
		return
	if global_position.distance_squared_to(lead.global_position) <= _COLLECT_RADIUS_PX * _COLLECT_RADIUS_PX:
		_collect()


func _on_body_entered(body: Node) -> void:
	_try_collect_from_collider(body)


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
	if pickup_id != &"" and GlobalPartRegistry.is_pickup_collected(pickup_id):
		queue_free()
		return
	if part_id == &"":
		queue_free()
		return
	_collected = true
	set_physics_process(false)
	GlobalPartRegistry.equip_part(part_id)
	if pickup_id != &"":
		GlobalPartRegistry.mark_pickup_collected(pickup_id)
	GameSession.save_career()
	queue_free()
