extends Node

## Persists run selection across Prep → planet scenes. Autoload.
const PREP_SCENE := "res://scenes/prep/Prep.tscn"
const _CAREER_SAVE_PATH := "user://career.cfg"
const _CAREER_SECTION := "career"
const _CAREER_KEY_BLOCKS := "total_blocks_destroyed"
const _CAREER_KEY_MONEY := "money"

const _STAGE_REVEAL_MAGIC := 0x52455631
const _MINING_CHUNK_BYTES := 40 * 40
const _BLOCK_DISCOVERY_SECTION := "block_discovery"

var selected_ship_id: StringName = &"scout"
## Reserved: slot index → turret type id; empty = no pre-mounted turrets from Prep.
var mounted_turrets: Array[Dictionary] = []
## Default when Prep calls `go_to_planet(GameSession.next_planet_scene)`.
var next_planet_scene: String = "res://scenes/planets/Planet1.tscn"
## Cumulative blocks destroyed across completed runs; saved to disk.
var career_blocks_destroyed: int = 0
var _career_write_pending: bool = false
## `stage_id` (String) -> { type_id: true } for types seen (vision) or hit (damage).
var _stage_block_types_found: Dictionary = {}


func _ready() -> void:
	_load_career()


func go_to_planet(path: String) -> void:
	if path.is_empty():
		push_error("GameSession.go_to_planet: path empty")
		return
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("GameSession.go_to_planet failed: %s" % error_string(err))


func return_to_prep() -> void:
	var err := get_tree().change_scene_to_file(PREP_SCENE)
	if err != OK:
		push_error("GameSession.return_to_prep failed: %s" % error_string(err))


func _load_career() -> void:
	var c := ConfigFile.new()
	if c.load(_CAREER_SAVE_PATH) != OK:
		return
	career_blocks_destroyed = int(c.get_value(_CAREER_SECTION, _CAREER_KEY_BLOCKS, 0))
	GameStatistics.money = maxi(0, int(c.get_value(_CAREER_SECTION, _CAREER_KEY_MONEY, 0)))
	UpgradeBus.read_from_career_config(c)
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
	UpgradeBus.write_to_career_config(c)
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


## Call when a solid block type is revealed or damaged (unlocks bestiary row on prep).
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


## Call from Prep when starting a mission so HUD "blocks" counts this run only.
func begin_run() -> void:
	GameStatistics.set_blocks_run_baseline()
	GameStatistics.reset_fuel_for_run()


func _stage_reveal_path(stage_id: StringName) -> String:
	var sid := String(stage_id).strip_edges()
	sid = sid.replace("/", "_").replace("\\", "_")
	return "user://stage_%s_reveal.dat" % sid


## Returns Dictionary with Vector2i keys -> PackedByteArray reveal mask (40*40 bytes per chunk).
func load_stage_reveal(stage_id: StringName) -> Dictionary:
	var path := _stage_reveal_path(stage_id)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GameSession.load_stage_reveal: cannot read %s" % path)
		return {}
	var magic := f.get_32()
	if magic != _STAGE_REVEAL_MAGIC:
		return {}
	var count := f.get_32()
	var out: Dictionary = {}
	for _i in count:
		var cx := f.get_32()
		var cy := f.get_32()
		var buf := f.get_buffer(_MINING_CHUNK_BYTES)
		if buf.size() < _MINING_CHUNK_BYTES:
			break
		out[Vector2i(cx, cy)] = buf
	return out


func save_stage_reveal(stage_id: StringName, reveals: Dictionary) -> void:
	var path := _stage_reveal_path(stage_id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("GameSession.save_stage_reveal: cannot write %s" % path)
		return
	f.store_32(_STAGE_REVEAL_MAGIC)
	f.store_32(reveals.size())
	for k in reveals:
		var v2: Vector2i = k
		var barr: PackedByteArray = reveals[k]
		f.store_32(v2.x)
		f.store_32(v2.y)
		var b := barr.duplicate()
		if b.size() < _MINING_CHUNK_BYTES:
			b.resize(_MINING_CHUNK_BYTES)
		f.store_buffer(b)


## Debug: wipe career save, money, upgrades, derived combat stats, and stage reveal files.
func reset_all_progress() -> void:
	career_blocks_destroyed = 0
	GameStatistics.money = 0
	GameStatistics.total_blocks_destroyed = 0
	GameStatistics._blocks_destroyed_run_baseline = 0
	GameStatistics.furthest_depth_cells = 0
	GameStatistics.damage_to_blocks_laser_turret = 0
	GameStatistics.damage_to_blocks_cannon_turret = 0
	GameStatistics.damage_to_blocks_click = 0
	GameStatistics.laser_turret_damage = 1
	GameStatistics.cannon_turret_damage = 5
	GameStatistics.cannon_explosion_radius_px = 16.0
	GameStatistics.click_damage = 1
	GameStatistics.click_radius_cells = 2
	GameStatistics.click_fire_rate_ms = GameStatistics.CLICK_FIRE_RATE_START_MS
	GameStatistics.fuel_max = GameStatistics.BASE_FUEL_MAX
	GameStatistics.fuel = GameStatistics.fuel_max
	UpgradeBus._levels.clear()
	_stage_block_types_found.clear()
	_career_write_pending = false
	_write_career_to_disk()
	_delete_all_stage_reveal_files()
	GameStatistics.fuel_changed.emit(GameStatistics.fuel, GameStatistics.fuel_max)
	GameStatistics.stats_changed.emit()


func _delete_all_stage_reveal_files() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("stage_") and fname.ends_with("_reveal.dat"):
			DirAccess.remove_absolute("user://" + fname)
		fname = dir.get_next()
	dir.list_dir_end()


## Commit this run’s block count to career and load Prep (fuel out, manual exit from debug, etc.).
func end_current_run_to_prep() -> void:
	career_blocks_destroyed += GameStatistics.get_blocks_destroyed_this_run()
	_career_write_pending = false
	_write_career_to_disk()
	GameStatistics.set_blocks_run_baseline()
	call_deferred("return_to_prep")


func on_ship_destroyed() -> void:
	end_current_run_to_prep()
