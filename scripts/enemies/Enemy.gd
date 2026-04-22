class_name Enemy
extends Node2D

const ENEMY_PROJECTILE_SCENE := preload("res://scenes/enemies/EnemyProjectile.tscn")

@export var max_health: int = 20
@export var move_speed: float = 60.0
@export var attack_range_px: float = 380.0
@export var attack_rate_hz: float = 0.5
@export var hit_radius: float = 14.0
@export var projectile_speed: float = 260.0
@export var projectile_damage: int = 5
@export var projectile_lifetime_s: float = 4.0

var health: int = 20
var _fire_accum: float = 0.0
var _visual: Polygon2D


func _ready() -> void:
	add_to_group(&"enemies")
	health = max_health
	_build_visual()
	if Turret.debug_show_attack_ranges:
		queue_redraw()


func _build_visual() -> void:
	_visual = Polygon2D.new()
	_visual.color = Color(0.95, 0.25, 0.2, 1.0)
	# Triangle nose points left (toward ship)
	_visual.polygon = PackedVector2Array(
		[Vector2(-12, -10), Vector2(14, 0), Vector2(-12, 10)]
	)
	add_child(_visual)


func _process(delta: float) -> void:
	var ship := get_tree().get_first_node_in_group(&"player_ship") as Ship
	if ship == null:
		return
	var to_ship := ship.global_position - global_position
	var dist := to_ship.length()
	if dist > attack_range_px + 0.5:
		if dist > 0.001:
			global_position += to_ship.normalized() * move_speed * delta
		_fire_accum = 0.0
	else:
		_fire_accum += delta
		var interval := 1.0 / maxf(attack_rate_hz, 0.0001)
		while _fire_accum >= interval:
			_fire_accum -= interval
			_fire_at_ship(ship)


func _fire_at_ship(ship: Ship) -> void:
	var muzzle := global_position
	var target := ship.global_position
	var dir := target - muzzle
	if dir.length_squared() <= 0.0001:
		dir = Vector2.LEFT
	dir = dir.normalized()
	var proj := ENEMY_PROJECTILE_SCENE.instantiate()
	var pm := _projectile_parent()
	pm.add_child(proj)
	if proj is EnemyProjectile:
		(proj as EnemyProjectile).initialize(muzzle, dir, projectile_speed, projectile_damage, projectile_lifetime_s)
	else:
		proj.global_position = muzzle


func _projectile_parent() -> Node:
	var n := get_parent()
	while n != null:
		var pm := n.get_node_or_null("ProjectileManager")
		if pm != null:
			return pm
		n = n.get_parent()
	return get_parent()


func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	health -= amount
	if health <= 0:
		queue_free()


func _draw() -> void:
	if not Turret.debug_show_attack_ranges:
		return
	draw_arc(Vector2.ZERO, attack_range_px, 0.0, TAU, 64, Color(1.0, 0.3, 0.3, 0.55), 1.5, true)
