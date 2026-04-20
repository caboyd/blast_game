extends Control

const StatItemScene := preload("res://scenes/ui/StatItem.tscn")
const UpgradeItemScene := preload("res://scenes/ui/UpgradeItem.tscn")

const DEFAULT_STAT_CONFIG: Array[Dictionary] = [
	{"id": &"blocks", "name": "blocks"},
	{"id": &"turret_dmg", "name": "turret dmg"},
	{"id": &"click_dmg", "name": "click dmg"},
	{"id": &"depth", "name": "depth"},
]

const DEFAULT_UPGRADE_CONFIG: Array[Dictionary] = [
	{"id": &"melter", "name": "MELTER", "cost": 1000, "disabled": false},
	{"id": &"furnace", "name": "FURNACE", "cost": 1000, "disabled": false},
	{"id": &"stub_cryo", "name": "CRYO CHAMBER", "cost": 0, "disabled": true},
	{"id": &"stub_fusion", "name": "FUSION CORE", "cost": 0, "disabled": true},
	{"id": &"stub_turret", "name": "AUTO TURRET", "cost": 0, "disabled": true},
	{"id": &"stub_shield", "name": "SHIELD GEN", "cost": 0, "disabled": true},
	{"id": &"stub_drone", "name": "REPAIR DRONE", "cost": 0, "disabled": true},
	{"id": &"stub_aura", "name": "EMP AURA", "cost": 0, "disabled": true},
]

## If empty, DEFAULT_STAT_CONFIG used. Keys: `id` (StringName), optional `name` (display label), optional `icon` (Texture2D).
@export var stat_config: Array[Dictionary] = []

## If empty, DEFAULT_UPGRADE_CONFIG used. Keys: `id`, `name`, `cost`, optional `icon`, optional `disabled` (stub / locked row).
@export var upgrade_config: Array[Dictionary] = []

@export var stats_columns_horizontal: int = 6:
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

@onready var outer: PanelContainer = $Outer
@onready var handle_wrap: PanelContainer = $HandleWrap
@onready var upgrades_section: PanelContainer = $Outer/Inner/MainVBox/UpgradesSection
@onready var collapse_handle: Button = $HandleWrap/CollapseHandle
@onready var stats_scroll: ScrollContainer = $Outer/Inner/MainVBox/StatsRow/StatsSection/StatsScroll
@onready var stats_grid = $Outer/Inner/MainVBox/StatsRow/StatsSection/StatsScroll/StatsGrid
@onready var upgrades_grid = $Outer/Inner/MainVBox/UpgradesSection/UpgradesScroll/UpgradesGrid

var _is_expanded: bool = false
var _hud_layout_ready: bool = false

var _stat_items: Dictionary = {}  # StringName -> StatItem (instanced)


func _ready() -> void:
	collapse_handle.pressed.connect(_on_collapse_handle_pressed)
	stats_grid.columns_horizontal = stats_columns_horizontal
	upgrades_grid.columns_horizontal = upgrades_columns_horizontal
	_build_stats()
	_build_upgrades()
	_apply_expanded(false)
	_hud_layout_ready = true
	GameStatistics.stats_changed.connect(_on_stats_changed)
	refresh()
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed_fit_stats):
		get_viewport().size_changed.connect(_on_viewport_size_changed_fit_stats)


func _on_collapse_handle_pressed() -> void:
	_apply_expanded(not _is_expanded)


func _apply_expanded(open: bool) -> void:
	_is_expanded = open
	upgrades_section.visible = open
	if open:
		_set_expanded_horizontal_layout()
		offset_top = expanded_offset_top
		collapse_handle.text = "▼"
		call_deferred("_fit_stats_scroll_height")
	else:
		collapse_handle.text = "▲"
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


func _on_stats_changed() -> void:
	refresh()


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
		var uid: StringName = _read_string_name(d, "id")
		if String(uid).is_empty():
			continue
		var uname: String = str(d.get("name", uid))
		var ucost: int = int(d.get("cost", 0))
		var u_disabled: bool = bool(d.get("disabled", false))
		var item = UpgradeItemScene.instantiate()
		item.apply_config(uid, uname, ucost, _read_texture(d, "icon"), u_disabled)
		upgrades_grid.add_child(item)


func _schedule_layout_after_stat_change() -> void:
	if _is_expanded:
		call_deferred("_fit_stats_scroll_height")
	else:
		_fit_collapsed_height()


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


func refresh() -> void:
	for sid: StringName in _stat_items.keys():
		var item = _stat_items[sid]
		match String(sid):
			"blocks":
				item.set_value(str(GameStatistics.total_blocks_destroyed))
			"turret_dmg":
				item.set_value(str(GameStatistics.damage_to_blocks_turret))
			"click_dmg":
				item.set_value(str(GameStatistics.damage_to_blocks_click))
			"depth":
				item.set_value(str(GameStatistics.furthest_depth_cells))
			_:
				item.set_value("—")
