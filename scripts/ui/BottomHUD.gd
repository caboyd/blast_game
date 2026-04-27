extends Control
class_name BottomHUD

const StatItemScene := preload("res://scenes/ui/StatItem.tscn")
const UpgradeItemScene := preload("res://scenes/ui/UpgradeItem.tscn")
const UPGRADE_BATCH_REQUESTS: Array[int] = [1, 5, 25, 100, -1]

const DEFAULT_STAT_CONFIG: Array[Dictionary] = [
	{"id": &"blocks", "name": "blocks"},
	{"id": &"depth", "name": "depth"},
	{"id": &"money", "name": "money"},
	{"id": &"time", "name": "time"},
	{"id": &"ship_hp", "name": "fuel"},
]

## Per-source `upgrades` entries map to UpgradeBus.DEFS. Optional `max_level` in DEFS caps levels; omit for infinite.
const DEFAULT_UPGRADE_CONFIG: Array[Dictionary] = [
	{
		"id": &"laser_turret",
		"name": "LASER TURRET",
		"stats": [
			{"id": &"count", "label": "Count"},
			{"id": &"damage", "label": "Damage"},
			{"id": &"fire_rate", "label": "Fire/s"},
			{"id": &"dmg_dealt", "label": "Dmg Dealt"},
		],
		"upgrades": [
			{"id": &"laser_count", "label": "Count", "target_stat": &"count", "delta": 1},
			{"id": &"laser_fire_rate", "label": "Fire rate", "target_stat": &"fire_rate", "delta": 0},
			{"id": &"melter", "label": "Damage", "target_stat": &"damage", "delta": 1},
		],
	},
	{
		"id": &"click",
		"name": "CLICK",
		"stats": [
			{"id": &"count", "label": "Count"},
			{"id": &"damage", "label": "Damage"},
			{"id": &"fire_rate", "label": "Fire/s"},
			{"id": &"radius", "label": "Radius"},
			{"id": &"dmg_dealt", "label": "Dmg Dealt"},
		],
		"upgrades": [
			{"id": &"click_count", "label": "Count", "target_stat": &"count", "delta": 0},
			{"id": &"click_fire_rate", "label": "Fire rate", "target_stat": &"fire_rate", "delta": 0},
			{"id": &"click_dmg", "label": "Damage", "target_stat": &"damage", "delta": 1},
			{"id": &"click_radius", "label": "Radius", "target_stat": &"radius", "delta": 1},
		],
	},
	{
		"id": &"cannon_turret",
		"name": "CANNON TURRET",
		"stats": [
			{"id": &"count", "label": "Count"},
			{"id": &"damage", "label": "Damage"},
			{"id": &"fire_rate", "label": "Fire/s"},
			{"id": &"blast", "label": "Blast (px)"},
			{"id": &"dmg_dealt", "label": "Dmg Dealt"},
		],
		"upgrades": [
			{"id": &"cannon_count", "label": "Count", "target_stat": &"count", "delta": 1},
			{"id": &"cannon_fire_rate", "label": "Fire rate", "target_stat": &"fire_rate", "delta": 0},
			{"id": &"cannon_shell", "label": "Damage", "target_stat": &"damage", "delta": 1},
			{"id": &"cannon_blast", "label": "Blast r", "target_stat": &"blast", "delta": 4},
		],
	},
	{"id": &"stub_fusion", "name": "FUSION CORE", "disabled": true},
	{"id": &"stub_turret", "name": "AUTO TURRET", "disabled": true},
	{"id": &"stub_shield", "name": "SHIELD GEN", "disabled": true},
	{"id": &"stub_drone", "name": "REPAIR DRONE", "disabled": true},
	{"id": &"stub_aura", "name": "EMP AURA", "disabled": true},
]

## If empty, DEFAULT_STAT_CONFIG used. Keys: `id` (StringName), optional `name` (display label), optional `icon` (Texture2D).
@export var stat_config: Array[Dictionary] = []

## If empty, DEFAULT_UPGRADE_CONFIG used. Each entry is either a locked stub (`id`, `name`, `disabled`: true) or a source card with `stats` and `upgrades` arrays.
@export var upgrade_config: Array[Dictionary] = []

