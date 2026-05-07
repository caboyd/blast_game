extends Node

## Emitted once when `init()` completes (idempotent).
signal session_ready

## Persists run selection across Prep → planet scenes. Autoload.
const PREP_SCENE := "res://scenes/prep/Prep.tscn"
const _CAREER_SAVE_PATH := "user://career.cfg"
const _CAREER_SECTION := "career"
const _PART_PICKUP_BY_TYPE_SECTION := "part_pickup_by_type"
const _CAREER_KEY_BLOCKS := "total_blocks_destroyed"
const _CAREER_KEY_MONEY := "money"
const _CAREER_KEY_SELECTED_SHIP := "selected_ship_id"
const _CAREER_KEY_SELECTED_STAGE := "selected_stage_id"
const _CAREER_KEY_WEAPON_LASER_TARGET := "weapon_laser_target_priority"

## Prep / runtime: automatic laser targeting when [member weapon_laser_target_priority] matches.
const WEAPON_LASER_TARGET_HEALTHIEST := 0
const WEAPON_LASER_TARGET_WEAKEST := 1
const WEAPON_LASER_TARGET_HIGHEST_VALUE := 2
const WEAPON_LASER_TARGET_HIGHEST_DENSITY := 3

const _MINING_CHUNK_BYTES := 32 * 32
const _BLOCK_DISCOVERY_SECTION := "block_discovery"
const _PLANET1_SCENE := preload("res://scenes/planets/Planet1.tscn")
const _PLANET2_SCENE := preload("res://scenes/planets/Planet2.tscn")

## Stage id → mission planet scene path.
const STAGE_PLANET_SCENE_PATHS: Dictionary = {
	&"planet1": "res://scenes/planets/Planet1.tscn",
	&"planet2": "res://scenes/planets/Planet2.tscn",
}
const STAGE_PLANET_SCENES: Dictionary = {
	&"planet1": _PLANET1_SCENE,
	&"planet2": _PLANET2_SCENE,
}

var selected_ship_id: StringName = &"scout"
var selected_stage_id: StringName = &"planet1"
## No money cost; clamped to [member WEAPON_LASER_TARGET_HEALTHIEST] .. [member WEAPON_LASER_TARGET_HIGHEST_DENSITY].
var weapon_laser_target_priority: int = WEAPON_LASER_TARGET_HEALTHIEST
## Cumulative blocks destroyed across completed runs; saved to disk.
var career_blocks_destroyed: int = 0
var _career_write_pending: bool = false
## Wall-clock start for mission timer (see `get_mission_elapsed_sec`); set in `begin_run()`.
var _mission_start_ticks_msec: int = 0
## `stage_id` (String) -> { type_id: true } for types hit (damage).
var _stage_block_types_found: Dictionary = {}
## String slot key (`fuel_tank` / `drill` / `treads`) → dict composite key `"%d|%d" % [tier, pickup_index]` → true
var _part_pickups_by_type: Dictionary = {}

var initialized := false


func init() -> void:
	if initialized:
		return
	_load_career()
	initialized = true
	session_ready.emit()


func go_to_planet(path: String) -> void:
	if path.is_empty():
		push_error("GameSession.go_to_planet: path empty")
		return
	var scene := _get_preloaded_planet_scene_for_path(path)
	var err := get_tree().change_scene_to_packed(scene) if scene != null else get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("GameSession.go_to_planet failed: %s" % error_string(err))


func get_stage_planet_scene_path() -> String:
	var sc: Variant = STAGE_PLANET_SCENE_PATHS.get(selected_stage_id)
	if typeof(sc) != TYPE_STRING:
		sc = STAGE_PLANET_SCENE_PATHS[&"planet1"]
	var p: String = str(sc).strip_edges()
	if p.is_empty():
		return str(STAGE_PLANET_SCENE_PATHS[&"planet1"])
	return p


func _get_preloaded_planet_scene_for_path(path: String) -> PackedScene:
	for sid in STAGE_PLANET_SCENE_PATHS:
		if STAGE_PLANET_SCENE_PATHS[sid] == path:
			return STAGE_PLANET_SCENES.get(sid) as PackedScene
	return null


func return_to_prep() -> void:
	var err := get_tree().change_scene_to_file(PREP_SCENE)
	if err != OK:
		push_error("GameSession.return_to_prep failed: %s" % error_string(err))


