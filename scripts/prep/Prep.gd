extends Control

const _Bootstrap := preload("res://scripts/bootstrap/Bootstrap.gd")
const _PREP_PART_TOOLTIP_SCENE := preload("res://scenes/prep/prep_part_hover_tooltip.tscn")



const PREP_STAGE_CHOICES: Array[Dictionary] = [
	{"id": &"planet1", "label": "Planet 1"},
	{"id": &"planet2", "label": "Planet 2"},
]


const _STAGE_TAB_INDEX := 1
const _UNKNOWN_BLOCK := "???"
const UPGRADE_BATCH_REQUESTS: Array[int] = [1, 5, 25, 100, -1]
const _PREVIEW_POS := Vector2(200, 180)
const _PREVIEW_SCALE := Vector2(8, 8)
## Disabled placeholder slots to stress-test the ship picker row (not real ships).
const _DUMMY_SHIP_STUB_COUNT := 10
const _STUB_SHIP_PREFIX := "_prep_stub_"
const _SHIP_PICK_SCROLL_STEP_PX := 140

@export_group("Part Overlay")
@export var prep_parts_overlay_margins := Vector4(16.0, 14.0, 16.0, 14.0)
@export var prep_parts_overlay_height: float = 80.0
@export var prep_part_chip_min_size := Vector2(150.0, 64.0)
@export var prep_part_chip_spacing: int = 10
@export var prep_part_icon_size := Vector2(42.0, 42.0)
@export var prep_part_icon_scale: float = 3.0
@export var prep_part_icon_offset := Vector2.ZERO
@export var prep_part_icon_template: PackedScene
@export var prep_part_show_type_label: bool = true

@onready var _start: Button = %PrepStartMissionBtn
@onready var _career_label: Label = %PrepCareerBlocksLabel
@onready var _money_label: Label = %PrepProgressMoneyLabel
@onready var _depth_label: Label = %PrepFurthestDepthLabel
@onready var _ship_fuel_label: Label = %PrepShipFuelLabel
@onready var _visibility_range_label: Label = %PrepShipVisibilityLabel
@onready var _mining_radius_label: Label = %PrepShipMiningRadiusLabel
@onready var _move_speed_label: Label = %PrepShipMoveSpeedLabel
@onready var _turn_rate_label: Label = %PrepShipTurnRateLabel
@onready var _mining_power_label: Label = %PrepShipMiningPowerLabel
@onready var _mining_interval_label: Label = %PrepShipMiningIntervalLabel
@onready var _mining_power_per_sec_label: Label = %PrepShipMiningDpsLabel
@onready var _world: Node2D = %PrepShipPreviewWorld
@onready var _ship_preview_stack: Control = %PrepShipPreviewStack
@onready var _prep_parts_strip: MarginContainer = %PrepPartsOverlayStrip
@onready var _prep_parts_hbox: HBoxContainer = %PrepPartsHBox
@onready var _ship_preview_label: Label = %ShipPreviewLabel
@onready var _ship_description_label: Label = %ShipPreviewDescriptionLabel
@onready var _ship_lock_reason: Label = %ShipPreviewLockReasonLabel
@onready var _ship_picker_prev: Button = %PrepShipPickerPrevBtn
@onready var _ship_picker_next: Button = %PrepShipPickerNextBtn
@onready var _ship_picker_scroll: ScrollContainer = %PrepShipPickerScroll
@onready var _ship_picker_hbox: HBoxContainer = %PrepShipPickerHBox

@onready var _ship_tabs: TabContainer = %ShipTabs
@onready var _stage_summary: Label = %PrepStageSummaryLabel
@onready var _stage_option: OptionButton = %PrepStageOptionButton
@onready var _stage_type_tree: Tree = %PrepStageBlockTypesTree
@onready var _debug_reset: Button = %PrepDebugResetProgressBtn
@onready var _stats_tabs: TabContainer = %StatsTabs
@onready var _shop_money_label: Label = %PrepShopMoneyLabel
@onready var _shop_upgrades_label: Label = %PrepShopSectionTitleLabel
@onready var _shop_batch_row: HBoxContainer = %PrepShopBatchRow
@onready var _shop_batch_btn: Button = %PrepShopBatchBtn
@onready var _shop_upgrades: VBoxContainer = %PrepShopUpgradesList

var _upgrade_batch_index: int = 0
var _ship_pick_buttons: Dictionary = {}  # StringName -> Button
## Root from `ShipData.ship_scene` (implements mining API from `ShipBase`).
var _preview_ship: Node2D
var _shop_row_info_labels: Array[Label] = []
var _part_tooltip: Control


