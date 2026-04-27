extends Control

const _STAGE_TAB_INDEX := 1

@onready var _start: Button = $Margin/RootVBox/StartMission
@onready var _career_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Progress/ProgressVBox/CareerBlocksLabel"
@onready var _money_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Progress/ProgressVBox/MoneyLabel"
@onready var _depth_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Progress/ProgressVBox/DepthLabel"
@onready var _ship_fuel_label: Label = $"Margin/RootVBox/Row/PreviewCol/StatsPanel/StatsMargin/StatsOuter/StatsTabs/Ship/ShipVBox/ShipFuelLabel"
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
@onready var _shop_mining_tier: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/MiningRow/MiningBuyRow/MiningTierStack/MiningTierLabel
@onready var _shop_mining_tier_bar: ProgressBar = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/MiningRow/MiningBuyRow/MiningTierStack/MiningTierProgress
@onready var _shop_mining_btn: Button = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/MiningRow/MiningBuyRow/MiningBtn
@onready var _shop_fuel_tier: Label = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/FuelRow/FuelBuyRow/FuelTierStack/FuelTierLabel
@onready var _shop_fuel_tier_bar: ProgressBar = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/FuelRow/FuelBuyRow/FuelTierStack/FuelTierProgress
@onready var _shop_fuel_btn: Button = $Margin/RootVBox/Row/ShopPanel/ShopMargin/ShopInner/FuelRow/FuelBuyRow/FuelBtn


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
	_refresh_all()


func _on_vessel_tab_changed(tab: int) -> void:
	if tab == _STAGE_TAB_INDEX:
		_refresh_stage_tab()


func _on_debug_reset_pressed() -> void:
	GameSession.reset_all_progress()
	_refresh_all()


func _on_stats_changed() -> void:
	_refresh_all()


func _on_fuel_changed(_current: float, _max_fuel: float) -> void:
	_refresh_all()


func _on_upgrade_purchased(_id: StringName, _new_level: int) -> void:
	_refresh_all()


func _on_shop_purchase(upgrade_id: StringName) -> void:
	UpgradeBus.try_purchase(upgrade_id)


func _refresh_all() -> void:
	_refresh_progress()
	_refresh_ship_stats()
	_refresh_shop()
	if _vessel_tabs and _vessel_tabs.current_tab == _STAGE_TAB_INDEX:
		_refresh_stage_tab()


func _refresh_stage_tab() -> void:
	if _stage_type_tree == null or _stage_summary == null:
		return
	_stage_summary.text = "Stage: %s" % String(&"planet1")
	_stage_type_tree.clear()
	var root: TreeItem = _stage_type_tree.create_item()
	for spec in MiningGrid.get_stage_block_type_rows():
		var type_id: int = int(spec["type_id"])
		if type_id < 0 or type_id >= MiningGrid.TYPE_MAX_HP.size():
			continue
		var it: TreeItem = _stage_type_tree.create_item(root)
		it.set_text(0, str(spec.get("label", "?")))
		it.set_text(1, "%d" % int(MiningGrid.TYPE_MAX_HP[type_id]))
		it.set_text(2, "%d" % int(MiningGrid.TYPE_MONEY[type_id]))


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
	if _mining_radius_label:
		var half_cell: float = MiningGrid.CELL_SIZE_PX * 0.5
		var world_r: float = _vessel.get_drill_game_radius_px()
		var r_rel: float = world_r / half_cell if half_cell > 0.0 else 0.0
		_mining_radius_label.text = "Mining Radius: %.2f" % r_rel
	if _move_speed_label:
		_move_speed_label.text = "Move Speed: %d" % int(roundf(_vessel.move_speed_px_s))
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
	_set_shop_tier_label(&"mining_power", _shop_mining_tier)
	_set_shop_tier_label(&"fuel_tank", _shop_fuel_tier)
	_set_shop_tier_progress(&"mining_power", _shop_mining_tier_bar)
	_set_shop_tier_progress(&"fuel_tank", _shop_fuel_tier_bar)
	if _shop_mining_btn:
		_set_shop_button(&"mining_power", _shop_mining_btn)
	if _shop_fuel_btn:
		_set_shop_button(&"fuel_tank", _shop_fuel_btn)


func _set_shop_tier_label(upgrade_id: StringName, label: Label) -> void:
	if label == null:
		return
	if not UpgradeBus.DEFS.has(upgrade_id):
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
	if not UpgradeBus.DEFS.has(upgrade_id):
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
	if not UpgradeBus.DEFS.has(upgrade_id):
		btn.text = "—"
		btn.disabled = true
		btn.modulate = Color.WHITE
		return
	if UpgradeBus.is_maxed(upgrade_id):
		btn.text = "—"
		btn.disabled = true
		btn.modulate = Color.WHITE
		return
	var cost: int = UpgradeBus.get_cost(upgrade_id)
	var purchasable: bool = UpgradeBus.can_purchase(upgrade_id)
	btn.text = "%d $" % cost
	btn.disabled = not purchasable
	btn.modulate = (
		Color(0.75, 0.75, 0.8, 1.0)
		if (UpgradeBus.can_upgrade(upgrade_id) and not UpgradeBus.can_afford(upgrade_id))
		else Color.WHITE
	)


func _on_start_mission_pressed() -> void:
	GameSession.selected_ship_id = &"scout"
	GameSession.begin_run()
	GameSession.go_to_planet(GameSession.next_planet_scene)