func _load_career() -> void:
	var c := ConfigFile.new()
	if c.load(_CAREER_SAVE_PATH) != OK:
		# First launch: no save yet — still apply ship-derived fuel max (and empty upgrade levels).
		UpgradeBus._levels.clear()
		clear_part_pickup_collected_by_type()
		PartRegistry.reset_to_t0_defaults()
		GameStatistics.apply_fuel_max_from_career_load()
		return
	career_blocks_destroyed = int(c.get_value(_CAREER_SECTION, _CAREER_KEY_BLOCKS, 0))
	GameStatistics.money = maxi(0, int(c.get_value(_CAREER_SECTION, _CAREER_KEY_MONEY, 0)))
	selected_ship_id = StringName(
		str(c.get_value(_CAREER_SECTION, _CAREER_KEY_SELECTED_SHIP, "scout"))
	)
	var stage_raw: String = str(c.get_value(_CAREER_SECTION, _CAREER_KEY_SELECTED_STAGE, "planet1"))
	selected_stage_id = StringName(stage_raw)
	if not STAGE_PLANET_SCENES.has(selected_stage_id):
		selected_stage_id = &"planet1"
	var pri_raw: int = int(
		c.get_value(_CAREER_SECTION, _CAREER_KEY_WEAPON_LASER_TARGET, WEAPON_LASER_TARGET_HEALTHIEST)
	)
	weapon_laser_target_priority = clampi(
		pri_raw, WEAPON_LASER_TARGET_HEALTHIEST, WEAPON_LASER_TARGET_HIGHEST_DENSITY
	)
	if ShipDataRegistry:
		ShipDataRegistry.reload_active()
	UpgradeBus.read_from_career_config(c)
	PartRegistry.load_from_config_file(c)
	load_part_pickup_collected_from_config(c)
	GameStatistics.apply_fuel_max_from_career_load()
	_load_block_discovery_from_config(c)


## Persists career blocks + current money. Debounced to one write per frame when called from `GameStatistics` money changes.
func save_career() -> void:
	if _career_write_pending:
		return
	_career_write_pending = true
	call_deferred("_flush_career_write")


func _flush_career_write() -> void:
	_career_write_pending = false
	_write_career_to_disk()


func _write_career_to_disk() -> void:
	var c := ConfigFile.new()
	c.set_value(_CAREER_SECTION, _CAREER_KEY_BLOCKS, career_blocks_destroyed)
	c.set_value(_CAREER_SECTION, _CAREER_KEY_MONEY, GameStatistics.money)
	c.set_value(_CAREER_SECTION, _CAREER_KEY_SELECTED_SHIP, String(selected_ship_id))
	c.set_value(_CAREER_SECTION, _CAREER_KEY_SELECTED_STAGE, String(selected_stage_id))
	c.set_value(_CAREER_SECTION, _CAREER_KEY_WEAPON_LASER_TARGET, weapon_laser_target_priority)
	UpgradeBus.write_to_career_config(c)
	PartRegistry.write_to_config_file(c)
	write_part_pickup_collected_to_config(c)
	_write_block_discovery_to_config(c)
	var err := c.save(_CAREER_SAVE_PATH)
	if err != OK:
		push_error("GameSession._write_career_to_disk failed: %s" % error_string(err))


func is_block_type_discovered(stage_id: StringName, type_id: int) -> bool:
	if type_id <= 0:
		return true
	if not _stage_block_types_found.has(stage_id):
		return false
	return bool(_stage_block_types_found[stage_id].get(type_id, false))


## Call when a solid block type is damaged (unlocks bestiary row on prep).
func mark_block_type_discovered(stage_id: StringName, type_id: int) -> void:
	if type_id <= 0:
		return
	if not _stage_block_types_found.has(stage_id):
		_stage_block_types_found[stage_id] = {}
	var m: Dictionary = _stage_block_types_found[stage_id]
	if m.get(type_id, false):
		return
	m[type_id] = true
	save_career()


func _load_block_discovery_from_config(c: ConfigFile) -> void:
	_stage_block_types_found.clear()
	if not c.has_section(_BLOCK_DISCOVERY_SECTION):
		return
	for k in c.get_section_keys(_BLOCK_DISCOVERY_SECTION):
		var stage_key: String = String(k)
		var s: String = str(c.get_value(_BLOCK_DISCOVERY_SECTION, k, ""))
		s = s.strip_edges()
		if s.is_empty():
			continue
		var sid: StringName = StringName(stage_key)
		_stage_block_types_found[sid] = {}
		var m: Dictionary = _stage_block_types_found[sid]
		for part in s.split(","):
			var t: String = part.strip_edges()
			if t.is_empty():
				continue
			if t.is_valid_int():
				m[int(t)] = true


func _write_block_discovery_to_config(c: ConfigFile) -> void:
	if _stage_block_types_found.is_empty():
		return
	for sid in _stage_block_types_found:
		var m: Dictionary = _stage_block_types_found[sid]
		var ids: Array[int] = []
		for tid in m:
			if m[tid]:
				ids.append(int(tid))
		if ids.is_empty():
			continue
		ids.sort()
		var s_ids := ""
		for i in ids.size():
			if i > 0:
				s_ids += ","
			s_ids += str(ids[i])
		c.set_value(_BLOCK_DISCOVERY_SECTION, String(sid), s_ids)


func _slot_key_string(slot: StringName) -> String:
	return String(slot)


func clear_part_pickup_collected_by_type() -> void:
	_part_pickups_by_type.clear()


func _part_pickup_tuple_key(tier: int, pickup_index: int) -> String:
	return "%d|%d" % [tier, pickup_index]


