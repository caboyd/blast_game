extends Node

## Emitted once when `init()` completes (idempotent; subsequent `init()` does not emit again).
signal stats_ready

signal stats_changed
signal fuel_changed(current: float, max_fuel: float)
signal run_mined_resources_changed

## Max fuel multiplier (absolute ceiling = fuel_max × this). Overflow band is `(mul − 1) × fuel_max` (default 50% of nominal max).
const FUEL_ABSOLUTE_CAP_MUL := 1.5


func fuel_hard_cap_absolute() -> float:
	return fuel_max * FUEL_ABSOLUTE_CAP_MUL


func fuel_overflow_budget() -> float:
	return fuel_max * (FUEL_ABSOLUTE_CAP_MUL - 1.0)

## Window for rolling mining `$ / s` on the run HUD (`get_run_rolling_money_per_second`).
const RUN_MINING_ROLLING_MONEY_MS := 10000

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

## Actual dollars credited from `add_mined_cell_reward` this run (after double-money roll). Reset in `reset_run_mining_economy_tracking`.
var run_mined_money_awarded: int = 0
var _money_award_ticks_ms: PackedInt64Array = PackedInt64Array()
var _money_award_amounts: PackedInt32Array = PackedInt32Array()

## Block types fully mined this run (`type_id` -> count); colors captured on first increment. Cleared in `reset_run_mined_resources`.
var _run_mined_type_counts: Dictionary = {}
var _run_mined_type_colors: Dictionary = {}

## Master switch for world gizmos (mining ship hull/drill debug, conveyor bounds, viewport label). Toggled from `DebugOverlay` (F3 on prep or planet); default off so normal play stays clean.
## Persisted in `user://debug_prefs.cfg`.
var debug_world_visuals: bool = false

## Debug vehicle stat overrides (`DebugOverlay`). Persisted with debug prefs.
const DEBUG_VEHICLE_OVERRIDE_MIN_FUEL_MAX := 1.0
const DEBUG_VEHICLE_OVERRIDE_MIN_MOVE_PX := 1e-3
const DEBUG_VEHICLE_OVERRIDE_MIN_MINE_DAMAGE := 1e-4
const DEBUG_VEHICLE_OVERRIDE_MIN_MINE_INTERVAL_S := 0.01
const DEBUG_VEHICLE_OVERRIDE_MIN_DRILL_RANGE_GAME_PX := 0.05

var debug_fuel_max_override_enabled: bool = false
var debug_fuel_max_override_value: float = 100.0
var debug_move_speed_override_enabled: bool = false
var debug_move_speed_override_value: float = 40.0
var debug_mine_damage_override_enabled: bool = false
var debug_mine_damage_override_value: float = 10.0
## When enabled, overrides mining tick spacing (`mine_interval_s`). Lower interval = faster mining.
var debug_mine_interval_override_enabled: bool = false
var debug_mine_interval_override_value: float = 0.2
## Effective drill radius in **game** pixels (before ship scale); replaces base + upgrade bonus.
var debug_drill_range_game_px_override_enabled: bool = false
var debug_drill_range_game_px_override_value: float = 16.0

var debug_turn_rate_rad_s_override_enabled: bool = false
var debug_turn_rate_rad_s_override_value: float = 9.0

## Debug camera zoom multiplier on mining planets (`DebugOverlay` +/-). Clamped 0.2..2.0 on load; same range as planet `adjust_debug_camera_zoom`.
var debug_camera_zoom_multiplier: float = 1.0
## Last value in the debug panel gold `SpinBox` (Give button).
var debug_menu_gold_give_spin: int = 1000000

const _DEBUG_PREFS_PATH := "user://debug_prefs.cfg"
const _DEBUG_PREFS_SECTION := "debug"
const _DEBUG_ZOOM_CLAMP_MIN := 0.2
const _DEBUG_ZOOM_CLAMP_MAX := 2.0
var _debug_prefs_write_pending: bool = false

