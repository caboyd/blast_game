extends Node

## Persists run selection across Prep → planet scenes. Autoload.
const PREP_SCENE := "res://scenes/prep/Prep.tscn"
const _CAREER_SAVE_PATH := "user://career.cfg"
const _CAREER_SECTION := "career"
const _CAREER_KEY_BLOCKS := "total_blocks_destroyed"
const _CAREER_KEY_MONEY := "money"

const _STAGE_REVEAL_MAGIC := 0x52455631
const _MINING_CHUNK_BYTES := 40 * 40

var selected_ship_id: StringName = &"scout"
## Reserved: slot index → turret type id; empty = no pre-mounted turrets from Prep.
var mounted_turrets: Array[Dictionary] = []
## Default when Prep calls `go_to_planet(GameSession.next_planet_scene)`.
var next_planet_scene: String = "res://scenes/planets/Planet1.tscn"
## Cumulative blocks destroyed across completed runs; saved to disk.
var career_blocks_destroyed: int = 0
var _career_write_pending: bool = false


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
	var err := c.save(_CAREER_SAVE_PATH)
	if err != OK:
		push_error("GameSession._write_career_to_disk failed: %s" % error_string(err))


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


func on_ship_destroyed() -> void:
	career_blocks_destroyed += GameStatistics.get_blocks_destroyed_this_run()
	_career_write_pending = false
	_write_career_to_disk()
	GameStatistics.set_blocks_run_baseline()
	call_deferred("return_to_prep")
