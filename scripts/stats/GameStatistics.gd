extends Node

signal stats_changed
signal fuel_changed(current: float, max_fuel: float)

## Max fuel multiplier (absolute ceiling = fuel_max × this). Overflow band is `(mul − 1) × fuel_max` (default 50% of nominal max).
const FUEL_ABSOLUTE_CAP_MUL := 1.5


func fuel_hard_cap_absolute() -> float:
	return fuel_max * FUEL_ABSOLUTE_CAP_MUL


func fuel_overflow_budget() -> float:
	return fuel_max * (FUEL_ABSOLUTE_CAP_MUL - 1.0)

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

## Base max fuel before `fuel_tank` upgrades; set from active `ShipData.fuel_max_base`.
var _base_fuel_max: float = 0.0

var fuel: float = 0.0
var fuel_max: float = 0.0

## Master switch for world gizmos (mining ship hull/drill debug, conveyor bounds, viewport label). Toggled from `DebugOverlay` on planet; default off so Prep (no overlay) is clean.
var debug_world_visuals: bool = false
## Debug: temporarily reveals fog-of-war for the current mining mission only. Cleared in `GameSession.begin_run()`.
var debug_fog_disabled: bool = false


func set_debug_fog_disabled(on: bool) -> void:
	debug_fog_disabled = on
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group(&"mining_world"):
		if n.has_method(&"apply_debug_fog_visibility"):
			n.apply_debug_fog_visibility()


func _ready() -> void:
	_apply_ship_fuel_base()
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	if not PartRegistry.parts_changed.is_connected(_on_parts_changed):
		PartRegistry.parts_changed.connect(_on_parts_changed)


func _apply_ship_fuel_base() -> void:
	var sd: Resource = ShipDataRegistry.get_active()
	if sd == null:
		push_error("ShipDataRegistry.get_active() returned null")
		assert(false)
		return

	_base_fuel_max = float(sd.get("fuel_max_base"))


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	if id == &"fuel_tank":
		_refit_fuel_tank_add_capacity_preserve_fill()
	elif ShipDataRegistry.has_upgrade(id):
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


## Mined blocks only: may apply `money_double_chance` from ship upgrades, then `add_money`.
func add_mined_cell_reward(base_amount: int) -> void:
	if base_amount <= 0:
		return
	var amt: int = base_amount
	var chance: float = ShipDataRegistry.apply_effects_for_stat(&"money_double_chance", 0.0)
	chance = clampf(chance, 0.0, 100.0)
	if chance > 0.0 and randf() * 100.0 < chance:
		amt *= 2
	add_money(amt)


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


func apply_fuel_cell_pickup() -> void:
	if fuel_max <= 0.0:
		return
	fuel = minf(fuel + fuel_max * 0.5, fuel_hard_cap_absolute())
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


## After career load: full fuel at upgraded max.
func apply_fuel_max_from_career_load() -> void:
	var new_m: float = effective_fuel_max()
	fuel_max = new_m
	fuel = new_m
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


## Call when `GameSession.selected_ship_id` changes (Prep): re-base fuel max on the new ship, clamp fill.
func apply_active_ship_fuel_baseline() -> void:
	_apply_ship_fuel_base()
	var new_m: float = effective_fuel_max()
	fuel_max = new_m
	var cap_abs: float = fuel_hard_cap_absolute()
	fuel = minf(fuel, cap_abs)
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


func effective_fuel_max() -> float:
	var upgraded: float = ShipDataRegistry.apply_effects_for_stat(&"fuel_max", _base_fuel_max)
	return PartRegistry.apply_effects_for_stat(&"fuel_max", upgraded)


func _on_parts_changed() -> void:
	refit_fuel_from_parts()


func refit_fuel_from_parts() -> void:
	var old_m: float = fuel_max
	var new_m: float = effective_fuel_max()
	if is_equal_approx(old_m, new_m):
		return
	var frac: float = fuel / old_m if old_m > 0.0 else 1.0
	fuel_max = new_m
	fuel = minf(new_m * frac, fuel_hard_cap_absolute())
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


func _refit_fuel_tank_add_capacity_preserve_fill() -> void:
	var old_m: float = fuel_max
	var new_m: float = effective_fuel_max()
	if is_equal_approx(old_m, new_m):
		return
	fuel_max = new_m
	fuel = minf(fuel + (new_m - old_m), fuel_hard_cap_absolute())
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


func consume_fuel(amount: float) -> void:
	if amount <= 0.0:
		return
	fuel = maxf(0.0, fuel - amount)
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()