## High enough that stats stay on one row until the row exceeds the viewport (use horizontal scroll).
@export var stats_columns_horizontal: int = 32:
	set(v):
		stats_columns_horizontal = maxi(1, v)
		if stats_grid:
			stats_grid.columns_horizontal = stats_columns_horizontal

@export var upgrades_columns_horizontal: int = 2:
	set(v):
		upgrades_columns_horizontal = maxi(1, v)
		if upgrades_grid:
			upgrades_grid.columns_horizontal = upgrades_columns_horizontal

## Bottom edge inset when the HUD is fully open (matches panel height from bottom).
@export var expanded_offset_top: float = -288.0

## Horizontal inset from screen edges when expanded (anchor left/right 0..1).
@export var expanded_margin_horizontal: float = 8.0

## Moves the expand/collapse handle up by this many pixels when the HUD is expanded (same height, shifted).
@export var expanded_handle_raise_px: float = 15.0

@onready var outer: PanelContainer = $Outer
@onready var handle_wrap: PanelContainer = $HandleWrap
@onready var upgrades_section: PanelContainer = $Outer/Inner/MainVBox/UpgradesSection
@onready var collapse_handle: Button = $HandleWrap/CollapseHandle
@onready var stats_scroll: ScrollContainer = $Outer/Inner/MainVBox/StatsRow/StatsSection/StatsScroll
@onready var stats_grid = $Outer/Inner/MainVBox/StatsRow/StatsSection/StatsScroll/StatsGrid
@onready var upgrade_batch_btn: Button = $Outer/Inner/MainVBox/UpgradesSection/UpgradesVBox/UpgradeBatchRow/UpgradeBatchBtn
@onready var upgrades_grid = $Outer/Inner/MainVBox/UpgradesSection/UpgradesVBox/UpgradesScroll/UpgradesGrid

var _is_expanded: bool = false
var _hud_layout_ready: bool = false
var _upgrade_batch_index: int = 0

var _stat_items: Dictionary = {}  # StringName -> StatItem (instanced)
var _handle_wrap_offset_top_base: float = 0.0
var _handle_wrap_offset_bottom_base: float = 0.0


func _ready() -> void:
	_handle_wrap_offset_top_base = handle_wrap.offset_top
	_handle_wrap_offset_bottom_base = handle_wrap.offset_bottom
	collapse_handle.pressed.connect(_on_collapse_handle_pressed)
	upgrade_batch_btn.pressed.connect(_on_upgrade_batch_btn_pressed)
	stats_grid.columns_horizontal = stats_columns_horizontal
	upgrades_grid.columns_horizontal = upgrades_columns_horizontal
	_build_stats()
	_build_upgrades()
	_apply_expanded(false)
	_hud_layout_ready = true
	GameStatistics.stats_changed.connect(_on_stats_changed)
	if not GameStatistics.fuel_changed.is_connected(_on_fuel_changed):
		GameStatistics.fuel_changed.connect(_on_fuel_changed)
	UpgradeBus.upgrade_purchased.connect(_on_upgrade_purchased)
	refresh()
	set_process(_stat_items.has(&"time"))
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed_fit_stats):
		get_viewport().size_changed.connect(_on_viewport_size_changed_fit_stats)


func _process(_delta: float) -> void:
	if not _stat_items.has(&"time"):
		return
	(_stat_items[&"time"] as StatItem).set_value(_format_mission_elapsed(GameSession.get_mission_elapsed_sec()))


func _on_upgrade_batch_btn_pressed() -> void:
	_upgrade_batch_index = (_upgrade_batch_index + 1) % UPGRADE_BATCH_REQUESTS.size()
	_refresh_upgrade_batch_button()
	_refresh_upgrades()


func _on_collapse_handle_pressed() -> void:
	_apply_expanded(not _is_expanded)


