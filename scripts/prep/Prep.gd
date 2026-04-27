extends Control

const _STAGE_TAB_INDEX := 1
const _STAGE_BLOCK_CATALOG_ID: StringName = &"planet1"
const _UNKNOWN_BLOCK := "???"
const UPGRADE_BATCH_REQUESTS: Array[int] = [1, 5, 25, 100, -1]

@onready var _start: Button = $Margin/RootVBox/StartMission
@onready var _career_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Progress/ProgressVBox/CareerBlocksLabel"
@onready var _money_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Progress/ProgressVBox/MoneyLabel"
@onready var _depth_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Progress/ProgressVBox/DepthLabel"
@onready var _ship_fuel_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Ship/ShipVBox/ShipFuelLabel"
@onready var _visibility_range_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Ship/ShipVBox/VisibilityRangeLabel"
@onready var _mining_radius_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Ship/ShipVBox/MiningRadiusLabel"
@onready var _move_speed_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Ship/ShipVBox/MoveSpeedLabel"
@onready var _mining_power_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Ship/ShipVBox/MiningPowerLabel"
@onready var _mining_interval_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Ship/ShipVBox/MiningIntervalLabel"
@onready var _mining_power_per_sec_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Ship/ShipVBox/MiningPowerPerSecLabel"
@onready var _vessel: MiningVessel = $Margin/RootVBox/Row/PreviewCol/VesselColumn/VesselTabs/Preview/SubViewportContainer/SubViewport/World/MiningVessel
@onready var _vessel_tabs: TabContainer = $Margin/RootVBox/Row/PreviewCol/VesselColumn/VesselTabs
@onready var _stage_summary: Label = $Margin/RootVBox/Row/PreviewCol/VesselColumn/VesselTabs/Stage/StageScroll/StageVBox/StageSummaryLabel
@onready var _stage_type_tree: Tree = $Margin/RootVBox/Row/PreviewCol/VesselColumn/VesselTabs/Stage/StageScroll/StageVBox/StageTypeTree
@onready var _debug_reset: Button = $Margin/RootVBox/DebugRow/DebugResetProgress
@onready var _stats_tabs: TabContainer = $Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs
@onready var _shop_money_label: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/ShopMoneyRow/ShopMoneyPanel/ShopMoneyLabel
@onready var _shop_batch_btn: Button = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/ShopBatchRow/ShopBatchBtn
@onready var _shop_mining_tier: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/MiningRow/MiningBuyRow/MiningTierStack/MiningTierLabel
@onready var _shop_mining_tier_bar: ProgressBar = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/MiningRow/MiningBuyRow/MiningTierStack/MiningTierProgress
@onready var _shop_mining_btn: Button = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/MiningRow/MiningBuyRow/MiningBtn
@onready var _shop_fuel_tier: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/FuelRow/FuelBuyRow/FuelTierStack/FuelTierLabel
@onready var _shop_fuel_tier_bar: ProgressBar = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/FuelRow/FuelBuyRow/FuelTierStack/FuelTierProgress
@onready var _shop_fuel_btn: Button = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/FuelRow/FuelBuyRow/FuelBtn
@onready var _shop_visibility_tier: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/VisibilityRow/VisibilityBuyRow/VisibilityTierStack/VisibilityTierLabel
@onready var _shop_visibility_tier_bar: ProgressBar = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/VisibilityRow/VisibilityBuyRow/VisibilityTierStack/VisibilityTierProgress
@onready var _shop_visibility_btn: Button = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/VisibilityRow/VisibilityBuyRow/VisibilityBtn
@onready var _shop_speed_tier: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/SpeedRow/SpeedBuyRow/SpeedTierStack/SpeedTierLabel
@onready var _shop_speed_tier_bar: ProgressBar = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/SpeedRow/SpeedBuyRow/SpeedTierStack/SpeedTierProgress
@onready var _shop_speed_btn: Button = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/SpeedRow/SpeedBuyRow/SpeedBtn
@onready var _shop_drill_range_tier: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/DrillRangeRow/DrillRangeBuyRow/DrillRangeTierStack/DrillRangeTierLabel
@onready var _shop_drill_range_tier_bar: ProgressBar = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/DrillRangeRow/DrillRangeBuyRow/DrillRangeTierStack/DrillRangeTierProgress
@onready var _shop_drill_range_btn: Button = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/DrillRangeRow/DrillRangeBuyRow/DrillRangeBtn
@onready var _shop_mining_info: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/MiningRow/MiningInfo
@onready var _shop_fuel_info: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/FuelRow/FuelInfo
@onready var _shop_visibility_info: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/VisibilityRow/VisibilityInfo
@onready var _shop_speed_info: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/SpeedRow/SpeedInfo
@onready var _shop_drill_info: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/DrillRangeRow/DrillRangeInfo

