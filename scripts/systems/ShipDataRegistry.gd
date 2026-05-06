extends Node

## Emitted once when `init()` completes (idempotent; subsequent `init()` does not emit again).
signal registry_ready

## Loads all `res://data/ships/*.tres` and the active `ShipData` for `GameSession.selected_ship_id`
## (may be locked — use `is_ship_unlocked` before starting a run).
## Upgrade *levels* are global; effects from every ship's upgrade list apply together at runtime.
## The Prep shop only lists upgrades for the currently selected ship.

const _SHIP_DATA_SCRIPT = preload("res://scripts/data/ShipData.gd")
const _ShipUpgradeEffectScript = preload("res://scripts/data/ShipUpgradeEffect.gd")

const _SHIPS_DIR := "res://data/ships/"
const _SHIP_DATA_MANIFEST: Array[Resource] = [
	preload("res://data/ships/scout.tres"),
	preload("res://data/ships/prospector.tres"),
]

var _active: Resource
var _ships_by_id: Dictionary = {}  # StringName -> ShipData Resource
var _ship_ids_sorted: Array[StringName] = []
## First definition per `prep_sort_index` order (matches former `get_upgrade` scan).
var _upgrade_by_id: Dictionary = {}  # StringName -> upgrade resource
var _loaded := false
var _loading := false
var initialized := false


func init() -> void:
	if initialized:
		return
	ensure_loaded()
	initialized = true
	registry_ready.emit()


func reload_all() -> void:
	if _loading:
		return
	_loading = true
	_ships_by_id.clear()
	_ship_ids_sorted.clear()
	_upgrade_by_id.clear()
	_loaded = false
	var dir := DirAccess.open(_SHIPS_DIR)
	if dir == null:
		push_error("ShipDataRegistry: cannot open %s" % _SHIPS_DIR)
	else:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and _is_ship_resource_file(fname):
				var path: String = _SHIPS_DIR.path_join(_resource_path_from_dir_entry(fname))
				var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
				_register_ship_data_resource(res, path)
			fname = dir.get_next()
		dir.list_dir_end()
	for res in _SHIP_DATA_MANIFEST:
		_register_ship_data_resource(res, str(res.resource_path))
	var keys: Array = _ships_by_id.keys()
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			var sd_a: Resource = _ships_by_id[a] as Resource
			var sd_b: Resource = _ships_by_id[b] as Resource
			var ia: int = int(sd_a.get("prep_sort_index")) if sd_a != null else 0
			var ib: int = int(sd_b.get("prep_sort_index")) if sd_b != null else 0
			if ia != ib:
				return ia < ib
			return String(a) < String(b)
	)
	_ship_ids_sorted.clear()
	for k in keys:
		_ship_ids_sorted.append(k as StringName)
	_rebuild_upgrade_index()
	_loaded = true
	reload_active()
	_loading = false


func ensure_loaded() -> void:
	if _loaded or _loading:
		return
	reload_all()


func _is_ship_resource_file(fname: String) -> bool:
	return fname.ends_with(".tres") or fname.ends_with(".tres.remap")


func _resource_path_from_dir_entry(fname: String) -> String:
	if fname.ends_with(".remap"):
		return fname.trim_suffix(".remap")
	return fname


func _is_ship_data_resource(res: Resource) -> bool:
	return res != null and (res is ShipData or res.get_script() == _SHIP_DATA_SCRIPT)


func _register_ship_data_resource(res: Resource, path: String) -> void:
	if not _is_ship_data_resource(res):
		return
	var sid: StringName = res.get("id") as StringName
	if String(sid).is_empty():
		push_error("ShipDataRegistry: ship id empty in %s" % path)
	else:
		_ships_by_id[sid] = res


func _rebuild_upgrade_index() -> void:
	_upgrade_by_id.clear()
	for sid in _ship_ids_sorted:
		var sd: Resource = _ships_by_id.get(sid)
		if sd == null:
			continue
		var ups: Array = sd.get("upgrades") as Array
		for u in ups:
			if u == null:
				continue
			var uid: StringName = u.get("id") as StringName
			if not _upgrade_by_id.has(uid):
				_upgrade_by_id[uid] = u


