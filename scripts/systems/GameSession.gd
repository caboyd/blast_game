extends Node

## Persists run selection across Prep → planet scenes. Autoload.
const PREP_SCENE := "res://scenes/prep/Prep.tscn"

var selected_ship_id: StringName = &"scout"
## Reserved: slot index → turret type id; empty = no pre-mounted turrets from Prep.
var mounted_turrets: Array[Dictionary] = []
## Default when Prep calls `go_to_planet(GameSession.next_planet_scene)`.
var next_planet_scene: String = "res://scenes/planets/Planet1.tscn"


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
