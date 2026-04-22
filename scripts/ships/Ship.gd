class_name Ship
extends Node2D

signal health_changed(current: int, max_health: int)
signal destroyed

const SLOT_RING_RADIUS: float = 10.0

@export var ship_type_id: StringName = &"scout"
@export var position_x: float = 110.0

var _ship_type: ShipType
var _hull: Polygon2D
var _hit_area: Area2D
var _collision_poly: CollisionPolygon2D
var _slots_root: Node2D
var _slot_markers: Array[Marker2D] = []

var max_health: int = 100
var health: int = 100


func _ready() -> void:
	add_to_group(&"player_ship")
	# Build before UI/UpgradeBus reads slot counts (Main may re-apply if `ship_type_id` differs).
	apply_type_from_id()


## Rebuild hull, hit area, and slots from `ship_type_id`.
func apply_type_from_id() -> void:
	_apply_ship_type(ShipTypes.get_ship_type(ship_type_id))
	health = max_health
	health_changed.emit(health, max_health)


func _apply_ship_type(st: ShipType) -> void:
	_ship_type = st
	max_health = st.max_health
	health = mini(health, max_health)

	for c in get_children():
		c.queue_free()
	_slot_markers.clear()

	_hull = Polygon2D.new()
	_hull.name = "Hull"
	_hull.polygon = st.hull_polygon
	_hull.color = st.hull_color
	add_child(_hull)

	_hit_area = Area2D.new()
	_hit_area.name = "HitArea"
	_hit_area.collision_layer = 2
	_hit_area.collision_mask = 4
	_hit_area.monitoring = true
	_hit_area.monitorable = false
	add_child(_hit_area)
	_collision_poly = CollisionPolygon2D.new()
	_collision_poly.polygon = st.hull_polygon
	_hit_area.add_child(_collision_poly)
	_hit_area.area_entered.connect(_on_hit_area_area_entered)

	_slots_root = Node2D.new()
	_slots_root.name = "Slots"
	add_child(_slots_root)

	var i := 0
	for slot_def in st.slots:
		var m := Marker2D.new()
		var sz: StringName = slot_def.get("size", &"small") as StringName
		var stub: bool = bool(slot_def.get("stub", false))
		var pos: Vector2 = slot_def.get("position", Vector2.ZERO) as Vector2
		m.name = "Slot_%s_%d" % [String(sz), i]
		m.position = pos
		m.set_meta(&"slot_size", sz)
		m.set_meta(&"stub", stub)
		_slots_root.add_child(m)
		_slot_markers.append(m)

		var ring := Polygon2D.new()
		ring.color = Color(1, 1, 1, 0.12) if not stub else Color(0.5, 0.5, 0.5, 0.08)
		ring.polygon = _circle_polygon(SLOT_RING_RADIUS, 16)
		m.add_child(ring)
		i += 1


func _circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in segments:
		var a := TAU * float(j) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func get_small_slot_count() -> int:
	var n := 0
	for m in _slot_markers:
		if _is_mountable(m, &"small"):
			n += 1
	return n


func get_free_slot(size: StringName) -> Marker2D:
	for m in _slot_markers:
		if not _is_mountable(m, size):
			continue
		if _slot_has_turret(m):
			continue
		return m
	return null


func _is_mountable(m: Marker2D, size: StringName) -> bool:
	if bool(m.get_meta(&"stub", false)):
		return false
	return m.get_meta(&"slot_size", &"small") == size


func _slot_has_turret(m: Marker2D) -> bool:
	for c in m.get_children():
		if c is LaserTurret or c is CannonTurret:
			return true
	return false


func mount_turret(slot: Marker2D, turret: Node2D) -> void:
	if slot == null or turret == null:
		return
	for c in slot.get_children():
		if c is LaserTurret or c is CannonTurret:
			return
	slot.add_child(turret)
	turret.position = Vector2.ZERO


func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0:
		destroyed.emit()
		print("Ship destroyed")


func _on_hit_area_area_entered(area: Area2D) -> void:
	if not area.is_in_group(&"enemy_projectiles"):
		return
	if area.has_method(&"get_damage"):
		apply_damage(int(area.call(&"get_damage")))
	elif area.has_meta(&"damage"):
		apply_damage(int(area.get_meta(&"damage")))
	else:
		apply_damage(1)
	area.queue_free()