func _ready() -> void:
	_stats_tabs.set_tab_title(0, "Ship")
	_stats_tabs.set_tab_title(1, "Progress")
	if _ship_tabs:
		_ship_tabs.set_tab_title(0, "Ship")
		_ship_tabs.set_tab_title(1, "Stage")
		_ship_tabs.tab_changed.connect(_on_ship_tab_changed)
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
	if _ship_picker_prev:
		_ship_picker_prev.pressed.connect(_on_ship_picker_prev_pressed)
	if _ship_picker_next:
		_ship_picker_next.pressed.connect(_on_ship_picker_next_pressed)
	if _ship_picker_scroll:
		var hb := _ship_picker_scroll.get_h_scroll_bar()
		if hb:
			hb.visible = false
			if not hb.value_changed.is_connected(_on_ship_picker_h_scroll_value_changed):
				hb.value_changed.connect(_on_ship_picker_h_scroll_value_changed)
		if not _ship_picker_scroll.resized.is_connected(_on_ship_picker_scroll_resized):
			_ship_picker_scroll.resized.connect(_on_ship_picker_scroll_resized)
	if not GameStatistics.stats_changed.is_connected(_on_stats_changed):
		GameStatistics.stats_changed.connect(_on_stats_changed)
	if not GameStatistics.fuel_changed.is_connected(_on_fuel_changed):
		GameStatistics.fuel_changed.connect(_on_fuel_changed)
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	if not PartRegistry.parts_changed.is_connected(_on_parts_changed):
		PartRegistry.parts_changed.connect(_on_parts_changed)
	if _ship_preview_stack and not _ship_preview_stack.resized.is_connected(_on_ship_preview_stack_resized):
		_ship_preview_stack.resized.connect(_on_ship_preview_stack_resized)
	if _stage_option:
		if _stage_option.get_item_count() == 0:
			for row in PREP_STAGE_CHOICES:
				_stage_option.add_item(str(row["label"]))
		if not _stage_option.item_selected.is_connected(_on_prep_stage_choice_selected):
			_stage_option.item_selected.connect(_on_prep_stage_choice_selected)
		_sync_prep_stage_option_from_session()
	_Bootstrap.ensure_initialized()
	_prep_bootstrap_after_registry_and_career()


func _prep_bootstrap_after_registry_and_career() -> void:
	ShipDataRegistry.reload_active()
	GameStatistics.apply_active_ship_fuel_baseline()
	_apply_prep_parts_overlay_layout()
	_ensure_ship_picker_buttons()
	_rebuild_preview_ship()
	_refresh_all()
	call_deferred("_update_ship_picker_scroll_state")
	call_deferred("_rebuild_parts_strip")
	call_deferred("_sync_prep_stage_option_from_session")


func _sync_prep_stage_option_from_session() -> void:
	if _stage_option == null:
		return
	for i in PREP_STAGE_CHOICES.size():
		if PREP_STAGE_CHOICES[i]["id"] == GameSession.selected_stage_id:
			if _stage_option.selected != i:
				_stage_option.set_block_signals(true)
				_stage_option.select(i)
				_stage_option.set_block_signals(false)
			break


func _on_prep_stage_choice_selected(idx: int) -> void:
	if idx < 0 or idx >= PREP_STAGE_CHOICES.size():
		return
	GameSession.selected_stage_id = PREP_STAGE_CHOICES[idx]["id"]
	GameSession.save_career()
	_refresh_stage_tab()


func _select_ship(ship_id: StringName) -> void:
	GameSession.selected_ship_id = ship_id
	ShipDataRegistry.reload_active()
	GameStatistics.apply_active_ship_fuel_baseline()
	_rebuild_preview_ship()
	GameSession.save_career()
	_refresh_all()
	call_deferred("_apply_prep_parts_overlay_layout")


func _on_ship_preview_stack_resized() -> void:
	_apply_prep_parts_overlay_layout()


