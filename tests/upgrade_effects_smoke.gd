extends Node

const MiningVesselScene := preload("res://scenes/ships/MiningVessel.tscn")


func _ready() -> void:
	var vessel := MiningVesselScene.instantiate() as MiningVessel
	add_child(vessel)
	await get_tree().process_frame

	UpgradeBus._levels.clear()
	_assert_eq(UpgradeBus.get_max_level(&"fuel_tank"), 1000, "fuel tank max level")

	UpgradeBus._levels[&"visibility_range"] = 3
	UpgradeBus._levels[&"vessel_speed"] = 4
	UpgradeBus._levels[&"drill_range"] = 5

	_assert_eq(vessel.get_effective_vision_radius_cells(), vessel.vision_radius_cells + 3, "vision range")
	_assert_approx(
		vessel.get_effective_move_speed_px_s(),
		vessel.move_speed_px_s + 4.0,
		"vessel speed"
	)
	_assert_approx(
		vessel.get_effective_drill_game_radius_px(),
		vessel.get_drill_game_radius_px() + 5.0,
		"drill range"
	)

	vessel.queue_free()
	get_tree().quit(0)


func _assert_eq(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		get_tree().quit(1)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		push_error("%s: expected %.3f, got %.3f" % [label, expected, actual])
		get_tree().quit(1)
