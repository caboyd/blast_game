extends Node

const MiningVesselScene := preload("res://scenes/ships/MiningVessel.tscn")
const BottomHUDScene := preload("res://scenes/ui/BottomHUD.tscn")
const PrepScene := preload("res://scenes/prep/Prep.tscn")


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
	_assert_approx(
		vessel.get_debug_drill_draw_radius_px(),
		vessel.get_effective_drill_game_radius_px(),
		"debug drill radius"
	)

	UpgradeBus._levels.clear()
	GameStatistics.money = 1000
	_assert_eq(UpgradeBus.get_purchase_count_for_request(&"mining_power", 5), 5, "fixed batch count")
	_assert_eq(UpgradeBus.get_purchase_cost_for_count(&"mining_power", 3), 33, "three-level batch cost")
	_assert_eq(UpgradeBus.get_purchase_count_for_request(&"mining_power", -1), 10, "max batch count")
	_assert_eq(UpgradeBus.get_purchase_cost_for_count(&"mining_power", 10), 159, "max batch cost")
	_assert_true(UpgradeBus.try_purchase_count(&"mining_power", 5), "five-level purchase succeeds")
	_assert_eq(UpgradeBus.get_level(&"mining_power"), 5, "five-level purchase level")
	_assert_eq(GameStatistics.money, 939, "five-level purchase money")

	UpgradeBus._levels.clear()
	GameStatistics.money = 1000
	var hud := BottomHUDScene.instantiate() as BottomHUD
	add_child(hud)
	await get_tree().process_frame
	hud.set_upgrade_batch_request_for_test(5)
	_assert_eq_string(hud.get_upgrade_cost_display_for_test(&"mining_power"), "5x $61", "5x HUD cost")
	hud.set_upgrade_batch_request_for_test(-1)
	_assert_eq_string(hud.get_upgrade_cost_display_for_test(&"mining_power"), "10x $159", "max HUD cost")
	hud.queue_free()

	UpgradeBus._levels.clear()
	GameStatistics.money = 1000
	var prep := PrepScene.instantiate()
	add_child(prep)
	await get_tree().process_frame
	prep.set_upgrade_batch_request_for_test(5)
	_assert_eq_string(prep.get_shop_cost_display_for_test(&"mining_power"), "5x $61", "5x prep cost")
	prep.set_upgrade_batch_request_for_test(-1)
	_assert_eq_string(prep.get_shop_cost_display_for_test(&"mining_power"), "10x $159", "max prep cost")
	prep.queue_free()

	vessel.queue_free()
	get_tree().quit(0)


func _assert_eq(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		get_tree().quit(1)


func _assert_eq_string(actual: String, expected: String, label: String) -> void:
	if actual != expected:
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		get_tree().quit(1)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		push_error("%s: expected %.3f, got %.3f" % [label, expected, actual])
		get_tree().quit(1)


func _assert_true(actual: bool, label: String) -> void:
	if not actual:
		push_error("%s: expected true" % label)
		get_tree().quit(1)
