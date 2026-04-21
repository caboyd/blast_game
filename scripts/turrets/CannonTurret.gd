class_name CannonTurret
extends Turret

const CANNON_PROJECTILE_SCENE := preload("res://scenes/projectiles/CannonProjectile.tscn")
const TARGET_SPOTTER_SCENE := preload("res://scenes/target/TargetSpotter.tscn")

@export var fire_rate_hz: float = 1.0
## Projectile muzzle velocity (px/s). Straight line, direction from spotter aim.
@export var projectile_speed: float = 600.0
@export var projectile_lifetime_s: float = 3.0
@export var damage: int = 5
@export var visual_radius_px: float = 4.0
@export var collision_radius_px: float = 4.0
@export var explosion_radius_px: float = 16.0
@export var spotter_line_width: float = 0.0

var _spotter: TargetSpotter
var _conveyor: TargetConveyor
var _fire_accum: float = 0.0


func _ready() -> void:
	add_to_group(&"cannon_turrets")
	process_priority = 1
	_conveyor = _resolve_conveyor()
	_spotter = TARGET_SPOTTER_SCENE.instantiate() as TargetSpotter
	_spotter.name = "TargetSpotter"
	_spotter.line_width = spotter_line_width
	UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	damage = GameStatistics.cannon_turret_damage
	add_child(_spotter)


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	if id == &"cannon_shell":
		damage = GameStatistics.cannon_turret_damage


func _process(delta: float) -> void:
	if _conveyor == null:
		_conveyor = _resolve_conveyor()
	if _conveyor == null:
		return
	var dt := _conveyor.get_active_target() as DestructibleTarget
	if dt == null or dt.is_destroyed():
		_fire_accum = 0.0
		return
	var cell := _spotter.get_tracked_cell()
	if cell.x < 0 or not dt.is_cell_solid(cell):
		_fire_accum = 0.0
		return

	_fire_accum += delta
	var interval := 1.0 / maxf(fire_rate_hz, 0.0001)
	while _fire_accum >= interval:
		_fire_accum -= interval
		_fire_one(dt, cell)


func _fire_one(dt: DestructibleTarget, cell: Vector2i) -> void:
	var muzzle := barrel.global_position
	var target_world := dt.to_global(dt.cell_center_local(cell))
	var dir := target_world - muzzle
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


## Prefer dedicated ProjectileManager on the World2D layer; fall back to own parent.
func _projectile_parent() -> Node:
	var p := get_parent()
	if p == null:
		return self
	var world := p.get_parent()
	if world != null:
		var pm := world.get_node_or_null("ProjectileManager")
		if pm != null:
			return pm
	return p


func _resolve_conveyor() -> TargetConveyor:
	var p := get_parent()
	if p == null:
		return null
	var world := p.get_parent() as Node2D
	if world == null:
		return null
	return world.get_node_or_null("TargetConveyor") as TargetConveyor
