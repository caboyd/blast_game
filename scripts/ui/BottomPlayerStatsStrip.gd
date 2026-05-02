extends Control
class_name BottomPlayerStatsStrip

@onready var _panel: PanelContainer = $Center/Panel
@onready var _label: Label = $Center/Panel/Margin/Label

var _lead: ShipBase = null


func _ready() -> void:
	if not UpgradeBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	if not PartRegistry.parts_changed.is_connected(_on_parts_changed):
		PartRegistry.parts_changed.connect(_on_parts_changed)
	refresh()


func _on_upgrade_purchased(_id: StringName, _new_level: int) -> void:
	refresh()


func _on_parts_changed() -> void:
	refresh()


## Leading mining ship (head of the train). Safe to call with `null` before spawn.
func bind_leading_ship(ship: Node2D) -> void:
	_lead = ship as ShipBase
	refresh()


func refresh() -> void:
	if _label == null:
		return
	var drill_s: String = "—"
	var speed_s: String = "—"
	if _lead != null:
		drill_s = _format_drill(_lead.get_effective_mine_damage_per_tick())
		var cps: float = _lead.get_effective_move_speed_px_s() / MiningWorld.CELL_SIZE_PX
		speed_s = "%.2f" % cps
	var ship_name: String = "—"
	var sd_lead: Resource = ShipDataRegistry.get_ship_data(GameSession.selected_ship_id)
	if sd_lead != null:
		ship_name = str(sd_lead.get("display_name"))
	var chain: Array[StringName] = ShipDataRegistry.get_mission_ship_chain_ship_ids()
	var name_parts: PackedStringArray = []
	for sid in chain:
		var sd: Resource = ShipDataRegistry.get_ship_data(sid)
		if sd != null:
			name_parts.append(str(sd.get("display_name")))
	var train_s: String = "%d (%s)" % [chain.size(), ", ".join(name_parts)]
	_label.text = (
		"Drill: %s  •  Speed: %s c/s  •  Ship: %s  •  Train: %s"
		% [drill_s, speed_s, ship_name, train_s]
	)


func _format_drill(v: float) -> String:
	var r: float = roundf(v)
	if is_equal_approx(v, r):
		return str(int(r))
	return "%.1f" % v


## Pixels from bottom of viewport to topmost visible strip pixel (for gameplay letterbox).
func get_occlusion_bottom_reserve_px() -> int:
	if not is_inside_tree():
		return _occlusion_reserve_fallback_px()
	var r: Rect2 = get_global_rect()
	for c in get_children():
		if c is Control and (c as Control).visible:
			r = r.merge((c as Control).get_global_rect())
	var vp: Viewport = get_viewport()
	if vp == null:
		return maxi(ceili(r.size.y), 1)
	var vis: Rect2 = vp.get_visible_rect()
	var top_y: float = r.position.y
	var reserve: float = vis.end.y - top_y
	return maxi(ceili(reserve), 1)


func _occlusion_reserve_fallback_px() -> int:
	var h: float = 0.0
	if _panel != null:
		h = maxf(h, _panel.get_combined_minimum_size().y)
	h += 24.0
	return maxi(ceili(h), 1)
