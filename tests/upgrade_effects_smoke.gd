extends Node

const ScoutShipScene := preload("res://scenes/ships/Scout.tscn")
const PrepScene := preload("res://scenes/prep/Prep.tscn")
const ScoutShipData := preload("res://data/ships/scout.tres")
const ProspectorShipData := preload("res://data/ships/prospector.tres")
const _PartMovementPenaltyEffect = preload("res://scripts/data/PartMovementPenaltyEffect.gd")


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
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_chain_lightning"), "chain lightning in registry")
	_assert_true(UpgradeBus.get_max_level(&"weapon_chain_lightning") == 1, "chain lightning single level")
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_chain_lightning_range"), "chain lightning range in registry")
	_assert_true(UpgradeBus.get_max_level(&"weapon_chain_lightning_range") >= 2, "chain lightning range multi level")
	_assert_true(UpgradeBus.get_max_level(&"weapon_laser") == 1, "weapon laser single level")
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_laser"), "weapon laser in registry")
	_assert_true(UpgradeBus.get_max_level(&"weapon_bomb") == 1, "weapon bomb single level")
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_bomb"), "weapon bomb in registry")
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_bomb_range"), "weapon bomb range in registry")
	_assert_true(UpgradeBus.get_max_level(&"weapon_bomb_range") >= 2, "weapon bomb range has multiple levels")
	_assert_true(ShipDataRegistry.has_upgrade(&"block_explosive_unlock"), "block explosive unlock in registry")
	_assert_true(UpgradeBus.get_max_level(&"block_explosive_unlock") == 1, "explosive blocks single-level unlock")
	_assert_true(ShipDataRegistry.has_upgrade(&"block_explosive_chance"), "block explosive chance in registry")
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_laser_range"), "laser range upgrade in registry")
	_assert_true(UpgradeBus.get_max_level(&"weapon_laser_range") >= 2, "laser range has multiple levels")
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_missile"), "weapon missile in registry")
	_assert_true(UpgradeBus.get_max_level(&"weapon_missile") == 1, "weapon missile single level")
	_assert_true(UpgradeBus.get_max_level(&"weapon_gravity_pull") == 1, "weapon gravity pull single level")
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_gravity_pull"), "weapon gravity pull in registry")
	UpgradeBus._levels.clear()
	GameStatistics.money = 100000
	_assert_true(UpgradeBus.try_purchase_count(&"weapon_missile", 1), "weapon missile purchase succeeds")
	_assert_true(UpgradeBus.is_maxed(&"weapon_missile"), "weapon missile maxed after buy")
	_assert_true(not UpgradeBus.try_purchase_count(&"weapon_missile", 1), "weapon missile over-purchase blocked")
	_assert_true(ShipDataRegistry.has_upgrade(&"weapon_missile_range"), "weapon missile range upgrade in registry")
	_assert_true(UpgradeBus.get_max_level(&"weapon_missile_range") >= 2, "weapon missile range has multiple levels")

	UpgradeBus._levels.clear()
	GameStatistics.money = 100000
	_assert_true(UpgradeBus.try_purchase_count(&"weapon_bomb", 1), "weapon bomb purchase succeeds")
	_assert_true(UpgradeBus.is_maxed(&"weapon_bomb"), "weapon bomb maxed after buy")
	_assert_true(not UpgradeBus.try_purchase_count(&"weapon_bomb", 1), "weapon bomb over-purchase blocked")

	UpgradeBus._levels.clear()
	GameStatistics.money = 100000
	_assert_true(UpgradeBus.try_purchase_count(&"weapon_gravity_pull", 1), "weapon gravity pull purchase succeeds")
	_assert_true(UpgradeBus.is_maxed(&"weapon_gravity_pull"), "weapon gravity pull maxed after buy")
	_assert_true(not UpgradeBus.try_purchase_count(&"weapon_gravity_pull", 1), "weapon gravity pull over-purchase blocked")

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
	var prep := PrepScene.instantiate()
	add_child(prep)
	await get_tree().process_frame
	prep.set_upgrade_batch_request_for_test(5)
	_assert_nonempty_string(prep.get_shop_cost_display_for_test(&"mining_power"), "prep cost display")
	prep.set_upgrade_batch_request_for_test(-1)
	_assert_nonempty_string(prep.get_shop_cost_display_for_test(&"mining_power"), "prep max cost display")
	prep.queue_free()

	UpgradeBus._levels.clear()

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

	# Global parts: per-level effect consistency checks

	var d_t1: PartData = PartRegistry.get_part_data(&"part_drill_t1")
	_assert_true(d_t1 != null, "part_drill_t1 loads")

	var drill_max_level := PartRegistry.get_part_max_level(&"part_drill_t1")
	_assert_true(
		drill_max_level == d_t1.effect_sets_by_level.size(),
		"drill t1 max level matches effect set count"
	)
	_assert_true(drill_max_level == 2, "drill t1 has two levels")

	for lvl in range(1, drill_max_level + 1):
		var effects := d_t1.get_effects_for_level(lvl)
		_assert_true(effects.size() > 0, "drill t1 level %d has effects" % lvl)

	# ---------------- TREADS ----------------

	var treads_pd: PartData = PartRegistry.get_part_data(&"part_treads_t1")
	_assert_true(treads_pd != null, "part_treads_t1 loads")

	var treads_max_level := PartRegistry.get_part_max_level(&"part_treads_t1")

	for lvl in range(1, treads_max_level + 1):
		var effects := treads_pd.get_effects_for_level(lvl)
		_assert_true(effects.size() > 0, "treads level %d has effects" % lvl)


	# ---------------- FUEL TANK ----------------

	var fuel_pd: PartData = PartRegistry.get_part_data(&"part_fuel_tank_t1")
	_assert_true(fuel_pd != null, "part_fuel_tank_t1 loads")

	var fuel_max_level := PartRegistry.get_part_max_level(&"part_fuel_tank_t1")

	for lvl in range(1, fuel_max_level + 1):
		var effects := fuel_pd.get_effects_for_level(lvl)
		_assert_true(effects.size() > 0, "fuel tank level %d has effects" % lvl)
		
	# ---------------- CLAMP ----------------


	_assert_true(
		PartRegistry.get_part_level(&"part_fuel_tank_t0") == 1,
		"saved level beyond max clamps to derived max"
	)

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