var _upgrade_batch_index: int = 0


func _ready() -> void:
	_stats_tabs.set_tab_title(0, "Ship")
	_stats_tabs.set_tab_title(1, "Progress")
	if _vessel_tabs:
		_vessel_tabs.set_tab_title(0, "Vessel")
		_vessel_tabs.set_tab_title(1, "Stage")
		_vessel_tabs.tab_changed.connect(_on_vessel_tab_changed)
	if _stage_type_tree:
		_stage_type_tree.set_column_title(0, "Block")
		_stage_type_tree.set_column_title(1, "Max HP")
		_stage_type_tree.set_column_title(2, "$ (destroy)")
	if _start:
		_start.pressed.connect(_on_start_mission_pressed)
	if _debug_reset:
		_debug_reset.pressed.connect(_on_debug_reset_pressed)
	if _shop_batch_btn:
		_shop_batch_btn.pressed.connect(_on_shop_batch_btn_pressed)
	if not GameStatistics.stats_changed.is_connected(_on_stats_changed):
		GameStatistics.stats_changed.connect(_on_stats_changed)
	if not GameStatistics.fuel_changed.is_connected(_on_fuel_changed):
		GameStatistics.fuel_changed.connect(_on_fuel_changed)
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	if _shop_mining_btn:
		_shop_mining_btn.pressed.connect(func() -> void: _on_shop_purchase(&"mining_power"))
	if _shop_fuel_btn:
		_shop_fuel_btn.pressed.connect(func() -> void: _on_shop_purchase(&"fuel_tank"))
	if _shop_visibility_btn:
		_shop_visibility_btn.pressed.connect(func() -> void: _on_shop_purchase(&"visibility_range"))
	if _shop_speed_btn:
		_shop_speed_btn.pressed.connect(func() -> void: _on_shop_purchase(&"vessel_speed"))
	if _shop_drill_range_btn:
		_shop_drill_range_btn.pressed.connect(func() -> void: _on_shop_purchase(&"drill_range"))
	_refresh_all()


func _on_vessel_tab_changed(tab: int) -> void:
	if tab == _STAGE_TAB_INDEX:
		_refresh_stage_tab()


func _on_debug_reset_pressed() -> void:
	GameSession.reset_all_progress()
	_refresh_all()


func _on_shop_batch_btn_pressed() -> void:
	_upgrade_batch_index = (_upgrade_batch_index + 1) % UPGRADE_BATCH_REQUESTS.size()
	_refresh_shop_batch_button()
	_refresh_shop()


func _on_stats_changed() -> void:
	_refresh_all()


func _on_fuel_changed(_current: float, _max_fuel: float) -> void:
	_refresh_all()


func _on_upgrade_purchased(_id: StringName, _new_level: int) -> void:
	_refresh_all()


func _on_shop_purchase(upgrade_id: StringName) -> void:
	UpgradeBus.try_purchase_count(upgrade_id, _current_upgrade_batch_request())


func _refresh_all() -> void:
	_refresh_progress()
	_refresh_ship_stats()
	_refresh_shop()
	if _vessel_tabs and _vessel_tabs.current_tab == _STAGE_TAB_INDEX:
		_refresh_stage_tab()


