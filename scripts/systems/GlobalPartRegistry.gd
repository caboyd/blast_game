extends Node

signal parts_changed

const _GLOBAL_PARTS_DIR := "res://data/global_parts/"
const _CONFIG_SECTION_PARTS := "global_parts"
const _CONFIG_SECTION_PICKUPS := "global_part_pickups"

const KEY_FUEL_TANK := &"fuel_tank"
const KEY_DRILL := &"drill"
const KEY_TREADS := &"treads"

const DEFAULT_CRACKED_TANK := &"cracked_tank"
const DEFAULT_CRACKED_DRILL := &"cracked_drill"
const DEFAULT_CRACKED_TREADS := &"cracked_treads"

const _SHIP_UPGRADE_MATH = preload("res://scripts/data/ShipUpgradeMath.gd")
const _GlobalPartDataScript = preload("res://scripts/data/GlobalPartData.gd")

var _parts_by_id: Dictionary = {} # StringName -> GlobalPartData

var equipped_fuel_tank_id: StringName = DEFAULT_CRACKED_TANK
var equipped_drill_id: StringName = DEFAULT_CRACKED_DRILL
var equipped_treads_id: StringName = DEFAULT_CRACKED_TREADS

## pickup_id -> true
var _collected_pickups: Dictionary = {}


func _ready() -> void:
	_reload_definitions()


func _reload_definitions() -> void:
	_parts_by_id.clear()
	var dir := DirAccess.open(_GLOBAL_PARTS_DIR)
	if dir == null:
		push_error("GlobalPartRegistry: cannot open %s" % _GLOBAL_PARTS_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path: String = _GLOBAL_PARTS_DIR.path_join(fname)
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			if res != null and res.get_script() == _GlobalPartDataScript:
				var pid: StringName = res.get("id") as StringName
				if String(pid).is_empty():
					push_error("GlobalPartRegistry: part id empty in %s" % path)
				else:
					_parts_by_id[pid] = res
		fname = dir.get_next()
	dir.list_dir_end()


func reset_to_cracked_defaults() -> void:
	equipped_fuel_tank_id = DEFAULT_CRACKED_TANK
	equipped_drill_id = DEFAULT_CRACKED_DRILL
	equipped_treads_id = DEFAULT_CRACKED_TREADS
	_collected_pickups.clear()
	parts_changed.emit()


func load_from_config_file(c: ConfigFile) -> void:
	if c.has_section(_CONFIG_SECTION_PARTS):
		equipped_fuel_tank_id = StringName(
			str(c.get_value(_CONFIG_SECTION_PARTS, String(KEY_FUEL_TANK), String(DEFAULT_CRACKED_TANK)))
		)
		equipped_drill_id = StringName(
			str(c.get_value(_CONFIG_SECTION_PARTS, String(KEY_DRILL), String(DEFAULT_CRACKED_DRILL)))
		)
		equipped_treads_id = StringName(
			str(c.get_value(_CONFIG_SECTION_PARTS, String(KEY_TREADS), String(DEFAULT_CRACKED_TREADS)))
		)
	else:
		equipped_fuel_tank_id = DEFAULT_CRACKED_TANK
		equipped_drill_id = DEFAULT_CRACKED_DRILL
		equipped_treads_id = DEFAULT_CRACKED_TREADS
	_collected_pickups.clear()
	if c.has_section(_CONFIG_SECTION_PICKUPS):
		for k in c.get_section_keys(_CONFIG_SECTION_PICKUPS):
			if bool(c.get_value(_CONFIG_SECTION_PICKUPS, k, false)):
				_collected_pickups[StringName(k)] = true


func write_to_config_file(c: ConfigFile) -> void:
	c.set_value(_CONFIG_SECTION_PARTS, String(KEY_FUEL_TANK), String(equipped_fuel_tank_id))
	c.set_value(_CONFIG_SECTION_PARTS, String(KEY_DRILL), String(equipped_drill_id))
	c.set_value(_CONFIG_SECTION_PARTS, String(KEY_TREADS), String(equipped_treads_id))
	for pid in _collected_pickups:
		if _collected_pickups[pid]:
			c.set_value(_CONFIG_SECTION_PICKUPS, String(pid), true)


func get_part_data(part_id: StringName) -> GlobalPartData:
	return _parts_by_id.get(part_id) as GlobalPartData


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


func equip_part(part_id: StringName) -> void:
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
		for eff in pd.effects:
			if eff == null:
				continue
			if GlobalPartEffect.normalize_stat_id(eff.stat) != st:
				continue
			v = _SHIP_UPGRADE_MATH.apply_effect(v, 1, eff)
	return v


func get_drill_allowed_mine_type_ids() -> PackedInt32Array:
	var pid: StringName = equipped_drill_id
	var pd: GlobalPartData = get_part_data(pid)
	if pd == null:
		return PackedInt32Array()
	return pd.allowed_mine_type_ids


func treads_movement_stop_timing() -> Vector2:
	## x = every_s, y = duration_s; (0,0) = no stutter
	var pd: GlobalPartData = get_part_data(equipped_treads_id)
	if pd == null:
		return Vector2.ZERO
	return Vector2(pd.movement_stop_every_s, pd.movement_stop_duration_s)


func is_pickup_collected(pickup_id: StringName) -> bool:
	return bool(_collected_pickups.get(pickup_id, false))


func mark_pickup_collected(pickup_id: StringName) -> void:
	_collected_pickups[pickup_id] = true
