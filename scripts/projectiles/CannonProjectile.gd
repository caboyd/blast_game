class_name CannonProjectile
extends Projectile

const _ExplosionFX := preload("res://scripts/projectiles/CannonExplosionFX.gd")

@export var damage: int = 5
@export var visual_radius_px: float = 4.0
@export var collision_radius_px: float = 4.0
@export var explosion_radius_px: float = 16.0
@export var visual_color: Color = Color(1.0, 0.7, 0.2, 1.0)

var _visual: Polygon2D


func _ready() -> void:
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
	var max_step := 4.0
	var substeps := 1
	if max_step > 0.0 and step_len > max_step:
		substeps = int(ceil(step_len / max_step))
	var inc := step / float(substeps)

	for _i in substeps:
		position += inc
		var hit_enemy := _first_enemy_hit()
		if hit_enemy != null:
			_detonate(global_position)
			return


func _first_enemy_hit() -> Enemy:
	var gp := global_position
	var r := collision_radius_px
	for n in get_tree().get_nodes_in_group(&"enemies"):
		if not n is Enemy:
			continue
		var e := n as Enemy
		var rr := r + e.hit_radius
		if gp.distance_squared_to(e.global_position) <= rr * rr:
			return e
	return null


func _detonate(hit_world: Vector2) -> void:
	_damage_enemies_in_radius(hit_world, explosion_radius_px)
	var parent := get_parent() as Node2D
	if parent != null:
		_ExplosionFX.spawn(parent, hit_world, explosion_radius_px, visual_color)
	queue_free()


func _damage_enemies_in_radius(center_world: Vector2, radius: float) -> void:
	var r2 := radius * radius
	for n in get_tree().get_nodes_in_group(&"enemies"):
		if not n is Enemy:
			continue
		var e := n as Enemy
		if center_world.distance_squared_to(e.global_position) <= r2:
			e.apply_damage(damage)


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