func _refresh_stage_tab() -> void:
	if _stage_type_tree == null or _stage_summary == null:
		return
	_stage_summary.text = "Stage: %s" % String(_STAGE_BLOCK_CATALOG_ID)
	_stage_type_tree.clear()
	var root: TreeItem = _stage_type_tree.create_item()
	for spec in MiningGrid.get_stage_block_type_rows():
		var type_id: int = int(spec["type_id"])
		if type_id < 0 or type_id >= MiningGrid.TYPE_MAX_HP.size():
			continue
		var it: TreeItem = _stage_type_tree.create_item(root)
		if GameSession.is_block_type_discovered(_STAGE_BLOCK_CATALOG_ID, type_id):
			it.set_text(0, str(spec.get("label", "?")))
			it.set_text(1, "%d" % int(MiningGrid.TYPE_MAX_HP[type_id]))
			it.set_text(2, "%d" % int(MiningGrid.TYPE_MONEY[type_id]))
		else:
			it.set_text(0, _UNKNOWN_BLOCK)
			it.set_text(1, _UNKNOWN_BLOCK)
			it.set_text(2, _UNKNOWN_BLOCK)


func _refresh_progress() -> void:
	if _career_label:
		_career_label.text = "Blocks destroyed (all time): %d" % GameSession.career_blocks_destroyed
	if _money_label:
		_money_label.text = "Money: %d" % GameStatistics.money
	if _shop_money_label:
		_shop_money_label.text = "$ %d" % GameStatistics.money
	if _depth_label:
		_depth_label.text = "Furthest depth: %d cells" % GameStatistics.furthest_depth_cells


func _refresh_ship_stats() -> void:
	if _ship_fuel_label:
		_ship_fuel_label.text = "Fuel: %d / %d" % [int(floorf(GameStatistics.fuel)), int(floorf(GameStatistics.fuel_max))]
	if _vessel == null:
		return
	if _visibility_range_label:
		_visibility_range_label.text = "Visibility Range: %d cells" % _vessel.get_effective_vision_radius_cells()
	if _mining_radius_label:
		var half_cell: float = MiningGrid.CELL_SIZE_PX * 0.5
		var world_r: float = _vessel.get_effective_drill_game_radius_px()
		var r_rel: float = world_r / half_cell if half_cell > 0.0 else 0.0
		_mining_radius_label.text = "Mining Radius: %.2f" % r_rel
	if _move_speed_label:
		_move_speed_label.text = "Move Speed: %d" % int(roundf(_vessel.get_effective_move_speed_px_s()))
	if _mining_power_label:
		_mining_power_label.text = "Mining Power: %.1f" % _vessel.get_effective_mine_damage_per_tick()
	if _mining_interval_label:
		_mining_interval_label.text = "Mining Interval: %.1f" % _vessel.mine_interval_s
	if _mining_power_per_sec_label:
		var dt: float = _vessel.mine_interval_s
		if dt > 0.0:
			var dps: float = _vessel.get_effective_mine_damage_per_tick() / dt
			_mining_power_per_sec_label.text = "Mining Power / s: %.1f" % dps
		else:
			_mining_power_per_sec_label.text = "Mining Power / s: —"


func _refresh_shop() -> void:
	_refresh_shop_batch_button()
	_set_shop_tier_label(&"mining_power", _shop_mining_tier)
	_set_shop_tier_label(&"fuel_tank", _shop_fuel_tier)
	_set_shop_tier_label(&"visibility_range", _shop_visibility_tier)
	_set_shop_tier_label(&"vessel_speed", _shop_speed_tier)
	_set_shop_tier_label(&"drill_range", _shop_drill_range_tier)
	_set_shop_tier_progress(&"mining_power", _shop_mining_tier_bar)
	_set_shop_tier_progress(&"fuel_tank", _shop_fuel_tier_bar)
	_set_shop_tier_progress(&"visibility_range", _shop_visibility_tier_bar)
	_set_shop_tier_progress(&"vessel_speed", _shop_speed_tier_bar)
	_set_shop_tier_progress(&"drill_range", _shop_drill_range_tier_bar)
	if _shop_mining_btn:
		_set_shop_button(&"mining_power", _shop_mining_btn)
	if _shop_fuel_btn:
		_set_shop_button(&"fuel_tank", _shop_fuel_btn)
	if _shop_visibility_btn:
		_set_shop_button(&"visibility_range", _shop_visibility_btn)
	if _shop_speed_btn:
		_set_shop_button(&"vessel_speed", _shop_speed_btn)
	if _shop_drill_range_btn:
		_set_shop_button(&"drill_range", _shop_drill_range_btn)
	_set_shop_info_label(&"mining_power", _shop_mining_info)
	_set_shop_info_label(&"fuel_tank", _shop_fuel_info)
	_set_shop_info_label(&"visibility_range", _shop_visibility_info)
	_set_shop_info_label(&"vessel_speed", _shop_speed_info)
	_set_shop_info_label(&"drill_range", _shop_drill_info)