var initialized := false


func init() -> void:
	if initialized:
		return
	load_debug_preferences()
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	if not PartRegistry.parts_changed.is_connected(_on_parts_changed):
		PartRegistry.parts_changed.connect(_on_parts_changed)
	_apply_ship_fuel_base()
	initialized = true
	stats_ready.emit()


func load_debug_preferences() -> void:
	var c := ConfigFile.new()
	if c.load(_DEBUG_PREFS_PATH) != OK:
		return
	var sec := _DEBUG_PREFS_SECTION
	debug_world_visuals = bool(c.get_value(sec, "world_visuals", debug_world_visuals))
	debug_camera_zoom_multiplier = clampf(
		float(c.get_value(sec, "camera_zoom_mul", debug_camera_zoom_multiplier)),
		_DEBUG_ZOOM_CLAMP_MIN,
		_DEBUG_ZOOM_CLAMP_MAX,
	)
	debug_menu_gold_give_spin = int(c.get_value(sec, "gold_give_spin", debug_menu_gold_give_spin))
	debug_fuel_max_override_enabled = bool(c.get_value(sec, "fuel_ovrd_en", debug_fuel_max_override_enabled))
	debug_fuel_max_override_value = maxf(
		DEBUG_VEHICLE_OVERRIDE_MIN_FUEL_MAX,
		float(c.get_value(sec, "fuel_ovrd_val", debug_fuel_max_override_value)),
	)
	debug_move_speed_override_enabled = bool(c.get_value(sec, "speed_ovrd_en", debug_move_speed_override_enabled))
	debug_move_speed_override_value = maxf(
		DEBUG_VEHICLE_OVERRIDE_MIN_MOVE_PX,
		float(c.get_value(sec, "speed_ovrd_val", debug_move_speed_override_value)),
	)
	debug_mine_damage_override_enabled = bool(c.get_value(sec, "mine_dmg_ovrd_en", debug_mine_damage_override_enabled))
	debug_mine_damage_override_value = maxf(
		DEBUG_VEHICLE_OVERRIDE_MIN_MINE_DAMAGE,
		float(c.get_value(sec, "mine_dmg_ovrd_val", debug_mine_damage_override_value)),
	)
	debug_mine_interval_override_enabled = bool(c.get_value(sec, "mine_ivl_ovrd_en", debug_mine_interval_override_enabled))
	debug_mine_interval_override_value = clampf(
		float(c.get_value(sec, "mine_ivl_ovrd_val", debug_mine_interval_override_value)),
		DEBUG_VEHICLE_OVERRIDE_MIN_MINE_INTERVAL_S,
		999.0,
	)
	debug_drill_range_game_px_override_enabled = bool(
		c.get_value(sec, "drill_px_ovrd_en", debug_drill_range_game_px_override_enabled)
	)
	debug_drill_range_game_px_override_value = clampf(
		float(c.get_value(sec, "drill_px_ovrd_val", debug_drill_range_game_px_override_value)),
		DEBUG_VEHICLE_OVERRIDE_MIN_DRILL_RANGE_GAME_PX,
		2048.0,
	)
	debug_turn_rate_rad_s_override_enabled = bool(
		c.get_value(sec, "turn_ovrd_en", debug_turn_rate_rad_s_override_enabled)
	)
	debug_turn_rate_rad_s_override_value = clampf(
		float(c.get_value(sec, "turn_ovrd_val", debug_turn_rate_rad_s_override_value)),
		0.0,
		1000.0,
	)


func save_debug_preferences() -> void:
	if _debug_prefs_write_pending:
		return
	_debug_prefs_write_pending = true
	call_deferred("_flush_debug_prefs_write")


