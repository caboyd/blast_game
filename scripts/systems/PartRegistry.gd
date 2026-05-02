extends Node

signal parts_changed

const _PARTS_DIR := "res://data/parts/"
const _CONFIG_SECTION_PARTS := "parts"
const _CONFIG_SECTION_PART_LEVELS := "part_levels"

const KEY_FUEL_TANK := &"fuel_tank"
const KEY_DRILL := &"drill"
const KEY_TREADS := &"treads"

const DEFAULT_FUEL_TANK := &"part_fuel_tank_t0"
const DEFAULT_DRILL := &"part_drill_t0"
const DEFAULT_TREADS := &"part_treads_t0"

const PICKUP_PERSISTENCE_ONCE := &"once"
const PICKUP_PERSISTENCE_RESPAWNABLE := &"respawnable"

const _PartDataScript = preload("res://scripts/data/PartData.gd")
const _PartMovementPenaltyEffect = preload("res://scripts/data/PartMovementPenaltyEffect.gd")

var _parts_by_id: Dictionary = {} # StringName -> PartData

var equipped_fuel_tank_id: StringName = DEFAULT_FUEL_TANK
var equipped_drill_id: StringName = DEFAULT_DRILL
var equipped_treads_id: StringName = DEFAULT_TREADS

## part_id -> int level (>= 1). Missing keys mean level 1 once the part is relevant.
var _part_levels: Dictionary = {}


func _ready() -> void:
	_reload_definitions()


func _reload_definitions() -> void:
	_parts_by_id.clear()
	_load_definitions_in_dir(_PARTS_DIR)


func _load_definitions_in_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("PartRegistry: cannot open %s" % dir_path)
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
			if res != null and res.get_script() == _PartDataScript:
				var pid: StringName = res.get("id") as StringName
				if String(pid).is_empty():
					push_error("PartRegistry: part id empty in %s" % path)
				else:
					_parts_by_id[pid] = res
		fname = dir.get_next()
	dir.list_dir_end()


func reset_to_t0_defaults() -> void:
	equipped_fuel_tank_id = DEFAULT_FUEL_TANK
	equipped_drill_id = DEFAULT_DRILL
	equipped_treads_id = DEFAULT_TREADS
	_part_levels.clear()
	GameSession.clear_part_pickup_collected_by_type()
	parts_changed.emit()


func load_from_config_file(c: ConfigFile) -> void:
	if c.has_section(_CONFIG_SECTION_PARTS):
		var fuel_from_save: Variant = null
		if c.has_section_key(_CONFIG_SECTION_PARTS, String(KEY_FUEL_TANK)):
			fuel_from_save = c.get_value(_CONFIG_SECTION_PARTS, String(KEY_FUEL_TANK))
		if fuel_from_save == null:
			equipped_fuel_tank_id = DEFAULT_FUEL_TANK
		else:
			equipped_fuel_tank_id = StringName(str(fuel_from_save))
		equipped_drill_id = StringName(
			str(c.get_value(_CONFIG_SECTION_PARTS, String(KEY_DRILL), String(DEFAULT_DRILL)))
		)
		equipped_treads_id = StringName(
			str(c.get_value(_CONFIG_SECTION_PARTS, String(KEY_TREADS), String(DEFAULT_TREADS)))
		)
	else:
		equipped_fuel_tank_id = DEFAULT_FUEL_TANK
		equipped_drill_id = DEFAULT_DRILL
		equipped_treads_id = DEFAULT_TREADS
	_part_levels.clear()
	if c.has_section(_CONFIG_SECTION_PART_LEVELS):
		for k in c.get_section_keys(_CONFIG_SECTION_PART_LEVELS):
			var raw: Variant = c.get_value(_CONFIG_SECTION_PART_LEVELS, k, 1)
			var lv: int = int(raw) if raw != null else 1
			var pid: StringName = StringName(str(k))
			lv = maxi(1, lv)
			var pd_lv: PartData = get_part_data(pid)
			if pd_lv != null:
				lv = mini(lv, pd_lv.get_max_level())
			if _part_levels.has(pid):
				_part_levels[pid] = maxi(_part_levels[pid], lv)
			else:
				_part_levels[pid] = lv
	if get_part_data(equipped_fuel_tank_id) == null:
		equipped_fuel_tank_id = DEFAULT_FUEL_TANK
	if get_part_data(equipped_drill_id) == null:
		equipped_drill_id = DEFAULT_DRILL
	if get_part_data(equipped_treads_id) == null:
		equipped_treads_id = DEFAULT_TREADS
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


func get_part_data(part_id: StringName) -> PartData:
	return _parts_by_id.get(part_id) as PartData


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


func _slot_key_for_part_data(pd: PartData) -> StringName:
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
	var lv: int = maxi(1, int(_part_levels.get(part_id, 1)))
	var pd: PartData = get_part_data(part_id)
	if pd != null:
		lv = mini(lv, pd.get_max_level())
	return lv