func _apply_expanded(open: bool) -> void:
	_is_expanded = open
	upgrades_section.visible = open
	if open:
		_set_expanded_horizontal_layout()
		offset_top = expanded_offset_top
		collapse_handle.text = "▼"
		handle_wrap.offset_top = _handle_wrap_offset_top_base - expanded_handle_raise_px
		handle_wrap.offset_bottom = _handle_wrap_offset_bottom_base - expanded_handle_raise_px
		call_deferred("_fit_stats_scroll_height")
	else:
		collapse_handle.text = "▲"
		handle_wrap.offset_top = _handle_wrap_offset_top_base
		handle_wrap.offset_bottom = _handle_wrap_offset_bottom_base
		_fit_collapsed_height()


func _on_viewport_size_changed_fit_stats() -> void:
	if _is_expanded:
		call_deferred("_fit_stats_scroll_height")
	else:
		_fit_collapsed_height()


func _fit_stats_scroll_height() -> void:
	if stats_scroll == null or stats_grid == null:
		return
	var gs: Vector2 = stats_grid.get_combined_minimum_size()
	stats_scroll.custom_minimum_size.x = ceili(gs.x)
	stats_scroll.custom_minimum_size.y = ceili(gs.y)


func _fit_collapsed_height() -> void:
	if _is_expanded:
		return
	_fit_stats_scroll_height()
	call_deferred("_height_after_layout")


func _height_after_layout() -> void:
	if _is_expanded:
		return
	_fit_stats_scroll_height()
	var w: int = maxi(
		ceili(outer.get_combined_minimum_size().x),
		ceili(handle_wrap.get_combined_minimum_size().x)
	)
	w = maxi(w, 1)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -w / 2.0
	offset_right = w / 2.0
	var h: int = ceili(outer.get_combined_minimum_size().y)
	offset_top = offset_bottom - float(h)


func _set_expanded_horizontal_layout() -> void:
	anchor_left = 0.0
	anchor_right = 1.0
	offset_left = expanded_margin_horizontal
	offset_right = -expanded_margin_horizontal
	grow_horizontal = Control.GROW_DIRECTION_BOTH


## Pixels from bottom of viewport to topmost visible HUD pixel (includes handle above panel).
func get_occlusion_bottom_reserve_px() -> int:
	var r: Rect2 = get_global_rect()
	for c in get_children():
		if c is Control and (c as Control).visible:
			r = r.merge((c as Control).get_global_rect())
	var vp: Viewport = get_viewport()
	if vp == null:
		var st := get_tree()
		if st != null:
			vp = st.root as Viewport
	if vp == null:
		return maxi(ceili(r.size.y), 1)
	var vis: Rect2 = vp.get_visible_rect()
	var top_y: float = r.position.y
	var reserve: float = vis.end.y - top_y
	return maxi(ceili(reserve), 1)


func _on_fuel_changed(_current: float, _max: float) -> void:
	refresh()


func _on_stats_changed() -> void:
	refresh()


func _on_upgrade_purchased(_id: StringName, _new_level: int) -> void:
	_refresh_upgrades()


func _build_stats() -> void:
	for c in stats_grid.get_children():
		c.queue_free()
	_stat_items.clear()
	var defs: Array[Dictionary] = stat_config if stat_config.size() > 0 else DEFAULT_STAT_CONFIG
	for d in defs:
		var sid: StringName = _read_string_name(d, "id")
		if String(sid).is_empty():
			continue
		var item = StatItemScene.instantiate()
		item.stat_id = sid
		item.display_name = str(d.get("name", sid))
		var tex: Texture2D = _read_texture(d, "icon")
		if tex:
			item.icon_texture = tex
		stats_grid.add_child(item)
		_stat_items[sid] = item
	if _hud_layout_ready:
		_schedule_layout_after_stat_change()


func _build_upgrades() -> void:
	for c in upgrades_grid.get_children():
		c.queue_free()
	var defs: Array[Dictionary] = upgrade_config if upgrade_config.size() > 0 else DEFAULT_UPGRADE_CONFIG
	for d in defs:
		var item = UpgradeItemScene.instantiate()
		item.apply_source_config(d, _read_texture(d, "icon"))
		if not item.upgrade_disabled:
			item.purchase_pressed.connect(_on_upgrade_item_purchase_pressed)
		upgrades_grid.add_child(item)
	_refresh_upgrade_batch_button()