func is_part_pickup_collected(type_key: StringName, tier: int, pickup_index: int) -> bool:
	var inner: Variant = _part_pickups_by_type.get(_slot_key_string(type_key))
	if inner == null:
		return false
	if typeof(inner) != TYPE_DICTIONARY:
		return false
	return bool((inner as Dictionary).get(_part_pickup_tuple_key(tier, pickup_index), false))


func mark_part_pickup_collected(type_key: StringName, tier: int, pickup_index: int) -> void:
	var slot_s: String = _slot_key_string(type_key)
	if slot_s.is_empty():
		return
	if not _part_pickups_by_type.has(slot_s):
		_part_pickups_by_type[slot_s] = {}
	var slot_map: Dictionary = _part_pickups_by_type[slot_s]
	slot_map[_part_pickup_tuple_key(tier, pickup_index)] = true


func load_part_pickup_collected_from_config(c: ConfigFile) -> void:
	_part_pickups_by_type.clear()
	if not c.has_section(_PART_PICKUP_BY_TYPE_SECTION):
		return
	for slot_s in c.get_section_keys(_PART_PICKUP_BY_TYPE_SECTION):
		var raw_v: Variant = c.get_value(_PART_PICKUP_BY_TYPE_SECTION, slot_s, "")
		var list_s: String = str(raw_v).strip_edges()
		if list_s.is_empty():
			continue
		if not _part_pickups_by_type.has(slot_s):
			_part_pickups_by_type[slot_s] = {}
		var inner: Dictionary = _part_pickups_by_type[slot_s]
		for part in list_s.split(","):
			var chunk: String = part.strip_edges()
			if chunk.is_empty():
				continue
			var segs: PackedStringArray = chunk.split(":")
			if segs.size() != 2:
				continue
			if not String(segs[0]).is_valid_int() or not String(segs[1]).is_valid_int():
				continue
			var t: int = int(segs[0])
			var pix: int = int(segs[1])
			inner[_part_pickup_tuple_key(t, pix)] = true


func write_part_pickup_collected_to_config(c: ConfigFile) -> void:
	for sk in _part_pickups_by_type:
		var inner_raw: Variant = _part_pickups_by_type[sk]
		if typeof(inner_raw) != TYPE_DICTIONARY:
			continue
		var inner_dict: Dictionary = inner_raw
		var tuples: PackedStringArray = PackedStringArray()
		for comp in inner_dict:
			if not bool(inner_dict[comp]):
				continue
			var segs: PackedStringArray = String(comp).split("|")
			if segs.size() != 2:
				continue
			tuples.append("%s:%s" % [segs[0], segs[1]])
		if tuples.is_empty():
			continue
		tuples.sort()
		var line := ""
		for i in tuples.size():
			if i > 0:
				line += ","
			line += tuples[i]
		c.set_value(_PART_PICKUP_BY_TYPE_SECTION, String(sk), line)


## Call from Prep when starting a mission so HUD "blocks" counts this run only.
func begin_run() -> void:
	GameStatistics.set_blocks_run_baseline()
	GameStatistics.reset_run_mining_economy_tracking()
	GameStatistics.reset_run_mined_resources()
	GameStatistics.reset_fuel_for_run()


## Call when entering a gameplay planet scene so the HUD mission timer measures time in-mission only.
func start_mission_timer() -> void:
	_mission_start_ticks_msec = Time.get_ticks_msec()


## Seconds since `start_mission_timer()` (gameplay mission clock). 0 if the clock was never started.
func get_mission_elapsed_sec() -> float:
	if _mission_start_ticks_msec == 0:
		return 0.0
	return float(Time.get_ticks_msec() - _mission_start_ticks_msec) / 1000.0


## Debug: wipe career save, money, upgrades, derived combat stats.
func reset_all_progress() -> void:
	career_blocks_destroyed = 0
	selected_ship_id = &"scout"
	selected_stage_id = &"planet1"
	GameStatistics.money = 0
	GameStatistics.total_blocks_destroyed = 0
	GameStatistics._blocks_destroyed_run_baseline = 0
	GameStatistics.furthest_depth_cells = 0
	GameStatistics.reset_run_mined_resources()
	UpgradeBus._levels.clear()
	clear_part_pickup_collected_by_type()
	PartRegistry.reset_to_t0_defaults()
	ShipDataRegistry.reload_all()
	GameStatistics._apply_ship_fuel_base()
	GameStatistics.fuel_max = GameStatistics.effective_fuel_max()
	GameStatistics.fuel = GameStatistics.fuel_max
	_stage_block_types_found.clear()
	_career_write_pending = false
	_write_career_to_disk()
	GameStatistics.fuel_changed.emit(GameStatistics.fuel, GameStatistics.fuel_max)
	GameStatistics.stats_changed.emit()


## Commit this run’s block count to career and load Prep (fuel out, manual exit from debug, etc.).
func end_current_run_to_prep() -> void:
	career_blocks_destroyed += GameStatistics.get_blocks_destroyed_this_run()
	_career_write_pending = false
	_write_career_to_disk()
	GameStatistics.set_blocks_run_baseline()
	call_deferred("return_to_prep")
