extends Node

const _Self := preload("res://scripts/bootstrap/Bootstrap.gd")

## Loads `Prep` after a single ordered init chain (registries → stats baseline → career). Use as main scene;
## Prep also calls `ensure_initialized()` when opened directly from the editor or tests.

func _ready() -> void:
	_Self.ensure_initialized()
	var err := get_tree().change_scene_to_file(GameSession.PREP_SCENE)
	if err != OK:
		push_error("Bootstrap failed to load Prep: %s" % error_string(err))


static func ensure_initialized() -> void:
	if GameSession.initialized:
		return
	PartRegistry.init()
	ShipDataRegistry.init()
	GameStatistics.init()
	GameSession.init()