func _rebuild_preview_ship() -> void:
	if _world == null:
		return
	for c in _world.get_children():
		_world.remove_child(c)
		c.free()
	_preview_ship = null
	var chain: Array[StringName] = ShipDataRegistry.get_mission_ship_chain_ship_ids()
	if chain.is_empty():
		_rebuild_parts_strip()
		return
	var head_sd: Resource = ShipDataRegistry.get_ship_data(chain[0])
	if head_sd == null:
		_rebuild_parts_strip()
		return
	var head_ps: Variant = head_sd.get("ship_scene")
	if head_ps == null or not (head_ps is PackedScene):
		push_error("Prep: active ShipData missing ship_scene")
		_rebuild_parts_strip()
		return
	_preview_ship = (head_ps as PackedScene).instantiate() as Node2D
	if _preview_ship == null or not _preview_ship.has_method("get_effective_mine_damage_per_tick"):
		push_error("Prep: ship_scene must extend ShipBase")
		if _preview_ship != null:
			_preview_ship.queue_free()
		_preview_ship = null
		_rebuild_parts_strip()
		return
	_world.add_child(_preview_ship)
	_preview_ship.scale = _PREVIEW_SCALE
	_preview_ship.position = _PREVIEW_POS
	_preview_ship.rotation = 0.0
	for i in range(1, chain.size()):
		var sid: StringName = chain[i]
		var sd: Resource = ShipDataRegistry.get_ship_data(sid)
		if sd == null:
			continue
		var ps: Variant = sd.get("ship_scene")
		if ps == null or not (ps is PackedScene):
			continue
		var node: Node2D = (ps as PackedScene).instantiate() as Node2D
		if node == null or not node.has_method("get_effective_mine_damage_per_tick"):
			if node != null:
				node.queue_free()
			continue
		if node is ShipBase:
			(node as ShipBase).follower_visual_only = true
		node.scale = Vector2.ONE * _PREVIEW_SCALE * ShipChainLayout.FOLLOWER_SCALE
		_world.add_child(node)
	_layout_preview_ship_chain()
	for p in _world.get_children():
		var n2 := p as Node2D
		if n2:
			PartVisuals.attach_to_ship(n2)
	_rebuild_parts_strip()


func _apply_prep_parts_overlay_layout() -> void:
	if _prep_parts_strip:
		_prep_parts_strip.set_anchor(SIDE_LEFT, 0.0)
		_prep_parts_strip.set_anchor(SIDE_TOP, 1.0)
		_prep_parts_strip.set_anchor(SIDE_RIGHT, 1.0)
		_prep_parts_strip.set_anchor(SIDE_BOTTOM, 1.0)
		_prep_parts_strip.offset_left = prep_parts_overlay_margins.x
		_prep_parts_strip.offset_top = -prep_parts_overlay_height - prep_parts_overlay_margins.y
		_prep_parts_strip.offset_right = -prep_parts_overlay_margins.z
		_prep_parts_strip.offset_bottom = -prep_parts_overlay_margins.w
		_prep_parts_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_prep_parts_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_prep_parts_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_prep_parts_strip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if _prep_parts_hbox:
		_prep_parts_hbox.add_theme_constant_override(&"separation", prep_part_chip_spacing)
		_prep_parts_hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _prep_type_display_name(type_key: StringName) -> String:
	return String(type_key).replace("_", " ").capitalize()


func _prep_make_part_chip(type_key: StringName, part_id: StringName) -> Control:
	var pd: PartData = PartRegistry.get_part_data(part_id)
	var name_txt: String = "Empty"
	var type_txt: String = _prep_type_display_name(type_key)
	var icon_scene: PackedScene
	if pd != null:
		name_txt = pd.display_name
		type_txt = String(pd.part_type).replace("_", " ").capitalize()
		if pd.visuals != null:
			icon_scene = pd.visuals.prep_icon_scene
			if icon_scene == null:
				icon_scene = pd.visuals.ship_scene

	var chip := Control.new()
	if prep_part_icon_template != null:
		chip = prep_part_icon_template.instantiate() as Control
	if chip == null:
		chip = Control.new()
	chip.custom_minimum_size = prep_part_chip_min_size
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	chip.mouse_entered.connect(_on_prep_part_chip_entered.bind(type_key, part_id))
	chip.mouse_exited.connect(_on_prep_part_chip_exited)

	var name_lbl := chip.get_node_or_null(^"%NameLabel") as Label
	if name_lbl != null:
		name_lbl.text = name_txt
	var type_lbl := chip.get_node_or_null(^"%TypeLabel") as Label
	if type_lbl != null:
		type_lbl.text = type_txt
		type_lbl.visible = prep_part_show_type_label

	var icon := chip.get_node_or_null("Col/Row/Icon") as Control
	if icon != null:
		icon.custom_minimum_size = prep_part_icon_size
	var viewport := chip.get_node_or_null("Col/Row/Icon/SubViewport") as SubViewport
	if viewport != null:
		viewport.size = Vector2i(int(maxf(1.0, prep_part_icon_size.x)), int(maxf(1.0, prep_part_icon_size.y)))
	var missing_icon_lbl := chip.get_node_or_null("Col/Row/Icon/MissingIconLabel") as Label
	if missing_icon_lbl != null:
		missing_icon_lbl.visible = icon_scene == null
	var icon_root := chip.get_node_or_null("Col/Row/Icon/SubViewport/IconRoot") as Node2D
	if icon_root != null:
		var icon_position := prep_part_icon_offset
		if viewport != null:
			icon_position = Vector2(viewport.size) * 0.5 + prep_part_icon_offset
		icon_root.position = icon_position
		if icon_scene != null:
			var icon_node := icon_scene.instantiate() as Node2D
			if icon_node != null:
				icon_node.scale = Vector2.ONE * prep_part_icon_scale
				icon_root.add_child(icon_node)

	return chip


