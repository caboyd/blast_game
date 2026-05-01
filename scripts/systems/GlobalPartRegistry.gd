extends Node

signal parts_changed

const _GLOBAL_PARTS_DIR := "res://data/global_parts/"
const _CONFIG_SECTION_PARTS := "global_parts"
const _CONFIG_SECTION_PICKUPS := "global_part_pickups"
const _CONFIG_SECTION_PART_LEVELS := "global_part_levels"

const KEY_FUEL_TANK := &"fuel_tank"
const KEY_DRILL := &"drill"
const KEY_TREADS := &"treads"

const DEFAULT_FUEL_TANK := &"part_fuel_tank_t0"
const DEFAULT_DRILL := &"part_drill_t0"
const DEFAULT_TREADS := &"part_treads_t0"

const PICKUP_PERSISTENCE_ONCE := &"once"
const PICKUP_PERSISTENCE_RESPAWNABLE := &"respawnable"
const _LEGACY_PLANET1_PICKUP_PREFIX := "planet1_"
const _LEGACY_PART_IDS := {
	&"cracked_fuel_tank": &"part_fuel_tank_t0",
	&"dilapidated_fuel_tank": &"part_fuel_tank_t1",
	&"fuel_tank_t0": &"part_fuel_tank_t0",
	&"fuel_tank_t1": &"part_fuel_tank_t1",
	&"cracked_drill": &"part_drill_t0",
	&"dilapidated_drill": &"part_drill_t1",
	&"drill_t0": &"part_drill_t0",
	&"drill_t1": &"part_drill_t1",
	&"cracked_treads": &"part_treads_t0",
	&"dilapidated_treads": &"part_treads_t1",
	&"treads_t0": &"part_treads_t0",
	&"treads_t1": &"part_treads_t1",
}

const _SHIP_UPGRADE_MATH = preload("res://scripts/data/ShipUpgradeMath.gd")
const _GlobalPartDataScript = preload("res://scripts/data/GlobalPartData.gd")
const _GlobalPartStatEffect = preload("res://scripts/data/GlobalPartStatEffect.gd")
const _GlobalPartMovementPenaltyEffect = preload("res://scripts/data/GlobalPartMovementPenaltyEffect.gd")

var _parts_by_id: Dictionary = {} # StringName -> GlobalPartData

var equipped_fuel_tank_id: StringName = DEFAULT_FUEL_TANK
var equipped_drill_id: StringName = DEFAULT_DRILL
var equipped_treads_id: StringName = DEFAULT_TREADS

## pickup_id -> true
var _collected_pickups: Dictionary = {}

## part_id -> int level (>= 1). Missing keys mean level 1 once the part is relevant.
var _part_levels: Dictionary = {}


func _ready() -> void:
	_reload_definitions()


func _reload_definitions() -> void:
	_parts_by_id.clear()
	_load_definitions_in_dir(_GLOBAL_PARTS_DIR)