func _set_shop_info_label(upgrade_id: StringName, label: Label) -> void:
	if label == null:
		return
	if not UpgradeBus.has_def(upgrade_id) or not VesselDataRegistry.has_upgrade(upgrade_id):
		label.text = ""
		return
	if UpgradeBus.is_maxed(upgrade_id):
		label.text = "Fully upgraded"
		return
	var req: int = _current_upgrade_batch_request()
	var n_afford: int = UpgradeBus.get_purchase_count_for_request(
		upgrade_id, req if req >= 0 else -1
	)
	var next_teaser: bool = n_afford <= 0
	var n_disp: int = 1 if next_teaser else n_afford
	var deltas: Array = VesselDataRegistry.preview_upgrade_stat_deltas(upgrade_id, n_disp)
	var parts: Array[String] = []
	for e in deltas:
		var line: String = _shop_format_stat_delta_line(e, upgrade_id, n_disp)
		if not line.is_empty():
			parts.append(line)
	if parts.is_empty():
		label.text = ""
		return
	var prefix: String = ""
	if next_teaser:
		prefix = "Next: "
	elif n_disp > 1:
		prefix = "×%d: " % n_disp
	var body: String = " · ".join(parts)
	label.text = prefix + body


func _shop_drill_radius_display_total(upgrade_id: StringName, drill_level: int) -> float:
	var h: float = MiningGrid.CELL_SIZE_PX * 0.5
	var base: float = _vessel.get_drill_game_radius_px()
	var bonus: float = VesselDataRegistry.preview_effective_stat(
		&"drill_range_bonus_game_px", upgrade_id, drill_level
	)
	return (base + bonus) / h if h > 0.0 else 0.0


func _shop_format_stat_delta_line(e: Dictionary, upgrade_id: StringName, n_disp: int) -> String:
	var st: StringName = e["stat"] as StringName
	var delta: float = float(e["delta"])
	var after: float = float(e["after"])
	if st == &"drill_range_bonus_game_px":
		if _vessel == null:
			return ""
		var cur: int = UpgradeBus.get_level(upgrade_id)
		var before_u: float = _shop_drill_radius_display_total(upgrade_id, cur)
		var after_u: float = _shop_drill_radius_display_total(upgrade_id, cur + n_disp)
		delta = after_u - before_u
		after = after_u
	return _shop_format_line_for_stat(st, delta, after)


func _shop_format_line_for_stat(st: StringName, delta: float, after: float) -> String:
	if absf(delta) < 1e-5:
		return ""
	match String(st):
		"mine_damage_per_tick":
			return "+%.2f dmg/tick (→ %.2f)" % [delta, after]
		"fuel_max":
			return "+%d fuel max (→ %d)" % [int(round(delta)), int(round(after))]
		"vision_radius_cells":
			return "+%d vision cells (→ %d)" % [
				int(round(delta)),
				maxi(1, int(round(after))),
			]
		"move_speed_px_s":
			return "+%d speed (→ %d)" % [int(round(delta)), int(round(after))]
		"drill_range_bonus_game_px":
			return "+%.2f mining radius (→ %.2f)" % [delta, after]
		_:
			return "+%.2f (→ %.2f)" % [delta, after]


func _set_shop_tier_label(upgrade_id: StringName, label: Label) -> void:
	if label == null:
		return
	if not UpgradeBus.has_def(upgrade_id):
		label.text = ""
		return
	var cap: int = UpgradeBus.get_max_level(upgrade_id)
	var cur: int = UpgradeBus.get_level(upgrade_id)
	if cap < 0:
		label.text = "%d" % cur
		return
	label.text = "%d / %d" % [mini(cur, cap), cap]