func _schedule_layout_after_stat_change() -> void:
	if _is_expanded:
		call_deferred("_fit_stats_scroll_height")
	else:
		_fit_collapsed_height()


func _find_source_def(sid: StringName) -> Dictionary:
	var defs: Array[Dictionary] = upgrade_config if upgrade_config.size() > 0 else DEFAULT_UPGRADE_CONFIG
	for d in defs:
		if _read_string_name(d, "id") == sid:
			return d
	return {}


func _source_instance_count(sid: StringName) -> int:
	if sid == &"click":
		return 1
	if sid == &"laser_turret":
		return get_tree().get_nodes_in_group(&"laser_turrets").size()
	if sid == &"cannon_turret":
		return get_tree().get_nodes_in_group(&"cannon_turrets").size()
	return 0


func _first_laser_fire_rate_hz() -> float:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"laser_turrets")
	if nodes.is_empty():
		return 10.0
	var t: Node = nodes[0]
	if t is LaserTurret:
		return (t as LaserTurret).update_frequency_hz
	return 10.0


func _first_cannon_fire_rate_hz() -> float:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"cannon_turrets")
	if nodes.is_empty():
		return 1.0
	var t: Node = nodes[0]
	if t is CannonTurret:
		return (t as CannonTurret).fire_rate_hz
	return 1.0


func _stat_value_for_source(sid: StringName, stat_id: StringName) -> int:
	match String(stat_id):
		"count":
			return _source_instance_count(sid)
		"fire_rate":
			if sid == &"laser_turret":
				return int(round(_first_laser_fire_rate_hz()))
			if sid == &"cannon_turret":
				return int(round(_first_cannon_fire_rate_hz()))
			if sid == &"click":
				return int(round(1000.0 / maxf(GameStatistics.click_fire_rate_ms, 1.0)))
			return 0
	match String(sid):
		"laser_turret":
			match String(stat_id):
				"damage":
					return GameStatistics.laser_turret_damage
				"dmg_dealt":
					return GameStatistics.damage_to_blocks_laser_turret
		"cannon_turret":
			match String(stat_id):
				"damage":
					return GameStatistics.cannon_turret_damage
				"blast":
					return int(round(GameStatistics.cannon_explosion_radius_px))
				"dmg_dealt":
					return GameStatistics.damage_to_blocks_cannon_turret
		"click":
			match String(stat_id):
				"damage":
					return GameStatistics.click_damage
				"radius":
					return GameStatistics.click_radius_cells
				"dmg_dealt":
					return GameStatistics.damage_to_blocks_click
	return 0


func _cost_display_for(uid: StringName) -> String:
	if not UpgradeBus.can_upgrade(uid):
		if UpgradeBus.is_maxed(uid) and UpgradeBus.get_level(uid) > 0:
			return "MAX"
		return "—"
	var requested_count: int = _current_upgrade_batch_request()
	if requested_count < 0:
		var max_count: int = UpgradeBus.get_purchase_count_for_request(uid, requested_count)
		return "%dx $%d" % [max_count, UpgradeBus.get_purchase_cost_for_count(uid, max_count)]
	if not _has_room_for_batch(uid, requested_count):
		return "%dx —" % requested_count
	return "%dx $%d" % [requested_count, UpgradeBus.get_purchase_cost_for_count(uid, requested_count)]


func _current_upgrade_batch_request() -> int:
	return UPGRADE_BATCH_REQUESTS[_upgrade_batch_index]


func _current_upgrade_batch_label() -> String:
	var requested_count: int = _current_upgrade_batch_request()
	return "MAX" if requested_count < 0 else "%dx" % requested_count


func _refresh_upgrade_batch_button() -> void:
	if upgrade_batch_btn:
		upgrade_batch_btn.text = "Buy: %s" % _current_upgrade_batch_label()


func _has_room_for_batch(uid: StringName, requested_count: int) -> bool:
	if requested_count <= 0:
		return false
	var cap: int = UpgradeBus.get_max_level(uid)
	if cap < 0:
		return true
	return UpgradeBus.get_level(uid) + requested_count <= cap


