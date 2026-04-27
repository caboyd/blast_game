extends Node

## Loads `res://data/ships/<GameSession.selected_ship_id>.tres` and exposes mining ship stat/upgrade data.

const _SHIP_DATA_SCRIPT = preload("res://scripts/data/ShipData.gd")
const _SHIP_UPGRADE_MATH = preload("res://scripts/data/ShipUpgradeMath.gd")

var _active: Resource


func _ready() -> void:
	reload_active()


func reload_active() -> void:
	var sid: StringName = GameSession.selected_ship_id
	var path: String = "res://data/ships/%s.tres" % String(sid)
	if not ResourceLoader.exists(path):
		push_error("ShipDataRegistry: missing ship data at %s" % path)
		_active = null
		return
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null or res.get_script() != _SHIP_DATA_SCRIPT:
		push_error("ShipDataRegistry: not a ShipData resource: %s" % path)
		_active = null
		return
	_active = res


func get_active() -> Resource:
	return _active


func get_upgrade(id: StringName) -> Resource:
	if _active == null:
		return null
	var ups: Array = _active.get("upgrades") as Array
	for u in ups:
		if u != null and u.get("id") == id:
			return u
	return null


func has_upgrade(id: StringName) -> bool:
	return get_upgrade(id) != null


func apply_effects_for_stat(stat: StringName, base: float) -> float:
	var v: float = base
	if _active == null:
		return v
	var ups: Array = _active.get("upgrades") as Array
	for ud in ups:
		if ud == null:
			continue
		var uid: StringName = ud.get("id") as StringName
		var lvl: int = UpgradeBus.get_level(uid)
		if lvl <= 0:
			continue
		var effs: Array = ud.get("effects") as Array
		for eff in effs:
			if eff != null and eff.get("stat") == stat:
				v = _SHIP_UPGRADE_MATH.apply_effect(v, lvl, eff)
	return v


func apply_effects_for_stat_int(stat: StringName, base: int) -> int:
	return int(round(float(apply_effects_for_stat(stat, float(base)))))


func _get_base_for_stat(stat: StringName) -> float:
	if _active == null:
		return 0.0
	return _active.get_base_float_for_stat(stat)


## Effective value of `stat` if `focus_upgrade_id` were at `focus_level` and all other upgrades keep current career levels.
func preview_effective_stat(stat: StringName, focus_upgrade_id: StringName, focus_level: int) -> float:
	var v: float = _get_base_for_stat(stat)
	if _active == null:
		return v
	var ups: Array = _active.get("upgrades") as Array
	for ud in ups:
		if ud == null:
			continue
		var uid: StringName = ud.get("id") as StringName
		var lvl: int = focus_level if uid == focus_upgrade_id else UpgradeBus.get_level(uid)
		if lvl <= 0:
			continue
		var effs: Array = ud.get("effects") as Array
		for eff in effs:
			if eff != null and eff.get("stat") == stat:
				v = _SHIP_UPGRADE_MATH.apply_effect(v, lvl, eff)
	return v


## Each entry: `stat`, `before`, `after`, `delta` for buying `additional_levels` from current career level.
func preview_upgrade_stat_deltas(upgrade_id: StringName, additional_levels: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _active == null or additional_levels <= 0:
		return out
	var ud: Resource = get_upgrade(upgrade_id)
	if ud == null:
		return out
	var cur: int = UpgradeBus.get_level(upgrade_id)
	var target: int = cur + additional_levels
	var effs: Array = ud.get("effects") as Array
	for eff in effs:
		if eff == null:
			continue
		var st: StringName = eff.get("stat") as StringName
		var before: float = preview_effective_stat(st, upgrade_id, cur)
		var after: float = preview_effective_stat(st, upgrade_id, target)
		out.append(
			{"stat": st, "before": before, "after": after, "delta": after - before, "operation": eff.get("operation")}
		)
	return out