func _set_shop_tier_progress(upgrade_id: StringName, bar: ProgressBar) -> void:
	if bar == null:
		return
	if not UpgradeBus.has_def(upgrade_id):
		bar.visible = false
		return
	var cap: int = UpgradeBus.get_max_level(upgrade_id)
	if cap < 0:
		bar.visible = false
		return
	var cur: int = UpgradeBus.get_level(upgrade_id)
	bar.visible = true
	bar.min_value = 0.0
	bar.max_value = float(max(1, cap))
	bar.value = float(mini(maxi(cur, 0), cap))


func _set_shop_button(upgrade_id: StringName, btn: Button) -> void:
	if not UpgradeBus.has_def(upgrade_id):
		btn.text = "—"
		btn.disabled = true
		btn.modulate = Color.WHITE
		return
	if UpgradeBus.is_maxed(upgrade_id):
		btn.text = "—"
		btn.disabled = true
		btn.modulate = Color.WHITE
		return
	var purchasable: bool = UpgradeBus.can_upgrade(upgrade_id) and _can_purchase_batch(upgrade_id)
	btn.text = _shop_cost_display_for(upgrade_id)
	btn.disabled = not purchasable
	btn.modulate = (
		Color(0.75, 0.75, 0.8, 1.0)
		if (UpgradeBus.can_upgrade(upgrade_id) and not _can_afford_batch(upgrade_id))
		else Color.WHITE
	)


func _shop_cost_display_for(upgrade_id: StringName) -> String:
	if not UpgradeBus.can_upgrade(upgrade_id):
		return "—"
	var requested_count: int = _current_upgrade_batch_request()
	if requested_count < 0:
		var max_count: int = UpgradeBus.get_purchase_count_for_request(upgrade_id, requested_count)
		return "%dx $%d" % [max_count, UpgradeBus.get_purchase_cost_for_count(upgrade_id, max_count)]
	if not _has_room_for_batch(upgrade_id, requested_count):
		return "%dx —" % requested_count
	return "%dx $%d" % [
		requested_count, UpgradeBus.get_purchase_cost_for_count(upgrade_id, requested_count)
	]


func _current_upgrade_batch_request() -> int:
	return UPGRADE_BATCH_REQUESTS[_upgrade_batch_index]


func _current_upgrade_batch_label() -> String:
	var requested_count: int = _current_upgrade_batch_request()
	return "MAX" if requested_count < 0 else "%dx" % requested_count


func _refresh_shop_batch_button() -> void:
	if _shop_batch_btn:
		_shop_batch_btn.text = "Buy: %s" % _current_upgrade_batch_label()


func _has_room_for_batch(upgrade_id: StringName, requested_count: int) -> bool:
	if requested_count <= 0:
		return false
	var cap: int = UpgradeBus.get_max_level(upgrade_id)
	if cap < 0:
		return true
	return UpgradeBus.get_level(upgrade_id) + requested_count <= cap


func _can_purchase_batch(upgrade_id: StringName) -> bool:
	var requested_count: int = _current_upgrade_batch_request()
	if requested_count < 0:
		return UpgradeBus.get_purchase_count_for_request(upgrade_id, requested_count) > 0
	return _has_room_for_batch(upgrade_id, requested_count)


func _can_afford_batch(upgrade_id: StringName) -> bool:
	var requested_count: int = _current_upgrade_batch_request()
	if requested_count < 0:
		return UpgradeBus.get_purchase_count_for_request(upgrade_id, requested_count) > 0
	if not _has_room_for_batch(upgrade_id, requested_count):
		return false
	return GameStatistics.money >= UpgradeBus.get_purchase_cost_for_count(upgrade_id, requested_count)


func set_upgrade_batch_request_for_test(requested_count: int) -> void:
	var idx := UPGRADE_BATCH_REQUESTS.find(requested_count)
	if idx >= 0:
		_upgrade_batch_index = idx
		_refresh_shop_batch_button()


func get_shop_cost_display_for_test(upgrade_id: StringName) -> String:
	return _shop_cost_display_for(upgrade_id)


func _on_start_mission_pressed() -> void:
	GameSession.selected_ship_id = &"scout"
	GameSession.begin_run()
	GameSession.go_to_planet(GameSession.next_planet_scene)