func _flush_debug_prefs_write() -> void:
	_debug_prefs_write_pending = false
	var c := ConfigFile.new()
	var sec := _DEBUG_PREFS_SECTION
	c.set_value(sec, "world_visuals", debug_world_visuals)
	c.set_value(sec, "camera_zoom_mul", debug_camera_zoom_multiplier)
	c.set_value(sec, "gold_give_spin", debug_menu_gold_give_spin)
	c.set_value(sec, "fuel_ovrd_en", debug_fuel_max_override_enabled)
	c.set_value(sec, "fuel_ovrd_val", debug_fuel_max_override_value)
	c.set_value(sec, "speed_ovrd_en", debug_move_speed_override_enabled)
	c.set_value(sec, "speed_ovrd_val", debug_move_speed_override_value)
	c.set_value(sec, "mine_dmg_ovrd_en", debug_mine_damage_override_enabled)
	c.set_value(sec, "mine_dmg_ovrd_val", debug_mine_damage_override_value)
	c.set_value(sec, "mine_ivl_ovrd_en", debug_mine_interval_override_enabled)
	c.set_value(sec, "mine_ivl_ovrd_val", debug_mine_interval_override_value)
	c.set_value(sec, "drill_px_ovrd_en", debug_drill_range_game_px_override_enabled)
	c.set_value(sec, "drill_px_ovrd_val", debug_drill_range_game_px_override_value)
	c.set_value(sec, "turn_ovrd_en", debug_turn_rate_rad_s_override_enabled)
	c.set_value(sec, "turn_ovrd_val", debug_turn_rate_rad_s_override_value)
	var err := c.save(_DEBUG_PREFS_PATH)
	if err != OK:
		push_error("GameStatistics._flush_debug_prefs_write failed: %s" % error_string(err))


func notify_debug_fuel_max_override(enabled: bool, value: float) -> void:
	debug_fuel_max_override_value = maxf(DEBUG_VEHICLE_OVERRIDE_MIN_FUEL_MAX, value)
	debug_fuel_max_override_enabled = enabled
	_refit_live_fuel_max_preserving_fill()
	save_debug_preferences()


func notify_debug_move_speed_override(enabled: bool, value: float) -> void:
	debug_move_speed_override_value = maxf(DEBUG_VEHICLE_OVERRIDE_MIN_MOVE_PX, value)
	debug_move_speed_override_enabled = enabled
	save_debug_preferences()


func notify_debug_mine_damage_override(enabled: bool, value: float) -> void:
	debug_mine_damage_override_value = maxf(DEBUG_VEHICLE_OVERRIDE_MIN_MINE_DAMAGE, value)
	debug_mine_damage_override_enabled = enabled
	save_debug_preferences()


func notify_debug_mine_interval_override(enabled: bool, value_s: float) -> void:
	debug_mine_interval_override_value = clampf(
		value_s,
		DEBUG_VEHICLE_OVERRIDE_MIN_MINE_INTERVAL_S,
		999.0,
	)
	debug_mine_interval_override_enabled = enabled
	save_debug_preferences()


func notify_debug_drill_range_game_px_override(enabled: bool, value_px: float) -> void:
	debug_drill_range_game_px_override_value = clampf(
		value_px,
		DEBUG_VEHICLE_OVERRIDE_MIN_DRILL_RANGE_GAME_PX,
		2048.0,
	)
	debug_drill_range_game_px_override_enabled = enabled
	save_debug_preferences()


func notify_debug_turn_rate_rad_s_override(enabled: bool, value_rad_s: float) -> void:
	debug_turn_rate_rad_s_override_value = clampf(value_rad_s, 0.0, 1000.0)
	debug_turn_rate_rad_s_override_enabled = enabled
	save_debug_preferences()


func _refit_live_fuel_max_preserving_fill() -> void:
	var old_m: float = fuel_max
	var new_m: float = effective_fuel_max()
	var cap_abs := new_m * FUEL_ABSOLUTE_CAP_MUL
	if old_m <= 0.0:
		fuel_max = new_m
		fuel = minf(fuel, cap_abs)
	elif is_equal_approx(old_m, new_m):
		if fuel > cap_abs:
			fuel = cap_abs
			fuel_changed.emit(fuel, fuel_max)
			stats_changed.emit()
		return
	else:
		var frac := fuel / old_m if old_m > 0.0 else 1.0
		fuel_max = new_m
		fuel = minf(new_m * frac, cap_abs)
	fuel_changed.emit(fuel, fuel_max)
	stats_changed.emit()


