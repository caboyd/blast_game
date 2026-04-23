class_name Ship
extends Node2D

signal health_changed(current: int, max_health: int)
signal destroyed

const TURRET_SLOT_RING_SMALL := preload("res://scenes/ships/slots/TurretSlotRingSmall.tscn")
const TURRET_SLOT_RING_MEDIUM := preload("res://scenes/ships/slots/TurretSlotRingMedium.tscn")
const TURRET_SLOT_RING_LARGE := preload("res://scenes/ships/slots/TurretSlotRingLarge.tscn")

@export var ship_type_id: StringName = &"scout"
## If true, expect Hull / HitArea / Slots authored in scene; skip runtime rebuild (see ScoutShip.tscn).
@export var use_baked_scene_hull: bool = false
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
	if use_baked_scene_hull:
		_hydrate_from_baked_scene()
	else:
		apply_type_from_id()


## Rebuild hull, hit area, and slots from `ship_type_id`.
func apply_type_from_id() -> void:
	var st := ShipTypes.get_ship_type(ship_type_id)
	if use_baked_scene_hull:
		_ship_type = st
		max_health = st.max_health
		health = max_health
		health_changed.emit(health, max_health)
		return
	_apply_ship_type(st)
	health = max_health
	health_changed.emit(health, max_health)


func _hydrate_from_baked_scene() -> void:
	_hull = get_node_or_null("Hull") as Polygon2D
	_hit_area = get_node_or_null("HitArea") as Area2D
	_slots_root = get_node_or_null("Slots") as Node2D
	if _hull == null or _hit_area == null or _slots_root == null:
		push_error("Ship: baked hull missing Hull, HitArea, or Slots; falling back to procedural ship.")
		use_baked_scene_hull = false
		apply_type_from_id()
		return
	_collision_poly = _hit_area.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if _collision_poly == null:
		push_error("Ship: HitArea needs CollisionPolygon2D child.")
		use_baked_scene_hull = false
		apply_type_from_id()
		return
	if not _hit_area.area_entered.is_connected(_on_hit_area_area_entered):
		_hit_area.area_entered.connect(_on_hit_area_area_entered)
	_slot_markers.clear()
	for c in _slots_root.get_children():
		if c is Marker2D:
			var mk := c as Marker2D
			_ensure_slot_marker_meta(mk)
			_slot_markers.append(mk)
			_sync_turret_slot_ring_style(mk)
	var st := ShipTypes.get_ship_type(ship_type_id)
	_ship_type = st
	max_health = st.max_health
	health = max_health
	health_changed.emit(health, max_health)


func _ensure_slot_marker_meta(m: Marker2D) -> void:
	if not m.has_meta(&"slot_size"):
		var parts := String(m.name).split("_")
		if parts.size() >= 3 and parts[0] == "Slot":
			m.set_meta(&"slot_size", StringName(parts[1]))
		else:
			m.set_meta(&"slot_size", &"small")
	if not m.has_meta(&"stub"):
		m.set_meta(&"stub", false)


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

		_attach_turret_slot_ring(m, sz, stub)
		i += 1


func _turret_slot_ring_scene(slot_size: StringName) -> PackedScene:
	match slot_size:
		&"small":
			return TURRET_SLOT_RING_SMALL
		&"medium":
			return TURRET_SLOT_RING_MEDIUM
		&"large":
			return TURRET_SLOT_RING_LARGE
		_:
			return TURRET_SLOT_RING_SMALL


func _attach_turret_slot_ring(marker: Marker2D, slot_size: StringName, stub: bool) -> void:
	var ring_root := _turret_slot_ring_scene(slot_size).instantiate() as Node2D
	marker.add_child(ring_root)
	if ring_root is TurretSlotRing:
		(ring_root as TurretSlotRing).apply_stub_style(stub)


func _sync_turret_slot_ring_style(marker: Marker2D) -> void:
	var stub := bool(marker.get_meta(&"stub", false))
	for c in marker.get_children():
		if c is TurretSlotRing:
			(c as TurretSlotRing).apply_stub_style(stub)


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