func _batch_count_for_display(uid: StringName) -> int:
	var requested_count: int = _current_upgrade_batch_request()
	if requested_count < 0:
		return UpgradeBus.get_purchase_count_for_request(uid, requested_count)
	return requested_count if _has_room_for_batch(uid, requested_count) else 0


func _can_purchase_batch(uid: StringName) -> bool:
	var requested_count: int = _current_upgrade_batch_request()
	if requested_count < 0:
		return UpgradeBus.get_purchase_count_for_request(uid, requested_count) > 0
	return _has_room_for_batch(uid, requested_count)


func _can_afford_batch(uid: StringName) -> bool:
	var requested_count: int = _current_upgrade_batch_request()
	if requested_count < 0:
		return UpgradeBus.get_purchase_count_for_request(uid, requested_count) > 0
	if not _has_room_for_batch(uid, requested_count):
		return false
	return GameStatistics.money >= UpgradeBus.get_purchase_cost_for_count(uid, requested_count)


func set_upgrade_batch_request_for_test(requested_count: int) -> void:
	var idx := UPGRADE_BATCH_REQUESTS.find(requested_count)
	if idx >= 0:
		_upgrade_batch_index = idx
		_refresh_upgrade_batch_button()


func get_upgrade_cost_display_for_test(uid: StringName) -> String:
	return _cost_display_for(uid)


func _read_string_name(d: Dictionary, key: String) -> StringName:
	if not d.has(key):
		return &""
	var v = d[key]
	if v is StringName:
		return v
	return StringName(str(v))


func _read_texture(d: Dictionary, key: String) -> Texture2D:
	var t = d.get(key)
	return t if t is Texture2D else null


func _format_mission_elapsed(sec: float) -> String:
	var t: int = maxi(0, int(floorf(sec)))
	var h: int = t / 3600
	t %= 3600
	var m: int = t / 60
	var s2: int = t % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s2]
	return "%d:%02d" % [m, s2]


func _on_upgrade_item_purchase_pressed(upgrade_id: StringName) -> void:
	UpgradeBus.try_purchase_count(upgrade_id, _current_upgrade_batch_request())


func _refresh_upgrades() -> void:
	for c in upgrades_grid.get_children():
		if not c is UpgradeItem:
			continue
		var it: UpgradeItem = c
		if it.upgrade_disabled:
			continue
		var def: Dictionary = _find_source_def(it.source_id)
		if def.is_empty():
			continue
		var stats_raw = def.get("stats", [])
		if stats_raw is Array:
			for st in stats_raw:
				if st is Dictionary:
					var stid: StringName = _read_string_name(st, "id")
					if String(stid).is_empty():
						continue
					it.set_stat_value(stid, _stat_value_for_source(it.source_id, stid))
		var ups_raw = def.get("upgrades", [])
		if ups_raw is Array:
			for u in ups_raw:
				if u is Dictionary:
					var uid: StringName = _read_string_name(u, "id")
					if String(uid).is_empty():
						continue
					if UpgradeBus.get_max_level(uid) == 0:
						continue
					var ulbl: String = str(u.get("label", uid))
					var purchaseable: bool = UpgradeBus.can_upgrade(uid) and _can_purchase_batch(uid)
					var affordable: bool = _can_afford_batch(uid) if purchaseable else false
					it.set_upgrade_state(
						uid,
						ulbl,
						UpgradeBus.get_level(uid),
						purchaseable,
						affordable,
						_cost_display_for(uid),
						_batch_count_for_display(uid)
					)


func refresh() -> void:
	for sid: StringName in _stat_items.keys():
		var item = _stat_items[sid]
		match String(sid):
			"blocks":
				item.set_value(str(GameStatistics.get_blocks_destroyed_this_run()))
			"depth":
				item.set_value(str(GameStatistics.furthest_depth_cells))
			"money":
				item.set_value(str(GameStatistics.money))
			"time":
				item.set_value(_format_mission_elapsed(GameSession.get_mission_elapsed_sec()))
			"ship_hp":
				item.set_value(
					"%.0f / %.0f" % [GameStatistics.fuel, GameStatistics.fuel_max]
				)
			_:
				item.set_value("—")
	_refresh_upgrades()