func _load_definitions_in_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("GlobalPartRegistry: cannot open %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir():
			if not fname.begins_with("."):
				_load_definitions_in_dir(dir_path.path_join(fname))
		elif fname.ends_with(".tres"):
			var path: String = dir_path.path_join(fname)
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			if res != null and res.get_script() == _GlobalPartDataScript:
				var pid: StringName = res.get("id") as StringName
				if String(pid).is_empty():
					push_error("GlobalPartRegistry: part id empty in %s" % path)
				else:
					_parts_by_id[pid] = res
		fname = dir.get_next()
	dir.list_dir_end()


func _normalize_part_id(part_id: StringName) -> StringName:
	return _LEGACY_PART_IDS.get(part_id, part_id) as StringName


func reset_to_t0_defaults() -> void:
	equipped_fuel_tank_id = DEFAULT_FUEL_TANK
	equipped_drill_id = DEFAULT_DRILL
	equipped_treads_id = DEFAULT_TREADS
	_collected_pickups.clear()
	_part_levels.clear()
	GameSession.clear_global_part_pickup_collected_by_type()
	parts_changed.emit()


func load_from_config_file(c: ConfigFile) -> void:
	if c.has_section(_CONFIG_SECTION_PARTS):
		var fuel_from_save: Variant = null
		if c.has_section_key(_CONFIG_SECTION_PARTS, String(KEY_FUEL_TANK)):
			fuel_from_save = c.get_value(_CONFIG_SECTION_PARTS, String(KEY_FUEL_TANK))
		if fuel_from_save == null:
			equipped_fuel_tank_id = DEFAULT_FUEL_TANK
		else:
			equipped_fuel_tank_id = _normalize_part_id(StringName(str(fuel_from_save)))
		equipped_drill_id = _normalize_part_id(
			StringName(str(c.get_value(_CONFIG_SECTION_PARTS, String(KEY_DRILL), String(DEFAULT_DRILL))))
		)
		equipped_treads_id = _normalize_part_id(
			StringName(str(c.get_value(_CONFIG_SECTION_PARTS, String(KEY_TREADS), String(DEFAULT_TREADS))))
		)
	else:
		equipped_fuel_tank_id = DEFAULT_FUEL_TANK
		equipped_drill_id = DEFAULT_DRILL
		equipped_treads_id = DEFAULT_TREADS
	_collected_pickups.clear()
	if c.has_section(_CONFIG_SECTION_PICKUPS):
		for k in c.get_section_keys(_CONFIG_SECTION_PICKUPS):
			if bool(c.get_value(_CONFIG_SECTION_PICKUPS, k, false)):
				_collected_pickups[StringName(k)] = true
	_part_levels.clear()
	if c.has_section(_CONFIG_SECTION_PART_LEVELS):
		for k in c.get_section_keys(_CONFIG_SECTION_PART_LEVELS):
			var raw: Variant = c.get_value(_CONFIG_SECTION_PART_LEVELS, k, 1)
			var lv: int = int(raw) if raw != null else 1
			var pid: StringName = _normalize_part_id(StringName(str(k)))
			lv = maxi(1, lv)
			var pd_lv: GlobalPartData = get_part_data(pid)
			if pd_lv != null:
				lv = mini(lv, pd_lv.get_max_level())
			if _part_levels.has(pid):
				_part_levels[pid] = maxi(_part_levels[pid], lv)
			else:
				_part_levels[pid] = lv
	## Preserve existing saves: equipped parts default to level 1 when no stored levels.
	for pid in [equipped_fuel_tank_id, equipped_drill_id, equipped_treads_id]:
		if not _part_levels.has(pid):
			_part_levels[pid] = 1


func write_to_config_file(c: ConfigFile) -> void:
	c.set_value(_CONFIG_SECTION_PARTS, String(KEY_FUEL_TANK), String(equipped_fuel_tank_id))
	c.set_value(_CONFIG_SECTION_PARTS, String(KEY_DRILL), String(equipped_drill_id))
	c.set_value(_CONFIG_SECTION_PARTS, String(KEY_TREADS), String(equipped_treads_id))
	for pid in _part_levels:
		var lv: int = int(_part_levels[pid])
		if lv > 0:
			c.set_value(_CONFIG_SECTION_PART_LEVELS, String(pid), lv)


func get_part_data(part_id: StringName) -> GlobalPartData:
	return _parts_by_id.get(_normalize_part_id(part_id)) as GlobalPartData


func get_equipped_for_type_key(type_key: StringName) -> StringName:
	match String(type_key):
		"fuel_tank":
			return equipped_fuel_tank_id
		"drill":
			return equipped_drill_id
		"treads":
			return equipped_treads_id
		_:
			return &""


func _slot_key_for_part_data(pd: GlobalPartData) -> StringName:
	match String(pd.part_type):
		"fuel_tank":
			return KEY_FUEL_TANK
		"drill":
			return KEY_DRILL
		"treads":
			return KEY_TREADS
		_:
			return &""


func get_part_level(part_id: StringName) -> int:
	part_id = _normalize_part_id(part_id)
	var lv: int = maxi(1, int(_part_levels.get(part_id, 1)))
	var pd: GlobalPartData = get_part_data(part_id)
	if pd != null:
		lv = mini(lv, pd.get_max_level())
	return lv


func get_part_max_level(part_id: StringName) -> int:
	var pd: GlobalPartData = get_part_data(part_id)
	if pd == null:
		return 1
	return pd.get_max_level()


func is_part_max_level(part_id: StringName) -> bool:
	return get_part_level(part_id) >= get_part_max_level(part_id)


## Central level + equip rule for pickups and upgrades.
func collect_part(part_id: StringName) -> void:
	part_id = _normalize_part_id(part_id)
	var pd: GlobalPartData = get_part_data(part_id)
	if pd == null:
		push_warning("GlobalPartRegistry.collect_part: unknown id %s" % String(part_id))
		return
	var slot_key: StringName = _slot_key_for_part_data(pd)
	if slot_key == &"":
		push_warning("GlobalPartRegistry.collect_part: bad part_type on %s" % String(part_id))
		return
	var cur: StringName = get_equipped_for_type_key(slot_key)
	if cur == part_id:
		var mx: int = get_part_max_level(part_id)
		var lv: int = get_part_level(part_id)
		if lv >= mx:
			return
		_part_levels[part_id] = lv + 1
		parts_changed.emit()
	else:
		_part_levels[part_id] = 1
		equip_part(part_id)
		## equip_part emits parts_changed


func equip_part(part_id: StringName) -> void:
	part_id = _normalize_part_id(part_id)
	var d: GlobalPartData = get_part_data(part_id)
	if d == null:
		push_warning("GlobalPartRegistry.equip_part: unknown id %s" % String(part_id))
		return
	match String(d.part_type):
		"fuel_tank":
			equipped_fuel_tank_id = part_id
		"drill":
			equipped_drill_id = part_id
		"treads":
			equipped_treads_id = part_id
		_:
			push_warning("GlobalPartRegistry.equip_part: bad part_type on %s" % String(part_id))
	parts_changed.emit()


## After upgrades: `base` is already ship-upgrade-adjusted.
func apply_effects_for_stat(stat: StringName, base: float) -> float:
	var st := GlobalPartEffect.normalize_stat_id(stat)
	var v: float = base
	for pk in [KEY_FUEL_TANK, KEY_DRILL, KEY_TREADS]:
		var pid: StringName = get_equipped_for_type_key(pk)
		var pd: GlobalPartData = get_part_data(pid)
		if pd == null:
			continue
		var level: int = get_part_level(pid)
		for eff in pd.get_effects_for_level(level):
			if eff == null or not (eff is _GlobalPartStatEffect):
				continue
			var se := eff as _GlobalPartStatEffect
			var est := GlobalPartEffect.normalize_stat_id(se.stat)
			if est != st:
				continue
			v = _SHIP_UPGRADE_MATH.apply_effect(v, 1, se)
	return v


func get_drill_allowed_mine_type_ids() -> PackedInt32Array:
	var pid: StringName = equipped_drill_id
	var pd: GlobalPartData = get_part_data(pid)
	if pd == null:
		return PackedInt32Array()
	return pd.allowed_mine_type_ids


func treads_movement_effect_timing() -> PackedFloat32Array:
	## [0]=every_s, [1]=duration_s, [2]=speed multiplier during penalty [0–1]; empty or zeros = no stutter
	var pd: GlobalPartData = get_part_data(equipped_treads_id)
	if pd == null:
		return PackedFloat32Array([0.0, 0.0, 0.0])
	var lv: int = get_part_level(equipped_treads_id)
	for eff in pd.get_effects_for_level(lv):
		if eff == null or not (eff is _GlobalPartMovementPenaltyEffect):
			continue
		var mpe := eff as _GlobalPartMovementPenaltyEffect
		var ev: float = float(mpe.every_s)
		var du: float = float(mpe.duration_s)
		if ev > 0.0 and du > 0.0:
			var mult: float = clampf(float(mpe.speed_multiplier), 0.0, 1.0)
			return PackedFloat32Array([ev, du, mult])
	return PackedFloat32Array([0.0, 0.0, 0.0])


func migrate_legacy_pickup_ids_to_game_session_pickup_slots() -> void:
	for pickup_id_any in _collected_pickups.keys():
		if bool(_collected_pickups[pickup_id_any]):
			_try_migrate_one_legacy_pickup_id_to_game_session(StringName(str(pickup_id_any)))


func _try_migrate_one_legacy_pickup_id_to_game_session(pickup_id: StringName) -> void:
	var s: String = String(pickup_id)
	var pickup_index: int = 0
	var after_planet: String = ""
	var idx_marker := s.rfind("_i")
	if idx_marker >= 0:
		var suffix: String = s.substr(idx_marker + 2)
		if suffix.is_empty() or not suffix.is_valid_int():
			return
		pickup_index = int(suffix)
		var before_idx: String = s.substr(0, idx_marker)
		if not before_idx.begins_with(_LEGACY_PLANET1_PICKUP_PREFIX):
			return
		after_planet = before_idx.substr(_LEGACY_PLANET1_PICKUP_PREFIX.length())
	else:
		if not s.begins_with(_LEGACY_PLANET1_PICKUP_PREFIX):
			return
		after_planet = s.substr(_LEGACY_PLANET1_PICKUP_PREFIX.length())
		pickup_index = 0
	if after_planet.is_empty():
		return
	var part_id: StringName = StringName(after_planet)
	var pd: GlobalPartData = get_part_data(part_id)
	if pd == null:
		return
	var slot_key: StringName = _slot_key_for_part_data(pd)
	if slot_key == &"":
		return
	GameSession.mark_global_part_pickup_collected(slot_key, int(pd.tier), pickup_index)


func is_slot_pickup_collected(part_id: StringName, pickup_index: int) -> bool:
	var pd: GlobalPartData = get_part_data(part_id)
	if pd == null:
		return false
	var slot_key: StringName = _slot_key_for_part_data(pd)
	if slot_key == &"":
		return false
	return GameSession.is_global_part_pickup_collected(slot_key, int(pd.tier), pickup_index)


func mark_once_global_part_pickup(part_id: StringName, pickup_index: int, pickup_id: StringName) -> void:
	if pickup_id != &"":
		_collected_pickups[pickup_id] = true
	var pd: GlobalPartData = get_part_data(part_id)
	if pd == null:
		return
	var slot_key: StringName = _slot_key_for_part_data(pd)
	if slot_key == &"":
		return
	GameSession.mark_global_part_pickup_collected(slot_key, int(pd.tier), pickup_index)


func is_pickup_collected(pickup_id: StringName) -> bool:
	return bool(_collected_pickups.get(pickup_id, false))


func mark_pickup_collected(pickup_id: StringName) -> void:
	_collected_pickups[pickup_id] = true


func should_skip_spawn_for_pickup_def(
	persistence: StringName,
	pickup_id: StringName,
	part_id: StringName,
	pickup_index: int = 0
) -> bool:
	if persistence == PICKUP_PERSISTENCE_ONCE:
		var pd_once: GlobalPartData = get_part_data(part_id)
		if pd_once != null:
			var slot_once: StringName = _slot_key_for_part_data(pd_once)
			if slot_once != &"":
				if GameSession.is_global_part_pickup_collected(slot_once, int(pd_once.tier), pickup_index):
					return true
		return is_pickup_collected(pickup_id)
	if persistence == PICKUP_PERSISTENCE_RESPAWNABLE:
		var pd: GlobalPartData = get_part_data(part_id)
		if pd == null:
			return false
		var slot_key: StringName = _slot_key_for_part_data(pd)
		if slot_key == &"":
			return false
		return get_equipped_for_type_key(slot_key) == part_id and is_part_max_level(part_id)
	return is_pickup_collected(pickup_id)