func _rebuild_parts_strip() -> void:
	if _prep_parts_hbox == null:
		return
	_on_prep_part_chip_exited()
	_apply_prep_parts_overlay_layout()
	for c in _prep_parts_hbox.get_children():
		_prep_parts_hbox.remove_child(c)
		c.queue_free()
	var order: Array[StringName] = [&"fuel_tank", &"drill", &"treads"]
	for type_key in order:
		var pid: StringName = PartRegistry.get_equipped_for_type_key(type_key)
		_prep_parts_hbox.add_child(_prep_make_part_chip(type_key, pid))
	call_deferred("_apply_prep_parts_overlay_layout")


func _ensure_part_tooltip() -> void:
	if _part_tooltip != null:
		return
	var node := _PREP_PART_TOOLTIP_SCENE.instantiate() as Control
	if node == null or not node.has_method(&"setup_from_equipped_slot"):
		push_error("Prep: prep_part_hover_tooltip scene must expose setup_from_equipped_slot")
		if node != null:
			node.queue_free()
		return
	_part_tooltip = node
	_part_tooltip.visible = false
	add_child(_part_tooltip)


func _on_prep_part_chip_entered(type_key: StringName, part_id: StringName) -> void:
	_ensure_part_tooltip()
	if _part_tooltip == null:
		return
	_part_tooltip.call(&"setup_from_equipped_slot", type_key, part_id)
	_part_tooltip.visible = true
	call_deferred("_finish_part_tooltip_position")


func _finish_part_tooltip_position() -> void:
	if _part_tooltip == null or not _part_tooltip.visible:
		return
	var vp := get_viewport()
	var tip_size: Vector2 = _part_tooltip.size
	if tip_size.x < 4.0 or tip_size.y < 4.0:
		tip_size = _part_tooltip.get_combined_minimum_size()
	var mouse_local := vp.get_mouse_position()
	var pos := mouse_local + Vector2(14.0, 14.0)
	var vr := vp.get_visible_rect().size
	pos.x = clampf(pos.x, 8.0, vr.x - tip_size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vr.y - tip_size.y - 8.0)
	_part_tooltip.position = pos


func _on_prep_part_chip_exited() -> void:
	if _part_tooltip != null:
		_part_tooltip.visible = false


func _on_parts_changed() -> void:
	_rebuild_parts_strip()
	call_deferred("_rebuild_preview_ship")


func _layout_preview_ship_chain() -> void:
	if _world == null or _preview_ship == null:
		return
	var ch := _world.get_children()
	if ch.size() < 2:
		return
	var prev_nd: Node2D = ch[0] as Node2D
	if prev_nd == null:
		return
	var step: float = ShipChainLayout.SEGMENT_SPACING_PX * _PREVIEW_SCALE.x
	for j in range(1, ch.size()):
		var tail_nd: Node2D = ch[j] as Node2D
		if tail_nd == null:
			continue
		var back: Vector2 = -prev_nd.global_transform.x.normalized()
		tail_nd.global_position = prev_nd.global_position + back * step
		tail_nd.rotation = prev_nd.rotation
		prev_nd = tail_nd


func _on_ship_tab_changed(tab: int) -> void:
	if tab == _STAGE_TAB_INDEX:
		_refresh_stage_tab()


func _on_debug_reset_pressed() -> void:
	GameSession.reset_all_progress()
	ShipDataRegistry.reload_active()
	_rebuild_preview_ship()
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
	# Unlock chain can grow (e.g. new ship); refresh ship chain without requiring re-select.
	_rebuild_preview_ship()