func reload_active() -> void:
	ensure_loaded()
	var sid: StringName = GameSession.selected_ship_id
	if not _ships_by_id.has(sid):
		# Invalid id (e.g. removed ship): fall back to first unlocked ship.
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
	ensure_loaded()
	return _active


func get_ship_data(id: StringName) -> Resource:
	ensure_loaded()
	return _ships_by_id.get(id)


## Sorted by each ship's `prep_sort_index`, then id string (`ShipData`).
func get_all_ship_ids_sorted() -> Array[StringName]:
	ensure_loaded()
	return _ship_ids_sorted.duplicate()


## Selected ship first, then other unlocked ships in prep order. Used by Prep preview and mission ship chain tails.
func get_mission_ship_chain_ship_ids() -> Array[StringName]:
	ensure_loaded()
	var selected: StringName = GameSession.selected_ship_id
	var out: Array[StringName] = [selected]
	for sid in _ship_ids_sorted:
		if sid == selected:
			continue
		if not is_ship_unlocked(sid):
			continue
		out.append(sid)
	return out


## Every upgrade id defined on any ship (for save persistence and UpgradeBus).
func get_all_upgrade_ids() -> Array[StringName]:
	ensure_loaded()
	var out: Array[StringName] = []
	for k in _upgrade_by_id:
		out.append(k as StringName)
	return out


func get_upgrade(upgrade_id: StringName) -> Resource:
	ensure_loaded()
	if upgrade_id == &"":
		return null
	return _upgrade_by_id.get(upgrade_id)


func has_upgrade(upgrade_id: StringName) -> bool:
	ensure_loaded()
	if upgrade_id == &"":
		return false
	return _upgrade_by_id.has(upgrade_id)


## Upgrades shown in the shop for the currently active ship.
func get_active_ship_upgrades() -> Array:
	ensure_loaded()
	if _active == null:
		return []
	return _active.get("upgrades") as Array


func is_ship_unlocked(ship_id: StringName) -> bool:
	ensure_loaded()
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


## Empty if unlocked or unknown ship; shown on Prep when a locked ship is selected.
func get_ship_lock_reason(ship_id: StringName) -> String:
	if is_ship_unlocked(ship_id):
		return ""
	var sd: Resource = _ships_by_id.get(ship_id)
	if sd == null:
		return ""
	var authored: String = str(sd.get("unlock_requirement_text")).strip_edges()
	if not authored.is_empty():
		return authored
	var prereq: StringName = sd.get("unlock_after_ship_all_upgrades_maxed") as StringName
	if prereq == &"":
		return "Locked."
	var prereq_data: Resource = _ships_by_id.get(prereq)
	var pname: String = str(prereq_data.get("display_name")).strip_edges() if prereq_data != null else ""
	if pname.is_empty():
		pname = String(prereq)
	return "Unlock by maxing every upgrade on %s." % pname


func apply_effects_for_stat(stat: StringName, base: float) -> float:
	ensure_loaded()
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
				if eff != null and _ShipUpgradeEffectScript.normalize_effect_stat_id(eff.get("stat")) == stat:
					v = _ShipUpgradeEffectScript.apply_effect(v, lvl, eff)
	return v


func apply_effects_for_stat_int(stat: StringName, base: int) -> int:
	return int(round(float(apply_effects_for_stat(stat, float(base)))))


func _get_base_for_active_ship_stat(stat: StringName) -> float:
	ensure_loaded()
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
				if eff != null and _ShipUpgradeEffectScript.normalize_effect_stat_id(eff.get("stat")) == stat:
					v = _ShipUpgradeEffectScript.apply_effect(v, lvl, eff)
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
		var st: StringName = _ShipUpgradeEffectScript.normalize_effect_stat_id(eff.get("stat"))
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
