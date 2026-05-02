extends Control
class_name BottomPlayerStatsStrip

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