func _on_shop_purchase(upgrade_id: StringName) -> void:
	UpgradeBus.try_purchase_count(upgrade_id, _current_upgrade_batch_request())


func _on_dynamic_shop_purchase(upgrade_id: StringName) -> void:
	_on_shop_purchase(upgrade_id)


func _refresh_ship_preview_banner() -> void:
	var sid: StringName = GameSession.selected_ship_id
	var sd: Resource = ShipDataRegistry.get_ship_data(sid)
	var ship_unlocked: bool = ShipDataRegistry.is_ship_unlocked(sid)
	if _start:
		_start.disabled = not ship_unlocked
	if _ship_preview_label:
		if sd == null:
			_ship_preview_label.text = "—"
		else:
			_ship_preview_label.text = str(sd.get("display_name")).strip_edges()
	if _ship_description_label:
		var desc_text: String = str(sd.get("description")).strip_edges() if sd != null else ""
		_ship_description_label.text = desc_text
		_ship_description_label.visible = not desc_text.is_empty()
	if _ship_lock_reason:
		if ship_unlocked:
			_ship_lock_reason.visible = false
			_ship_lock_reason.text = ""
		else:
			var reason: String = ShipDataRegistry.get_ship_lock_reason(sid)
			_ship_lock_reason.text = reason
			_ship_lock_reason.visible = not reason.is_empty()


func _refresh_all() -> void:
	_refresh_ship_preview_banner()
	_refresh_ship_picker()
	_refresh_progress()
	_refresh_ship_stats()
	_refresh_shop()
	if _ship_tabs and _ship_tabs.current_tab == _STAGE_TAB_INDEX:
		_refresh_stage_tab()


func _is_stub_ship_id(ship_id: StringName) -> bool:
	return String(ship_id).begins_with(_STUB_SHIP_PREFIX)


func _stub_slot_index(ship_id: StringName) -> int:
	var tail: String = String(ship_id).trim_prefix(_STUB_SHIP_PREFIX)
	return tail.to_int()


func _ensure_ship_picker_buttons() -> void:
	if _ship_picker_hbox == null:
		return
	if not _ship_pick_buttons.is_empty():
		return
	var ordered_ids: Array[StringName] = []
	ordered_ids.assign(ShipDataRegistry.get_all_ship_ids_sorted())
	for i in range(1, _DUMMY_SHIP_STUB_COUNT + 1):
		ordered_ids.append(StringName("%s%02d" % [_STUB_SHIP_PREFIX, i]))
	for sid in ordered_ids:
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(104, 34)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if _is_stub_ship_id(sid):
			btn.disabled = true
			btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		else:
			btn.pressed.connect(_select_ship.bind(sid))
		_ship_picker_hbox.add_child(btn)
		_ship_pick_buttons[sid] = btn


func _refresh_ship_picker() -> void:
	_ensure_ship_picker_buttons()
	var cur: StringName = GameSession.selected_ship_id
	for sid in _ship_pick_buttons:
		var btn: Button = _ship_pick_buttons[sid] as Button
		if btn == null:
			continue
		if _is_stub_ship_id(sid):
			btn.text = "… #%02d" % _stub_slot_index(sid)
			btn.modulate = Color(0.52, 0.52, 0.55, 1.0)
			continue
		var sd: Resource = ShipDataRegistry.get_ship_data(sid)
		btn.text = str(sd.get("display_name")).strip_edges() if sd != null else String(sid)
		btn.modulate = Color(0.5, 1.0, 0.65, 1.0) if sid == cur else Color.WHITE
	call_deferred("_update_ship_picker_scroll_state")


func _on_ship_picker_h_scroll_value_changed(_value: float) -> void:
	call_deferred("_update_ship_picker_scroll_state")


func _on_ship_picker_scroll_resized() -> void:
	call_deferred("_update_ship_picker_scroll_state")


func _on_ship_picker_prev_pressed() -> void:
	if _ship_picker_scroll == null:
		return
	_ship_picker_scroll.scroll_horizontal = maxi(
		0, _ship_picker_scroll.scroll_horizontal - _SHIP_PICK_SCROLL_STEP_PX
	)
	call_deferred("_update_ship_picker_scroll_state")


