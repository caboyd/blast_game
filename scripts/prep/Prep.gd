extends Control

@onready var _start: Button = $Margin/RootVBox/StartMission
@onready var _career_label: Label = $Margin/RootVBox/CareerBlocksLabel
@onready var _money_label: Label = $Margin/RootVBox/MoneyLabel
@onready var _debug_reset: Button = $Margin/RootVBox/DebugRow/DebugResetProgress


func _ready() -> void:
	if _start:
		_start.pressed.connect(_on_start_mission_pressed)
	if _debug_reset:
		_debug_reset.pressed.connect(_on_debug_reset_pressed)
	if not GameStatistics.stats_changed.is_connected(_on_stats_changed):
		GameStatistics.stats_changed.connect(_on_stats_changed)
	_refresh_career_label()


func _on_debug_reset_pressed() -> void:
	GameSession.reset_all_progress()
	_refresh_career_label()


func _on_stats_changed() -> void:
	_refresh_career_label()


func _refresh_career_label() -> void:
	if _career_label:
		_career_label.text = "Blocks destroyed (all time): %d" % GameSession.career_blocks_destroyed
	if _money_label:
		_money_label.text = "Money: %d" % GameStatistics.money


func _on_start_mission_pressed() -> void:
	GameSession.selected_ship_id = &"scout"
	GameSession.begin_run()
	GameSession.go_to_planet(GameSession.next_planet_scene)
