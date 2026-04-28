extends Node

const _SHIP_UPGRADE_MATH = preload("res://scripts/data/ShipUpgradeMath.gd")

## Central hub for upgrade purchases. UI calls `try_purchase`; gameplay systems connect to `upgrade_purchased`.
## Mining upgrade defs/costs come from `ShipDataRegistry` (per-ship `.tres`). Legacy combat/click defs stay in code.
## Optional `max_level` in legacy defs (inclusive cap). Omit `max_level` for infinite levels.
## `laser_count` / `cannon_count` caps come from current Ship small-slot pool (shared).

signal upgrade_purchased(id: StringName, new_level: int)

const LEGACY_UPGRADE_DEFS: Dictionary = {
	&"laser_count": {"base_cost": 120, "multiplier": 2.0},
	&"laser_fire_rate": {"base_cost": 100, "multiplier": 2.0, "max_level": 0},
	&"melter": {"base_cost": 100, "multiplier": 2.0},
	&"cannon_count": {"base_cost": 120, "multiplier": 2.0},
	&"cannon_fire_rate": {"base_cost": 100, "multiplier": 2.0, "max_level": 0},
	&"cannon_shell": {"base_cost": 100, "multiplier": 2.0},
	&"cannon_blast": {"base_cost": 100, "multiplier": 2.0},
	&"click_count": {"base_cost": 1, "multiplier": 1.0, "max_level": 0},
	&"click_fire_rate": {"base_cost": 100, "multiplier": 2.0, "max_level": 59},
	&"click_dmg": {"base_cost": 100, "multiplier": 2.0},
	&"click_radius": {"base_cost": 100, "multiplier": 2.0},
}

var _levels: Dictionary = {}  # StringName -> int


func has_def(id: StringName) -> bool:
	return LEGACY_UPGRADE_DEFS.has(id) or ShipDataRegistry.has_upgrade(id)


func get_level(id: StringName) -> int:
	return int(_levels.get(id, 0))



## Returns inclusive max level, or -1 if unlimited.
func get_max_level(id: StringName) -> int:
	var vud: Resource = ShipDataRegistry.get_upgrade(id)
	if vud != null:
		return int(vud.get("max_level"))
	if not LEGACY_UPGRADE_DEFS.has(id):
		return 0
	var d: Dictionary = LEGACY_UPGRADE_DEFS[id]
	if not d.has("max_level"):
		return -1
	return int(d["max_level"])


func is_maxed(id: StringName) -> bool:
	var cap := get_max_level(id)
	if cap < 0:
		return false
	return get_level(id) >= cap


func can_upgrade(id: StringName) -> bool:
	return has_def(id) and not is_maxed(id)


func get_cost(id: StringName) -> int:
	if not has_def(id):
		return 999999999
	return _cost_at_level(id, get_level(id))


func _legacy_cost_at_level(id: StringName, level: int) -> int:
	var d: Dictionary = LEGACY_UPGRADE_DEFS[id]
	var base: int = int(d.get("base_cost", 100))
	var mult: float = float(d.get("multiplier", 2.0))
	var c: float = float(base) * pow(mult, float(level))
	return maxi(1, int(round(c)))


func _cost_at_level(id: StringName, level: int) -> int:
	var vud: Resource = ShipDataRegistry.get_upgrade(id)
	if vud != null:
		return _SHIP_UPGRADE_MATH.cost_at_level(vud, level)
	if LEGACY_UPGRADE_DEFS.has(id):
		return _legacy_cost_at_level(id, level)
	return 999999999


func can_afford(id: StringName) -> bool:
	if not has_def(id):
		return false
	return GameStatistics.money >= get_cost(id)


func can_purchase(id: StringName) -> bool:
	return can_upgrade(id) and can_afford(id)


func get_purchase_count_for_request(id: StringName, requested_count: int) -> int:
	if not has_def(id) or requested_count == 0 or is_maxed(id):
		return 0
	var desired: int = requested_count
	if requested_count < 0:
		desired = 2147483647
	var cap: int = get_max_level(id)
	var level: int = get_level(id)
	if cap >= 0:
		desired = mini(desired, maxi(0, cap - level))
	if desired <= 0:
		return 0

	var affordable_count := 0
	var total_cost := 0
	for i in range(desired):
		var next_cost := _cost_at_level(id, level + i)
		if total_cost + next_cost > GameStatistics.money:
			break
		total_cost += next_cost
		affordable_count += 1
	return affordable_count


func get_purchase_cost_for_count(id: StringName, count: int) -> int:
	if not has_def(id) or count <= 0 or is_maxed(id):
		return 0
	var cap: int = get_max_level(id)
	var level: int = get_level(id)
	var actual_count: int = count
	if cap >= 0:
		actual_count = mini(actual_count, maxi(0, cap - level))
	var total := 0
	for i in range(actual_count):
		total += _cost_at_level(id, level + i)
	return total


func try_purchase(id: StringName) -> bool:
	return try_purchase_count(id, 1)


func try_purchase_count(id: StringName, requested_count: int) -> bool:
	var count: int = get_purchase_count_for_request(id, requested_count)
	if count <= 0:
		return false
	if requested_count > 0 and count < requested_count:
		return false
	var cost := get_purchase_cost_for_count(id, count)
	if not GameStatistics.spend_money(cost, false):
		return false
	var new_level := get_level(id) + count
	_levels[id] = new_level
	upgrade_purchased.emit(id, new_level)
	GameSession.save_career()
	return true


const _CONFIG_SECTION := "upgrades"


func _all_persisted_upgrade_ids() -> Array[StringName]:
	var id_set: Dictionary = {}
	for k in LEGACY_UPGRADE_DEFS:
		id_set[k] = true
	for uid in ShipDataRegistry.get_all_upgrade_ids():
		id_set[uid] = true
	for k in _levels:
		id_set[k] = true
	var out: Array[StringName] = []
	for idn in id_set:
		out.append(idn)
	return out


func read_from_career_config(c: ConfigFile) -> void:
	_levels.clear()
	if not c.has_section(_CONFIG_SECTION):
		return
	for k in c.get_section_keys(_CONFIG_SECTION):
		var id: StringName = StringName(k)
		var n: int = int(c.get_value(_CONFIG_SECTION, k, 0))
		if n > 0:
			_levels[id] = n


func write_to_career_config(c: ConfigFile) -> void:
	for id in _all_persisted_upgrade_ids():
		c.set_value(_CONFIG_SECTION, String(id), get_level(id))