func _on_ship_picker_next_pressed() -> void:
	if _ship_picker_scroll == null:
		return
	var hbar := _ship_picker_scroll.get_h_scroll_bar()
	var mx: int = int(hbar.max_value)
	_ship_picker_scroll.scroll_horizontal = mini(mx, _ship_picker_scroll.scroll_horizontal + _SHIP_PICK_SCROLL_STEP_PX)
	call_deferred("_update_ship_picker_scroll_state")


func _update_ship_picker_scroll_state() -> void:
	if _ship_picker_scroll == null or _ship_picker_prev == null or _ship_picker_next == null:
		return
	var hbar := _ship_picker_scroll.get_h_scroll_bar()
	var overflow: bool = hbar.max_value > hbar.page + 1.0
	_ship_picker_prev.visible = overflow
	_ship_picker_next.visible = overflow
	if not overflow:
		_ship_picker_prev.disabled = true
		_ship_picker_next.disabled = true
		return
	var cur: float = float(_ship_picker_scroll.scroll_horizontal)
	var max_scroll: float = float(hbar.max_value)
	_ship_picker_prev.disabled = cur <= 0.5
	_ship_picker_next.disabled = cur >= max_scroll - 0.5


func _refresh_stage_tab() -> void:
	if _stage_type_tree == null or _stage_summary == null:
		return
	var sid: StringName = GameSession.selected_stage_id
	var title := String(sid)
	for row in PREP_STAGE_CHOICES:
		if row["id"] == sid:
			title = str(row["label"])
			break
	_stage_summary.text = "Stage: %s" % title
	_stage_type_tree.clear()
	var root: TreeItem = _stage_type_tree.create_item()
	for spec in MiningWorld.get_stage_block_type_rows(sid):
		var type_id: int = int(spec["type_id"])
		if type_id < 0 or type_id >= MiningWorld.TYPE_MAX_HP.size():
			continue
		var it: TreeItem = _stage_type_tree.create_item(root)
		if GameSession.is_block_type_discovered(sid, type_id):
			it.set_text(0, str(spec.get("label", "?")))
			it.set_text(1, "%d" % int(MiningWorld.TYPE_MAX_HP[type_id]))
			it.set_text(2, "%d" % int(MiningWorld.TYPE_MONEY[type_id]))
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
	if _preview_ship == null:
		return
	var ship_preview = _preview_ship
	if _visibility_range_label:
		_visibility_range_label.text = "Visibility Range: %d cells" % ship_preview.get_effective_vision_radius_cells()
	if _mining_radius_label:
		var half_cell: float = MiningWorld.CELL_SIZE_PX * 0.5
		var world_r: float = ship_preview.get_effective_drill_game_radius_px()
		var r_rel: float = world_r / half_cell if half_cell > 0.0 else 0.0
		_mining_radius_label.text = "Mining Radius: %.2f" % r_rel
	if _move_speed_label:
		_move_speed_label.text = "Move Speed: %d" % int(roundf(ship_preview.get_effective_move_speed_px_s()))
	if _turn_rate_label:
		_turn_rate_label.text = "Turn Rate: %.1f rad/s" % ship_preview.get_effective_turn_rate_rad_s()
	if _mining_power_label:
		_mining_power_label.text = "Mining Power: %.1f" % ship_preview.get_effective_mine_damage_per_tick()
	if _mining_interval_label:
		_mining_interval_label.text = "Mining Interval: %.1f" % ship_preview.mine_interval_s
	if _mining_power_per_sec_label:
		var dt: float = ship_preview.mine_interval_s
		if dt > 0.0:
			var dps: float = ship_preview.get_effective_mine_damage_per_tick() / dt
			_mining_power_per_sec_label.text = "Mining Power / s: %.1f" % dps
		else:
			_mining_power_per_sec_label.text = "Mining Power / s: —"


func _clear_shop_upgrades() -> void:
	_shop_row_info_labels.clear()
	if _shop_upgrades == null:
		return
	for i in range(_shop_upgrades.get_child_count() - 1, -1, -1):
		var c: Node = _shop_upgrades.get_child(i)
		_shop_upgrades.remove_child(c)
		c.free()


