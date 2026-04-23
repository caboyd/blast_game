extends Control

@onready var _start: Button = $Margin/RootVBox/StartMission


func _ready() -> void:
	if _start:
		_start.pressed.connect(_on_start_mission_pressed)


func _on_start_mission_pressed() -> void:
	GameSession.selected_ship_id = &"scout"
	GameSession.go_to_planet(GameSession.next_planet_scene)
