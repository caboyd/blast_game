extends Node

signal stats_changed
signal fuel_changed(current: float, max_fuel: float)

const DAMAGE_SOURCE_LASER_TURRET := &"laser_turret"
const DAMAGE_SOURCE_CANNON_TURRET := &"cannon_turret"
const DAMAGE_SOURCE_CLICK := &"click"

const CLICK_FIRE_RATE_START_MS := 500.0
const CLICK_FIRE_RATE_MIN_MS := 25.0
const CLICK_FIRE_RATE_STEP := 0.95

var total_blocks_destroyed: int = 0
## Baseline for `get_blocks_destroyed_this_run()`; set when a mission starts or after a run is committed to career.
var _blocks_destroyed_run_baseline: int = 0
## Currency earned from destroying blocks; spent on upgrades.
var money: int = 0
var furthest_depth_cells: int = 0
## Total HP removed from block cells (not the same as blocks destroyed).
var damage_to_blocks_laser_turret: int = 0
var damage_to_blocks_cannon_turret: int = 0
var damage_to_blocks_click: int = 0
## Per-shot laser turret damage (weapon stat); updated by LaserTurret.
var laser_turret_damage: int = 1
## Per-shot cannon projectile direct blast damage; updated by CannonTurret.
var cannon_turret_damage: int = 5
## Cannon shell explosion radius (px); increased by `cannon_blast` upgrade.
var cannon_explosion_radius_px: float = 16.0
const CANNON_BLAST_RADIUS_STEP_PX := 4.0
## Per-click damage to the destructible grid; updated by upgrades.
var click_damage: int = 1
## Click AoE radius in whole cells (circle in cell space).
var click_radius_cells: int = 2
## Minimum interval between click damage ticks while holding LMB (ms); reduced by click_fire_rate upgrade.
var click_fire_rate_ms: float = CLICK_FIRE_RATE_START_MS

const FUEL_TANK_BONUS := 10.0
## Max fuel with zero `fuel_tank` upgrades. Keep in sync with `begin_run` / career reset expectations.
const BASE_FUEL_MAX := 100.0
const MINE_UPGRADE_DMG_PER_LEVEL := 0.15
const VISIBILITY_RANGE_UPGRADE_CELLS_PER_LEVEL := 1
const VESSEL_SPEED_UPGRADE_PX_PER_LEVEL := 1.0
const DRILL_RANGE_UPGRADE_PX_PER_LEVEL := 1.0

var fuel: float = 100.0
var fuel_max: float = BASE_FUEL_MAX

## Master switch for world gizmos (mining vessel hull/drill debug, conveyor bounds, viewport label). Toggled from `DebugOverlay` on planet; default off so Prep (no overlay) is clean.
var debug_world_visuals: bool = false


func _ready() -> void:
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	if id == &"fuel_tank":
		_refit_fuel_tank_add_capacity_preserve_fill()
	elif (
		id == &"mining_power"
		or id == &"visibility_range"
		or id == &"vessel_speed"
		or id == &"drill_range"
	):
		stats_changed.emit()
	elif id == &"melter":
		set_laser_turret_damage(laser_turret_damage + 1)
	elif id == &"cannon_shell":
		set_cannon_turret_damage(cannon_turret_damage + 1)
	elif id == &"cannon_blast":
		set_cannon_explosion_radius_px(cannon_explosion_radius_px + CANNON_BLAST_RADIUS_STEP_PX)
	elif id == &"click_dmg":
		set_click_damage(click_damage + 1)
	elif id == &"click_radius":
		set_click_radius_cells(click_radius_cells + 1)
	elif id == &"click_fire_rate":
		set_click_fire_rate_ms(click_fire_rate_ms * CLICK_FIRE_RATE_STEP)


func set_laser_turret_damage(amount: int) -> void:
	var v := maxi(1, amount)
	if laser_turret_damage == v:
		return
	laser_turret_damage = v
	stats_changed.emit()


func set_cannon_turret_damage(amount: int) -> void:
	var v := maxi(1, amount)
	if cannon_turret_damage == v:
		return
	cannon_turret_damage = v
	stats_changed.emit()


func set_cannon_explosion_radius_px(px: float) -> void:
	var v := maxf(1.0, px)
	if is_equal_approx(cannon_explosion_radius_px, v):
		return
	cannon_explosion_radius_px = v
	stats_changed.emit()


func set_click_damage(amount: int) -> void:
	var v := maxi(1, amount)
	if click_damage == v:
		return
	click_damage = v
	stats_changed.emit()


func set_click_radius_cells(cells: int) -> void:
	var v := maxi(1, cells)
	if click_radius_cells == v:
		return
	click_radius_cells = v
	stats_changed.emit()


func set_click_fire_rate_ms(ms: float) -> void:
	var v := maxf(CLICK_FIRE_RATE_MIN_MS, ms)
	if is_equal_approx(click_fire_rate_ms, v):
		return
	click_fire_rate_ms = v
	stats_changed.emit()


func add_block_damage(amount: int, source: StringName) -> void:
	if amount <= 0:
		return
	if source == DAMAGE_SOURCE_LASER_TURRET:
		damage_to_blocks_laser_turret += amount
	elif source == DAMAGE_SOURCE_CANNON_TURRET:
		damage_to_blocks_cannon_turret += amount
	elif source == DAMAGE_SOURCE_CLICK:
		damage_to_blocks_click += amount
	stats_changed.emit()


func set_blocks_run_baseline() -> void:
	_blocks_destroyed_run_baseline = total_blocks_destroyed
	stats_changed.emit()


func get_blocks_destroyed_this_run() -> int:
	return total_blocks_destroyed - _blocks_destroyed_run_baseline


func add_blocks_destroyed(count: int) -> void:
	if count <= 0:
		return
	total_blocks_destroyed += count
	stats_changed.emit()


func add_money(amount: int) -> void:
	if amount <= 0:
		return
	money += amount
	stats_changed.emit()
	GameSession.save_career()


func spend_money(amount: int, persist_career: bool = true) -> bool:
	if amount <= 0:
		return true
	if amount > money:
		return false
	money -= amount
	stats_changed.emit()
	if persist_career:
		GameSession.save_career()
	return true


func update_depth_in_cells(instantaneous_depth: int) -> void:
	if instantaneous_depth <= furthest_depth_cells:
		return
	furthest_depth_cells = instantaneous_depth
	stats_changed.emit()


func reset_fuel_for_run() -> void:
	fuel = fuel_max
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


## After career load: full fuel at upgraded max.
func apply_fuel_max_from_career_load() -> void:
	var new_m: float = effective_fuel_max()
	fuel_max = new_m
	fuel = new_m
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


func effective_fuel_max() -> float:
	return BASE_FUEL_MAX + float(UpgradeBus.get_level(&"fuel_tank")) * FUEL_TANK_BONUS


func _refit_fuel_tank_add_capacity_preserve_fill() -> void:
	var old_m: float = fuel_max
	var new_m: float = effective_fuel_max()
	if is_equal_approx(old_m, new_m):
		return
	fuel_max = new_m
	fuel = minf(fuel + (new_m - old_m), new_m)
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


func consume_fuel(amount: float) -> void:
	if amount <= 0.0:
		return
	fuel = maxf(0.0, fuel - amount)
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()