func _add_shop_row(upgrade_id: StringName) -> void:
	if _shop_upgrades == null:
		return
	var row := VBoxContainer.new()
	row.set_meta("upgrade_id", upgrade_id)
	row.add_theme_constant_override("separation", 2)
	var info := Label.new()
	_shop_row_info_labels.append(info)
	row.add_child(info)
	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	var tier_stack := Control.new()
	tier_stack.custom_minimum_size = Vector2(0, 32)
	tier_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.max_value = 10.0
	bar.show_percentage = false
	tier_stack.add_child(bar)
	var tier_lbl := Label.new()
	tier_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tier_lbl.add_theme_font_size_override("font_size", 14)
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tier_stack.add_child(tier_lbl)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(96, 32)
	btn.pressed.connect(_on_dynamic_shop_purchase.bind(upgrade_id))
	buy_row.add_child(tier_stack)
	buy_row.add_child(btn)
	row.add_child(buy_row)
	_shop_upgrades.add_child(row)
	# Stash for refresh
	row.set_meta("info", info)
	row.set_meta("bar", bar)
	row.set_meta("tier_lbl", tier_lbl)
	row.set_meta("btn", btn)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _refresh_shop() -> void:
	var ship_ok: bool = ShipDataRegistry.is_ship_unlocked(GameSession.selected_ship_id)
	if _shop_batch_row:
		_shop_batch_row.visible = ship_ok
	if _shop_upgrades_label:
		_shop_upgrades_label.visible = ship_ok
	if _shop_upgrades:
		_shop_upgrades.visible = ship_ok
	if not ship_ok:
		return
	_refresh_shop_batch_button()
	if _shop_upgrades:
		# Build rows on first use or if empty / count mismatch
		var up_ids: Array[StringName] = []
		for u in ShipDataRegistry.get_active_ship_upgrades():
			if u != null:
				up_ids.append(u.get("id") as StringName)
		if _shop_upgrades.get_child_count() != up_ids.size():
			_clear_shop_upgrades()
			for ui in up_ids:
				_add_shop_row(ui)
		# If still empty (e.g. no data), try building once
		if _shop_upgrades.get_child_count() == 0 and not up_ids.is_empty():
			for ui in up_ids:
				_add_shop_row(ui)
		_shop_row_info_labels.clear()
		for i in _shop_upgrades.get_child_count():
			var row: VBoxContainer = _shop_upgrades.get_child(i) as VBoxContainer
			if row == null:
				continue
			var upgrade_id: StringName = row.get_meta("upgrade_id") as StringName
			var info: Label = row.get_meta("info") as Label
			var bar: ProgressBar = row.get_meta("bar") as ProgressBar
			var tier_lbl: Label = row.get_meta("tier_lbl") as Label
			var btn: Button = row.get_meta("btn") as Button
			if info:
				_shop_row_info_labels.append(info)
			_set_shop_tier_label(upgrade_id, tier_lbl)
			_set_shop_tier_progress(upgrade_id, bar)
			if btn:
				_set_shop_button(upgrade_id, btn)
			if info:
				_set_shop_info_label(upgrade_id, info)


func _set_shop_info_label(upgrade_id: StringName, label: Label) -> void:
	if label == null:
		return
	if not ShipDataRegistry.has_upgrade(upgrade_id):
		label.text = ""
		return
	if UpgradeBus.is_maxed(upgrade_id):
		var cap_lv: int = UpgradeBus.get_max_level(upgrade_id)
		var ud_snap: Resource = ShipDataRegistry.get_upgrade(upgrade_id)
		var effs_snap: Array = ud_snap.get("effects") as Array
		var snap_parts: Array[String] = []
		for eff in effs_snap:
			if eff == null:
				continue
			var st_snap: StringName = ShipUpgradeEffect.normalize_effect_stat_id(eff.get("stat"))
			var contrib: float
			if st_snap == &"drill_range_bonus_game_px":
				contrib = _shop_drill_radius_display_total(upgrade_id, cap_lv)
				contrib -= _shop_drill_radius_display_total(upgrade_id, 0)
			else:
				contrib = ShipDataRegistry.preview_effective_stat(
					st_snap, upgrade_id, cap_lv
				)
				contrib -= ShipDataRegistry.preview_effective_stat(st_snap, upgrade_id, 0)
			var snap_line: String = _shop_format_snapshot_line(ud_snap, st_snap, contrib)
			if not snap_line.is_empty():
				snap_parts.append(snap_line)
		label.text = " · ".join(snap_parts)
		return
	var req: int = _current_upgrade_batch_request()
	var n_afford: int = UpgradeBus.get_purchase_count_for_request(
		upgrade_id, req if req >= 0 else -1
	)
	var next_teaser: bool = n_afford <= 0
	var n_disp: int = 1 if next_teaser else n_afford
	var deltas: Array = ShipDataRegistry.preview_upgrade_stat_deltas(upgrade_id, n_disp)
	var parts: Array[String] = []
	for e in deltas:
		var line: String = _shop_format_stat_delta_line(e, upgrade_id, n_disp)
		if not line.is_empty():
			parts.append(line)
	if parts.is_empty():
		label.text = ""
		return
	var prefix: String = ""
	if n_disp > 1:
		prefix = "×%d: " % n_disp
	var body: String = " · ".join(parts)
	label.text = prefix + body