func _apply_ship_fuel_base() -> void:
	var sd: Resource = ShipDataRegistry.get_active()
	if sd == null:
		push_error("ShipDataRegistry.get_active() returned null")
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


func reset_run_mining_economy_tracking() -> void:
	run_mined_money_awarded = 0
	_money_award_ticks_ms = PackedInt64Array()
	_money_award_amounts = PackedInt32Array()
	stats_changed.emit()


func reset_run_mined_resources() -> void:
	_run_mined_type_counts.clear()
	_run_mined_type_colors.clear()
	run_mined_resources_changed.emit()


## Call when a mineable cell is fully cleared (one increment per fuel cluster, not per fuel tile).
func register_fully_mined_block(type_id: int, display_color: Color) -> void:
	if type_id <= 0:
		return
	_run_mined_type_counts[type_id] = int(_run_mined_type_counts.get(type_id, 0)) + 1
	if not _run_mined_type_colors.has(type_id):
		_run_mined_type_colors[type_id] = display_color
	run_mined_resources_changed.emit()


func get_run_mined_resource_rows_sorted() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for tid_any in _run_mined_type_counts:
		var c: int = int(_run_mined_type_counts[tid_any])
		if c <= 0:
			continue
		var tid: int = int(tid_any)
		rows.append({
			"type_id": tid,
			"count": c,
			"color": _run_mined_type_colors.get(tid_any, Color.WHITE),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := int(a["count"])
		var cb := int(b["count"])
		if ca != cb:
			return ca > cb
		return int(a["type_id"]) < int(b["type_id"])
	)
	return rows


func _prune_run_money_award_log(now_ms: int) -> void:
	var cutoff := now_ms - RUN_MINING_ROLLING_MONEY_MS
	while _money_award_ticks_ms.size() > 0 and _money_award_ticks_ms[0] < cutoff:
		_money_award_ticks_ms.remove_at(0)
		_money_award_amounts.remove_at(0)


## Sum of awarded mined money over the last 10s wall clock, divided by 10.
func get_run_rolling_money_per_second() -> float:
	var now_ms: int = Time.get_ticks_msec()
	_prune_run_money_award_log(now_ms)
	var total: int = 0
	for i in _money_award_amounts.size():
		total += int(_money_award_amounts[i])
	return float(total) / (float(RUN_MINING_ROLLING_MONEY_MS) / 1000.0)


## Current fuel (including overflow) / leading ship `get_effective_fuel_drain_per_second`, or `INF` if no drain.
func get_fuel_seconds_remaining_from_leading_ship_drain() -> float:
	var st: SceneTree = get_tree()
	if st == null:
		return INF
	var n: Node = st.get_first_node_in_group(&"leading_mining_ship")
	var drain_ps: float = 0.0
	if n is ShipBase:
		drain_ps = (n as ShipBase).get_effective_fuel_drain_per_second()
	if drain_ps <= 0.0:
		return INF
	return fuel / drain_ps


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
	run_mined_money_awarded += amt
	_money_award_ticks_ms.append(Time.get_ticks_msec())
	_money_award_amounts.append(amt)
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


func nominal_effective_fuel_max() -> float:
	var upgraded: float = ShipDataRegistry.apply_effects_for_stat(&"fuel_max", _base_fuel_max)
	return PartRegistry.apply_effects_for_stat(&"fuel_max", upgraded)


func effective_fuel_max() -> float:
	if debug_fuel_max_override_enabled:
		return maxf(DEBUG_VEHICLE_OVERRIDE_MIN_FUEL_MAX, debug_fuel_max_override_value)
	return nominal_effective_fuel_max()


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
