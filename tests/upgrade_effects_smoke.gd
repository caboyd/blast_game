extends Node

const ScoutShipScene := preload("res://scenes/ships/Scout.tscn")
const BottomHUDScene := preload("res://scenes/ui/BottomHUD.tscn")
const PrepScene := preload("res://scenes/prep/Prep.tscn")
const ScoutShipData := preload("res://data/ships/scout.tres")
const ProspectorShipData := preload("res://data/ships/prospector.tres")


func _ready() -> void:
	var scout: Resource = ScoutShipData as Resource
	_assert_true(scout != null, "scout ship resource loads")
	_assert_nonempty_id(scout.get("id"), "scout id")
	_assert_true(is_finite(float(scout.get("move_speed_px_s"))), "scout move speed")
	var vsp: Resource = null
	for u in scout.get("upgrades") as Array:
		if u != null and u.get("id") == &"scout_speed":
			vsp = u
			break
	_assert_true(vsp != null, "scout_speed upgrade exists")
	_assert_true(int(vsp.get("base_cost")) > 0, "scout_speed base cost")
	var vfx: Array = vsp.get("effects") as Array
	_assert_true(vfx.size() > 0, "scout_speed has effects")
	_assert_true(vfx[0].get("value") != null, "scout_speed effect value")

	var ship := ScoutShipScene.instantiate() as Scout
	add_child(ship)
	await get_tree().process_frame

	UpgradeBus._levels.clear()
	_assert_true(UpgradeBus.get_max_level(&"fuel_tank") > 0, "fuel tank max level")

	UpgradeBus._levels[&"visibility_range"] = 3
	UpgradeBus._levels[&"ship_speed"] = 4
	UpgradeBus._levels[&"drill_range"] = 5

	_assert_true(ship.get_effective_vision_radius_cells() > 0, "vision range")
	_assert_true(is_finite(ship.get_effective_move_speed_px_s()), "ship speed")
	_assert_true(is_finite(ship.get_effective_drill_game_radius_px()), "drill range")
	_assert_true(
		is_finite(ship.get_debug_drill_draw_radius_px()),
		"debug drill radius"
	)

	UpgradeBus._levels.clear()
	GameStatistics.money = 100000
	_assert_true(UpgradeBus.try_purchase_count(&"mining_power", 1), "mining purchase succeeds")
	_assert_true(UpgradeBus.get_level(&"mining_power") >= 1, "mining level after purchase")

	UpgradeBus._levels.clear()
	GameStatistics.money = 100000
	var hud := BottomHUDScene.instantiate() as BottomHUD
	add_child(hud)
	await get_tree().process_frame
	hud.set_upgrade_batch_request_for_test(5)
	_assert_nonempty_string(hud.get_upgrade_cost_display_for_test(&"mining_power"), "HUD cost display")
	hud.set_upgrade_batch_request_for_test(-1)
	_assert_nonempty_string(hud.get_upgrade_cost_display_for_test(&"mining_power"), "HUD max cost display")
	hud.queue_free()

	UpgradeBus._levels.clear()
	GameStatistics.money = 100000
	var prep := PrepScene.instantiate()
	add_child(prep)
	await get_tree().process_frame
	prep.set_upgrade_batch_request_for_test(5)
	_assert_nonempty_string(prep.get_shop_cost_display_for_test(&"mining_power"), "prep cost display")
	prep.set_upgrade_batch_request_for_test(-1)
	_assert_nonempty_string(prep.get_shop_cost_display_for_test(&"mining_power"), "prep max cost display")
	prep.queue_free()

	ship.queue_free()

	var prospector: Resource = ProspectorShipData as Resource
	_assert_true(prospector != null, "prospector resource loads")
	_assert_nonempty_id(prospector.get("id"), "prospector id")
	_assert_true(is_finite(float(prospector.get("fuel_drain_per_second"))), "prospector fuel drain")
	GameSession.selected_ship_id = &"scout"
	ShipDataRegistry.reload_active()
	_assert_true(not ShipDataRegistry.is_ship_unlocked(&"prospector"), "prospector locked before scout max")
	for u in (ScoutShipData as Resource).get("upgrades") as Array:
		if u != null:
			UpgradeBus._levels[u.get("id") as StringName] = int(u.get("max_level"))
	_assert_true(ShipDataRegistry.is_ship_unlocked(&"prospector"), "prospector unlocked when scout maxed")

	GameSession.selected_ship_id = &"scout"
	ShipDataRegistry.reload_active()
	UpgradeBus._levels.clear()
	UpgradeBus._levels[&"mining_power"] = 3
	UpgradeBus._levels[&"prospector_double_money"] = 5
	var ship2 := ScoutShipScene.instantiate() as Scout
	add_child(ship2)
	await get_tree().process_frame
	_assert_true(is_finite(ship2.get_effective_mine_damage_per_tick()), "mine damage scout selected")
	GameSession.selected_ship_id = &"prospector"
	ShipDataRegistry.reload_active()
	var ship3 := ScoutShipScene.instantiate() as Scout
	add_child(ship3)
	await get_tree().process_frame
	_assert_true(is_finite(ship3.get_effective_mine_damage_per_tick()), "mine damage prospector selected")
	ship2.queue_free()
	ship3.queue_free()

	UpgradeBus._levels.clear()
	get_tree().quit(0)


func _assert_nonempty_string(s: String, label: String) -> void:
	if s.is_empty():
		push_error("%s: expected non-empty string" % label)
		get_tree().quit(1)


func _assert_nonempty_id(id, label: String) -> void:
	if id == null or String(id).is_empty():
		push_error("%s: expected id" % label)
		get_tree().quit(1)


func _assert_true(actual: bool, label: String) -> void:
	if not actual:
		push_error("%s: expected true" % label)
		get_tree().quit(1)
