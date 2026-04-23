extends Node

## Persists run selection across Prep → planet scenes. Autoload.
const PREP_SCENE := "res://scenes/prep/Prep.tscn"
const _CAREER_SAVE_PATH := "user://career.cfg"
const _CAREER_SECTION := "career"
const _CAREER_KEY_BLOCKS := "total_blocks_destroyed"
const _CAREER_KEY_MONEY := "money"

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


func on_ship_destroyed() -> void:
	career_blocks_destroyed += GameStatistics.get_blocks_destroyed_this_run()
	_career_write_pending = false
	_write_career_to_disk()
	GameStatistics.set_blocks_run_baseline()
	return_to_prep()