func get_part_max_level(part_id: StringName) -> int:
	var pd: PartData = get_part_data(part_id)
	if pd == null:
		return 1
	return pd.get_max_level()


func is_part_max_level(part_id: StringName) -> bool:
	return get_part_level(part_id) >= get_part_max_level(part_id)


## Central level + equip rule for pickups and upgrades.
func collect_part(part_id: StringName) -> void:
	var pd: PartData = get_part_data(part_id)
	if pd == null:
		push_warning("PartRegistry.collect_part: unknown id %s" % String(part_id))
		return
	var slot_key: StringName = _slot_key_for_part_data(pd)
	if slot_key == &"":
		push_warning("PartRegistry.collect_part: bad part_type on %s" % String(part_id))
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
	var d: PartData = get_part_data(part_id)
	if d == null:
		push_warning("PartRegistry.equip_part: unknown id %s" % String(part_id))
		return
	match String(d.part_type):
		"fuel_tank":
			equipped_fuel_tank_id = part_id
		"drill":
			equipped_drill_id = part_id
		"treads":
			equipped_treads_id = part_id
		_:
			push_warning("PartRegistry.equip_part: bad part_type on %s" % String(part_id))
	parts_changed.emit()


## After upgrades: `base` is already ship-upgrade-adjusted.
func apply_effects_for_stat(stat: StringName, base: float) -> float:
	var st := ShipUpgradeEffect.normalize_stat_id(stat)
	var v: float = base
	for pk in [KEY_FUEL_TANK, KEY_DRILL, KEY_TREADS]:
		var pid: StringName = get_equipped_for_type_key(pk)
		var pd: PartData = get_part_data(pid)
		if pd == null:
			continue
		var level: int = get_part_level(pid)
		for eff in pd.get_effects_for_level(level):
			if eff == null or not (eff is ShipUpgradeEffect):
				continue
			var se := eff as ShipUpgradeEffect
			var est := ShipUpgradeEffect.normalize_stat_id(se.stat)
			if est != st:
				continue
			v = ShipUpgradeEffect.apply_effect(v, 1, se)
	return v


func get_drill_allowed_mine_type_ids() -> PackedInt32Array:
	var pid: StringName = equipped_drill_id
	var pd: PartData = get_part_data(pid)
	if pd == null:
		return PackedInt32Array()
	return pd.allowed_mine_type_ids


func treads_movement_effect_timing() -> PackedFloat32Array:
	## [0]=every_s, [1]=duration_s, [2]=speed multiplier during penalty [0–1]; empty or zeros = no stutter
	var pd: PartData = get_part_data(equipped_treads_id)
	if pd == null:
		return PackedFloat32Array([0.0, 0.0, 0.0])
	var lv: int = get_part_level(equipped_treads_id)
	for eff in pd.get_effects_for_level(lv):
		if eff == null or not (eff is _PartMovementPenaltyEffect):
			continue
		var mpe := eff as _PartMovementPenaltyEffect
		var ev: float = float(mpe.every_s)
		var du: float = float(mpe.duration_s)
		if ev > 0.0 and du > 0.0:
			var mult: float = clampf(float(mpe.speed_multiplier), 0.0, 1.0)
			return PackedFloat32Array([ev, du, mult])
	return PackedFloat32Array([0.0, 0.0, 0.0])


func is_slot_pickup_collected(part_id: StringName, pickup_index: int) -> bool:
	var pd: PartData = get_part_data(part_id)
	if pd == null:
		return false
	var slot_key: StringName = _slot_key_for_part_data(pd)
	if slot_key == &"":
		return false
	return GameSession.is_part_pickup_collected(slot_key, int(pd.tier), pickup_index)


func mark_once_part_pickup(part_id: StringName, pickup_index: int, _pickup_id: StringName) -> void:
	var pd: PartData = get_part_data(part_id)
	if pd == null:
		return
	var slot_key: StringName = _slot_key_for_part_data(pd)
	if slot_key == &"":
		return
	GameSession.mark_part_pickup_collected(slot_key, int(pd.tier), pickup_index)


func should_skip_spawn_for_pickup_def(
	persistence: StringName,
	_pickup_id: StringName,
	part_id: StringName,
	pickup_index: int = 0
) -> bool:
	if persistence == PICKUP_PERSISTENCE_ONCE:
		var pd_once: PartData = get_part_data(part_id)
		if pd_once != null:
			var slot_once: StringName = _slot_key_for_part_data(pd_once)
			if slot_once != &"":
				return GameSession.is_part_pickup_collected(
					slot_once, int(pd_once.tier), pickup_index
				)
		return false
	if persistence == PICKUP_PERSISTENCE_RESPAWNABLE:
		var pd: PartData = get_part_data(part_id)
		if pd == null:
			return false
		var slot_key: StringName = _slot_key_for_part_data(pd)
		if slot_key == &"":
			return false
		return get_equipped_for_type_key(slot_key) == part_id and is_part_max_level(part_id)
	return false
