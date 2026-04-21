extends Node

signal stats_changed

const DAMAGE_SOURCE_TURRET := &"turret"
const DAMAGE_SOURCE_CLICK := &"click"

const CLICK_FIRE_RATE_START_MS := 500.0
const CLICK_FIRE_RATE_MIN_MS := 25.0
const CLICK_FIRE_RATE_STEP := 0.95

var total_blocks_destroyed: int = 0
var furthest_depth_cells: int = 0
## Total HP removed from block cells (not the same as blocks destroyed).
var damage_to_blocks_turret: int = 0
var damage_to_blocks_click: int = 0
## Per-shot laser turret damage (weapon stat); updated by LaserTurret.
var laser_turret_damage: int = 1
## Per-click damage to the destructible grid; updated by upgrades.
var click_damage: int = 1
## Click AoE radius in whole cells (circle in cell space).
var click_radius_cells: int = 2
## Minimum interval between click damage ticks while holding LMB (ms); reduced by click_fire_rate upgrade.
var click_fire_rate_ms: float = CLICK_FIRE_RATE_START_MS


func _ready() -> void:
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	if id == &"melter":
		set_laser_turret_damage(laser_turret_damage + 1)
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
	if source == DAMAGE_SOURCE_TURRET:
		damage_to_blocks_turret += amount
	elif source == DAMAGE_SOURCE_CLICK:
		damage_to_blocks_click += amount
	stats_changed.emit()


func add_blocks_destroyed(count: int) -> void:
	if count <= 0:
		return
	total_blocks_destroyed += count
	stats_changed.emit()


func update_depth_in_cells(instantaneous_depth: int) -> void:
	if instantaneous_depth <= furthest_depth_cells:
		return
	furthest_depth_cells = instantaneous_depth
	stats_changed.emit()
