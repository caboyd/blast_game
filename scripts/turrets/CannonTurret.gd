class_name CannonTurret
extends Turret

const CANNON_PROJECTILE_SCENE := preload("res://scenes/projectiles/CannonProjectile.tscn")

@export var fire_rate_hz: float = 1.0
@export var attack_range_px: float = 520.0
## Projectile muzzle velocity (px/s). Straight line, direction toward enemy.
@export var projectile_speed: float = 600.0
@export var projectile_lifetime_s: float = 3.0
@export var damage: int = 5
@export var visual_radius_px: float = 4.0
@export var collision_radius_px: float = 4.0
@export var explosion_radius_px: float = 16.0

var _fire_accum: float = 0.0


func _ready() -> void:
	add_to_group(&"cannon_turrets")
	process_priority = 1
	UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	damage = GameStatistics.cannon_turret_damage
	explosion_radius_px = GameStatistics.cannon_explosion_radius_px
	if Turret.debug_show_attack_ranges:
		queue_redraw()


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	if id == &"cannon_shell":
		damage = GameStatistics.cannon_turret_damage
	elif id == &"cannon_blast":
		explosion_radius_px = GameStatistics.cannon_explosion_radius_px


func _pick_target() -> Enemy:
	var best: Enemy = null
	var best_d2: float = INF
	var origin := barrel.global_position
	var r2 := attack_range_px * attack_range_px
	for n in get_tree().get_nodes_in_group(&"enemies"):
		if not n is Enemy:
			continue
		var e := n as Enemy
		var d2 := origin.distance_squared_to(e.global_position)
		if d2 <= r2 and d2 < best_d2:
			best_d2 = d2
			best = e
	return best


func _draw() -> void:
	if not Turret.debug_show_attack_ranges:
		return
	if barrel == null:
		return
	draw_arc(barrel.position, attack_range_px, 0.0, TAU, 64, Color(0.3, 0.75, 1.0, 0.55), 1.5, true)


func _process(delta: float) -> void:
	var enemy := _pick_target()
	if enemy == null:
		_fire_accum = 0.0
		return

	_fire_accum += delta
	var interval := 1.0 / maxf(fire_rate_hz, 0.0001)
	while _fire_accum >= interval:
		_fire_accum -= interval
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			break
		_fire_one(enemy)


func _fire_one(enemy: Enemy) -> void:
	var muzzle := barrel.global_position
	var dir := enemy.global_position - muzzle
	if dir.length_squared() <= 0.0001:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	var proj := CANNON_PROJECTILE_SCENE.instantiate() as CannonProjectile
	var parent := _projectile_parent()
	parent.add_child(proj)
	proj.global_position = muzzle
	proj.lifetime_s = projectile_lifetime_s
	proj.configure(
		dir,
		projectile_speed,
		damage,
		visual_radius_px,
		collision_radius_px,
		explosion_radius_px
	)


## Prefer dedicated ProjectileManager under World2D; walk up from turret mount.
func _projectile_parent() -> Node:
	var n: Node = self
	while n != null:
		var pm := n.get_node_or_null("ProjectileManager")
		if pm != null:
			return pm
		n = n.get_parent()
	var p := get_parent()
	return p if p != null else self
