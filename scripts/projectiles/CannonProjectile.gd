class_name CannonProjectile
extends Projectile

const _ExplosionFX := preload("res://scripts/projectiles/CannonExplosionFX.gd")

@export var damage: int = 5
@export var visual_radius_px: float = 4.0
@export var collision_radius_px: float = 4.0
@export var explosion_radius_px: float = 16.0
@export var visual_color: Color = Color(1.0, 0.7, 0.2, 1.0)

var _conveyor: TargetConveyor
var _visual: Polygon2D


func _ready() -> void:
	_conveyor = _resolve_conveyor()
	_build_visual()


## Called by CannonTurret right after add_child + global_position set.
func configure(
	direction: Vector2,
	speed_override: float,
	damage_v: int,
	vis_r: float,
	coll_r: float,
	expl_r: float
) -> void:
	setup(direction)
	if speed_override > 0.0:
		speed = speed_override
	damage = damage_v
	visual_radius_px = vis_r
	collision_radius_px = coll_r
	explosion_radius_px = expl_r
	if _visual != null:
		_rebuild_visual_polygon()


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime_s:
		queue_free()
		return

	var step := _dir * speed * delta
	var step_len := step.length()
	# Sub-step to avoid tunneling: cap per-micro-step to half a cell.
	var max_step := _active_cell_size() * 0.5
	var substeps := 1
	if max_step > 0.0 and step_len > max_step:
		substeps = int(ceil(step_len / max_step))
	var inc := step / float(substeps)

	for _i in substeps:
		position += inc
		var hit_dt := _first_overlap()
		if hit_dt != null:
			_detonate()
			return


func _first_overlap() -> DestructibleTarget:
	if _conveyor == null:
		return null
	var f := _conveyor.front_target as DestructibleTarget
	if f != null and not f.is_destroyed():
		if f.overlaps_solid_circle_local(f.to_local(global_position), collision_radius_px):
			return f
	var n := _conveyor.next_target as DestructibleTarget
	if n != null and not n.is_destroyed():
		if n.overlaps_solid_circle_local(n.to_local(global_position), collision_radius_px):
			return n
	return null


## Apply blast to every slab whose grid is within explosion reach.
func _detonate() -> void:
	var hit_world := global_position
	if _conveyor != null:
		_apply_blast(_conveyor.front_target as DestructibleTarget, hit_world)
		_apply_blast(_conveyor.next_target as DestructibleTarget, hit_world)
	var parent := get_parent() as Node2D
	if parent != null:
		_ExplosionFX.spawn(parent, hit_world, explosion_radius_px, visual_color)
	queue_free()


func _apply_blast(dt: DestructibleTarget, hit_world: Vector2) -> void:
	if dt == null or dt.is_destroyed():
		return
	var local := dt.to_local(hit_world)
	# Cheap reject: skip if circle can't possibly touch this slab's AABB.
	var half := dt.target_size_px * 0.5
	var r := explosion_radius_px
	if local.x < -half.x - r or local.x > half.x + r:
		return
	if local.y < -half.y - r or local.y > half.y + r:
		return
	dt.apply_damage_circle_local(local, r, damage, GameStatistics.DAMAGE_SOURCE_CANNON_TURRET)


func _active_cell_size() -> float:
	if _conveyor != null:
		var f := _conveyor.front_target as DestructibleTarget
		if f != null:
			return f.cell_size_px
	return 8.0


func _resolve_conveyor() -> TargetConveyor:
	var n := get_parent()
	while n != null:
		var c := n.get_node_or_null("TargetConveyor") as TargetConveyor
		if c != null:
			return c
		n = n.get_parent()
	return null


func _build_visual() -> void:
	_visual = get_node_or_null("Visual") as Polygon2D
	if _visual == null:
		_visual = Polygon2D.new()
		_visual.name = "Visual"
		add_child(_visual)
	_rebuild_visual_polygon()


func _rebuild_visual_polygon() -> void:
	if _visual == null:
		return
	var segs := 20
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * visual_radius_px)
	_visual.polygon = pts
	_visual.color = visual_color