func _shop_drill_radius_display_total(upgrade_id: StringName, drill_level: int) -> float:
	var h: float = MiningWorld.CELL_SIZE_PX * 0.5
	if _preview_ship == null:
		return 0.0
	var base: float = _preview_ship.get_drill_game_radius_px()
	var bonus: float = ShipDataRegistry.preview_effective_stat(
		&"drill_range_bonus_game_px", upgrade_id, drill_level
	)
	return (base + bonus) / h if h > 0.0 else 0.0


func _shop_format_stat_delta_line(e: Dictionary, upgrade_id: StringName, n_disp: int) -> String:
	var st: StringName = e["stat"] as StringName
	var delta: float = float(e["delta"])
	var after: float = float(e["after"])
	if st == &"drill_range_bonus_game_px":
		if _preview_ship == null:
			return ""
		var cur: int = UpgradeBus.get_level(upgrade_id)
		var before_u: float = _shop_drill_radius_display_total(upgrade_id, cur)
		var after_u: float = _shop_drill_radius_display_total(upgrade_id, cur + n_disp)
		delta = after_u - before_u
		after = after_u
	return _shop_format_line_for_stat(e, delta, after)


func _shop_decimal_places_for_stat(st: StringName) -> int:
	match String(st):
		"mine_damage_per_tick", "drill_range_bonus_game_px":
			return 2
		"money_double_chance", "turn_rate_rad_s":
			return 1
		_:
			return 0


func _shop_format_stat_value(v: float, st: StringName) -> String:
	return _shop_format_number_plain(v, _shop_decimal_places_for_stat(st))


func _shop_upgrade_display_name(ud: Resource) -> String:
	if ud == null:
		return ""
	return str(ud.get("shop_display_name")).strip_edges()


func _shop_format_number_plain(v: float, decimal_places: int) -> String:
	if decimal_places <= 0:
		return "%d" % int(round(v))
	if decimal_places == 1:
		return "%.1f" % v
	if decimal_places == 2:
		return "%.2f" % v
	if decimal_places == 3:
		return "%.3f" % v
	return ("%." + str(decimal_places) + "f") % v


## Max-tier snapshot: +value + display name from ShipUpgradeData.
func _shop_format_snapshot_line(ud: Resource, st_snap: StringName, contrib: float) -> String:
	if ud == null or absf(contrib) < 1e-5:
		return ""
	var label := _shop_upgrade_display_name(ud)
	if label.is_empty():
		return ""
	return "+%s %s" % [_shop_format_stat_value(contrib, st_snap), label]


func _shop_format_line_for_stat(e: Dictionary, delta: float, after: float) -> String:
	if absf(delta) < 1e-5:
		return ""
	var st: StringName = e["stat"] as StringName
	var label := str(e.get("shop_display_name")).strip_edges()
	if label.is_empty():
		push_warning("Missing shop_display_name for stat: %s" % st)
		label = "[Missing shop_display_name: %s]" % st

	var after_u: float = after
	if st == &"vision_radius_cells":
		after_u = float(maxi(1, int(round(after))))

	var space := ""
	if not label.begins_with("%"):
		space = " "

	return "+%s%s%s (→ %s)" % [
		_shop_format_stat_value(delta, st),
		space,
		label,
		_shop_format_stat_value(after_u, st),
	]


func _set_shop_tier_label(upgrade_id: StringName, label: Label) -> void:
	if label == null:
		return
	if not ShipDataRegistry.has_upgrade(upgrade_id):
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
	if not ShipDataRegistry.has_upgrade(upgrade_id):
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
	if not ShipDataRegistry.has_upgrade(upgrade_id):
		btn.text = "—"
		btn.disabled = true
		btn.modulate = Color.WHITE
		return
	if UpgradeBus.is_maxed(upgrade_id):
		btn.text = "MAX"
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
	if not ShipDataRegistry.is_ship_unlocked(GameSession.selected_ship_id):
		return
	ShipDataRegistry.reload_active()
	GameSession.begin_run()
	GameSession.go_to_planet(GameSession.get_stage_planet_scene_path())
