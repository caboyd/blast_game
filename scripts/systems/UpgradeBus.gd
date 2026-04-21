extends Node

## Central hub for upgrade purchases. UI calls `try_purchase`; gameplay systems connect to `upgrade_purchased`.
## Optional `max_level` in DEFS (inclusive cap on stored level after purchases). Omit `max_level` for infinite levels.

signal upgrade_purchased(id: StringName, new_level: int)

const DEFS: Dictionary = {
	&"laser_count": {"base_cost": 120, "multiplier": 2.0, "max_level": 6},
	&"laser_fire_rate": {"base_cost": 100, "multiplier": 2.0, "max_level": 0},
	&"melter": {"base_cost": 100, "multiplier": 2.0},
	&"cannon_count": {"base_cost": 120, "multiplier": 2.0, "max_level": 5},
	&"cannon_fire_rate": {"base_cost": 100, "multiplier": 2.0, "max_level": 0},
	&"cannon_shell": {"base_cost": 100, "multiplier": 2.0},
	&"click_count": {"base_cost": 1, "multiplier": 1.0, "max_level": 0},
	&"click_fire_rate": {"base_cost": 100, "multiplier": 2.0, "max_level": 59},
	&"click_dmg": {"base_cost": 100, "multiplier": 2.0},
	&"click_radius": {"base_cost": 100, "multiplier": 2.0},
}

var _levels: Dictionary = {}  # StringName -> int


func get_level(id: StringName) -> int:
	return int(_levels.get(id, 0))


## Returns inclusive max level, or -1 if unlimited.
func get_max_level(id: StringName) -> int:
	if not DEFS.has(id):
		return 0
	var d: Dictionary = DEFS[id]
	if not d.has("max_level"):
		return -1
	return int(d["max_level"])


func is_maxed(id: StringName) -> bool:
	var cap := get_max_level(id)
	if cap < 0:
		return false
	return get_level(id) >= cap


func can_upgrade(id: StringName) -> bool:
	return DEFS.has(id) and not is_maxed(id)


func get_cost(id: StringName) -> int:
	if not DEFS.has(id):
		return 999999999
	var level := get_level(id)
	var base: int = int(DEFS[id].get("base_cost", 100))
	var mult: float = float(DEFS[id].get("multiplier", 2.0))
	var c: float = float(base) * pow(mult, float(level))
	return maxi(1, int(round(c)))


func can_afford(id: StringName) -> bool:
	if not DEFS.has(id):
		return false
	return GameStatistics.money >= get_cost(id)


func can_purchase(id: StringName) -> bool:
	return can_upgrade(id) and can_afford(id)


func try_purchase(id: StringName) -> bool:
	if not DEFS.has(id):
		return false
	if is_maxed(id):
		return false
	if not can_afford(id):
		return false
	var cost := get_cost(id)
	if not GameStatistics.spend_money(cost):
		return false
	var new_level := get_level(id) + 1
	_levels[id] = new_level
	upgrade_purchased.emit(id, new_level)
	return true
