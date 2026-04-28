extends Node

## Loads all `res://data/ships/*.tres` and the active `ShipData` for `GameSession.selected_ship_id`.
## Upgrade *levels* are global; effects from every ship's upgrade list apply together at runtime.
## The Prep shop only lists upgrades for the currently selected ship.

const _SHIP_DATA_SCRIPT = preload("res://scripts/data/ShipData.gd")
const _SHIP_UPGRADE_MATH = preload("res://scripts/data/ShipUpgradeMath.gd")

const _SHIPS_DIR := "res://data/ships/"

var _active: Resource
var _ships_by_id: Dictionary = {}  # StringName -> ShipData Resource
var _ship_ids_sorted: Array[StringName] = []


func _ready() -> void:
	reload_all()


func reload_all() -> void:
	_ships_by_id.clear()
	_ship_ids_sorted.clear()
	var dir := DirAccess.open(_SHIPS_DIR)
	if dir == null:
		push_error("ShipDataRegistry: cannot open %s" % _SHIPS_DIR)
		_active = null
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path: String = _SHIPS_DIR.path_join(fname)
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			if res != null and res.get_script() == _SHIP_DATA_SCRIPT:
				var sid: StringName = res.get("id") as StringName
				if String(sid).is_empty():
					push_error("ShipDataRegistry: ship id empty in %s" % path)
				else:
					_ships_by_id[sid] = res
		fname = dir.get_next()
	dir.list_dir_end()
	var keys: Array = _ships_by_id.keys()
	var skeys: Array[String] = []
	for k in keys:
		skeys.append(String(k))
	skeys.sort()
	_ship_ids_sorted.clear()
	for sk in skeys:
		_ship_ids_sorted.append(StringName(sk))
	reload_active()


func reload_active() -> void:
	var sid: StringName = GameSession.selected_ship_id
	if not _ships_by_id.has(sid) or not is_ship_unlocked(sid):
		# Fall back to first unlocked ship (usually scout).
		sid = &""
		for candidate in _ship_ids_sorted:
			if is_ship_unlocked(candidate):
				sid = candidate
				break
		if sid == &"" and not _ship_ids_sorted.is_empty():
			sid = _ship_ids_sorted[0]
		GameSession.selected_ship_id = sid
	_active = _ships_by_id.get(sid)


func get_active() -> Resource:
	return _active


func get_ship_data(id: StringName) -> Resource:
	return _ships_by_id.get(id)


func get_all_ship_ids_sorted() -> Array[StringName]:
	return _ship_ids_sorted.duplicate()


## Every upgrade id defined on any ship (for save persistence and UpgradeBus).
func get_all_upgrade_ids() -> Array[StringName]:
	var id_set: Dictionary = {}
	for sid in _ship_ids_sorted:
		var sd: Resource = _ships_by_id.get(sid)
		if sd == null:
			continue
		var ups: Array = sd.get("upgrades") as Array
		for u in ups:
			if u != null:
				id_set[u.get("id")] = true
	var out: Array[StringName] = []
	for k in id_set:
		out.append(k)
	return out


func get_upgrade(upgrade_id: StringName) -> Resource:
	if upgrade_id == &"":
		return null
	for sid in _ship_ids_sorted:
		var ups: Array = _ships_by_id[sid].get("upgrades") as Array
		for u in ups:
			if u != null and u.get("id") == upgrade_id:
				return u
	return null


func has_upgrade(upgrade_id: StringName) -> bool:
	return get_upgrade(upgrade_id) != null


## Upgrades shown in the shop for the currently active ship.
func get_active_ship_upgrades() -> Array:
	if _active == null:
		return []
	return _active.get("upgrades") as Array


func is_ship_unlocked(ship_id: StringName) -> bool:
	var sd: Resource = _ships_by_id.get(ship_id)
	if sd == null:
		return false
	var prereq: StringName = sd.get("unlock_after_ship_all_upgrades_maxed") as StringName
	if prereq == &"":
		return true
	var prereq_data: Resource = _ships_by_id.get(prereq)
	if prereq_data == null:
		push_error("ShipDataRegistry: missing prerequisite ship data %s" % String(prereq))
		return false
	var ups: Array = prereq_data.get("upgrades") as Array
	for u in ups:
		if u == null:
			continue
		var uid: StringName = u.get("id") as StringName
		if not UpgradeBus.is_maxed(uid):
			return false
	return true


func apply_effects_for_stat(stat: StringName, base: float) -> float:
	var v: float = base
	if _ship_ids_sorted.is_empty():
		return v
	for sid in _ship_ids_sorted:
		var sdata: Resource = _ships_by_id.get(sid)
		if sdata == null:
			continue
		var ups: Array = sdata.get("upgrades") as Array
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


func _get_base_for_active_ship_stat(stat: StringName) -> float:
	if _active == null:
		return 0.0
	return _active.get_base_float_for_stat(stat)


## Effective value of `stat` if `focus_upgrade_id` were at `focus_level` and all other upgrades keep current career levels.
func preview_effective_stat(stat: StringName, focus_upgrade_id: StringName, focus_level: int) -> float:
	var v: float = _get_base_for_active_ship_stat(stat)
	if _ship_ids_sorted.is_empty():
		return v
	for sid in _ship_ids_sorted:
		var sdata: Resource = _ships_by_id.get(sid)
		if sdata == null:
			continue
		var ups: Array = sdata.get("upgrades") as Array
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
	var shop_name: String = str(ud.get("shop_display_name"))
	for eff in effs:
		if eff == null:
			continue
		var st: StringName = eff.get("stat") as StringName
		var before: float = preview_effective_stat(st, upgrade_id, cur)
		var after: float = preview_effective_stat(st, upgrade_id, target)
		out.append(
			{
				"stat": st,
				"before": before,
				"after": after,
				"delta": after - before,
				"operation": eff.get("operation"),
				"shop_display_name": shop_name,
			}
		)
	return out
