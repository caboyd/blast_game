extends Node

@onready var target_conveyor: TargetConveyor = %TargetConveyor


func _ready() -> void:
	# Step-1 scaffold: keep this minimal and stable.
	target_conveyor.ensure_targets_spawned()
