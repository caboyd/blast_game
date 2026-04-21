extends PanelContainer
class_name UpgradeItem

signal purchase_pressed(upgrade_id: StringName)

const _BUY_STYLE := preload("res://resources/ui/hud_style_buy_button.tres")

const _BG := Color(0.290196, 0.180392, 0.117647, 1)
const _BG_HOVER := Color(0.36, 0.24, 0.16, 1)
const _BG_PRESSED := Color(0.22, 0.14, 0.09, 1)
const _NAME_COLOR := Color(0.96, 0.9, 0.78, 1)
const _NAME_COLOR_DISABLED := Color(0.55, 0.5, 0.48, 0.85)
const _BUY_FONT := Color(0.29, 0.18, 0.12, 1)
const _BUY_FONT_DIM := Color(0.4, 0.38, 0.36, 0.9)
const _MOD_DISABLED := Color(0.72, 0.7, 0.74, 0.88)
const _DMG_PREVIEW_GREEN := Color(0.525, 0.85, 0.55, 1)

## Source id from config (`laser_turret`, `click`, stub ids, …).
var source_id: StringName = &""
## When true, card is a non-interactive stub.
var upgrade_disabled: bool = false

@onready var _icon: TextureRect = $MainVBox/TopRow/Icon
@onready var _name_label: Label = $MainVBox/TopRow/NameLabel
@onready var _upgrades_host: HBoxContainer = $MainVBox/TopRow/UpgradesHost
@onready var _stats_row: HBoxContainer = $MainVBox/StatsRow
@onready var _locked_label: Label = $MainVBox/LockedLabel

var _source: Dictionary = {}
var _header_icon: Texture2D
var _stat_richtext: Dictionary = {}  # StringName -> RichTextLabel
var _stat_values: Dictionary = {}  # StringName -> int
var _stat_string_override: Dictionary = {}  # StringName -> String; when set, overrides int display
var _upgrade_meta: Dictionary = {}  # StringName -> { target_stat, delta, button, label_base, row }
var _affordable: Dictionary = {}
var _purchaseable: Dictionary = {}
var _hover_upgrade: StringName = &""


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_sync_icon()
	_apply_source_to_nodes_if_ready()


func apply_source_config(source: Dictionary, tex: Texture2D = null) -> void:
	_header_icon = tex
	_source = source
	source_id = _read_string_name(source, "id")
	upgrade_disabled = bool(source.get("disabled", false))
	if is_node_ready():
		_sync_icon()
		_apply_source_to_nodes_if_ready()


func _sync_icon() -> void:
	if _icon == null:
		return
	if _header_icon:
		_icon.texture = _header_icon
		_icon.visible = true
	else:
		_icon.texture = null
		_icon.visible = false


## Clears any string override so the stat uses numeric `value` again.
func set_stat_value(stat_key: StringName, value: int) -> void:
	_stat_string_override.erase(stat_key)
	_stat_values[stat_key] = value
	if is_node_ready():
		_refresh_stat_display(stat_key)


func set_stat_text(stat_key: StringName, text: String) -> void:
	_stat_string_override[stat_key] = text
	if is_node_ready():
		_refresh_stat_display(stat_key)


func set_upgrade_state(
	upgrade_key: StringName,
	label_base: String,
	level: int,
	purchaseable: bool,
	affordable: bool,
	cost_display: String
) -> void:
	_purchaseable[upgrade_key] = purchaseable
	_affordable[upgrade_key] = affordable
	var meta: Dictionary = _upgrade_meta.get(upgrade_key, {}) as Dictionary
	var btn: Button = meta.get("button", null) as Button
	if btn:
		btn.text = "%s  Lv%d  %s" % [label_base, maxi(0, level), cost_display]
		var may_buy := purchaseable and affordable
		btn.add_theme_color_override("font_color", _BUY_FONT if may_buy else _BUY_FONT_DIM)
		btn.disabled = not purchaseable
		if not purchaseable:
			btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
		elif not affordable:
			btn.modulate = Color(0.82, 0.82, 0.82, 1.0)
		else:
			btn.modulate = Color.WHITE


func _apply_source_to_nodes_if_ready() -> void:
	if not is_node_ready():
		return
	_clear_dynamic_children()
	_hover_upgrade = &""
	if upgrade_disabled:
		_build_stub_card()
	else:
		_build_active_card()


func _clear_dynamic_children() -> void:
	for c in _stats_row.get_children():
		c.queue_free()
	for c in _upgrades_host.get_children():
		c.queue_free()
	_stat_richtext.clear()
	_stat_values.clear()
	_stat_string_override.clear()
	_upgrade_meta.clear()
	_affordable.clear()
	_purchaseable.clear()


func _build_stub_card() -> void:
	_sync_icon()
	_name_label.text = str(_source.get("name", source_id))
	_locked_label.visible = true
	_stats_row.visible = false
	_upgrades_host.visible = false
	_apply_stub_panel_style()


func _build_active_card() -> void:
	_sync_icon()
	_name_label.text = str(_source.get("name", source_id))
	_locked_label.visible = false
	_stats_row.visible = true
	_upgrades_host.visible = true
	_name_label.add_theme_color_override("font_color", _NAME_COLOR)
	_stats_row.alignment = BoxContainer.ALIGNMENT_BEGIN

	var stats_raw = _source.get("stats", [])
	if stats_raw is Array:
		for st in stats_raw:
			if st is Dictionary:
				_add_stat_cell(st as Dictionary)

	var ups_raw = _source.get("upgrades", [])
	if ups_raw is Array:
		for u in ups_raw:
			if u is Dictionary:
				_add_upgrade_button(u as Dictionary)

	remove_theme_stylebox_override("panel")
	add_theme_stylebox_override("panel", _make_panel_style(false, false))
	modulate = Color.WHITE


func _add_stat_cell(st: Dictionary) -> void:
	var sid: StringName = _read_string_name(st, "id")
	if String(sid).is_empty():
		return
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 4)
	var nl := Label.new()
	nl.text = str(st.get("label", sid)) + ":"
	nl.add_theme_color_override("font_color", _NAME_COLOR)
	nl.add_theme_font_size_override("font_size", 12)
	cell.add_child(nl)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.custom_minimum_size = Vector2(40, 20)
	rt.add_theme_color_override("default_color", _NAME_COLOR)
	rt.add_theme_font_size_override("normal_font_size", 12)
	cell.add_child(rt)
	_stats_row.add_child(cell)
	_stat_richtext[sid] = rt


func _add_upgrade_button(u: Dictionary) -> void:
	var uid: StringName = _read_string_name(u, "id")
	if String(uid).is_empty():
		return
	if UpgradeBus.get_max_level(uid) == 0:
		return
	var target_stat: StringName = _read_string_name(u, "target_stat")
	var delta: int = int(u.get("delta", 1))
	var label_base: String = str(u.get("label", uid))

	var btn := Button.new()
	btn.text = label_base
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", _BUY_FONT)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_stylebox_override("normal", _BUY_STYLE)
	btn.add_theme_stylebox_override("hover", _BUY_STYLE)
	btn.add_theme_stylebox_override("pressed", _BUY_STYLE)
	btn.mouse_entered.connect(_on_upgrade_btn_mouse_entered.bind(uid))
	btn.mouse_exited.connect(_on_upgrade_btn_mouse_exited.bind(uid))
	btn.pressed.connect(_on_upgrade_btn_pressed.bind(uid))

	_upgrades_host.add_child(btn)
	_upgrade_meta[uid] = {
		"target_stat": target_stat,
		"delta": delta,
		"button": btn,
		"label_base": label_base,
	}


func _on_upgrade_btn_pressed(uid: StringName) -> void:
	if _purchaseable.get(uid, false) and _affordable.get(uid, false):
		purchase_pressed.emit(uid)


func _on_upgrade_btn_mouse_entered(uid: StringName) -> void:
	if not _purchaseable.get(uid, false):
		return
	_hover_upgrade = uid
	_refresh_all_stat_displays()


func _on_upgrade_btn_mouse_exited(uid: StringName) -> void:
	if _hover_upgrade == uid:
		_hover_upgrade = &""
	_refresh_all_stat_displays()


func _refresh_all_stat_displays() -> void:
	for k in _stat_richtext.keys():
		_refresh_stat_display(k)


func _refresh_stat_display(stat_key: StringName) -> void:
	var rt: RichTextLabel = _stat_richtext.get(stat_key, null) as RichTextLabel
	if rt == null:
		return
	if _stat_string_override.has(stat_key):
		rt.text = str(_stat_string_override[stat_key])
		return
	var base: int = int(_stat_values.get(stat_key, 0))
	var show_delta := false
	var dlt := 0
	if not String(_hover_upgrade).is_empty():
		var meta: Dictionary = _upgrade_meta.get(_hover_upgrade, {}) as Dictionary
		var ts: StringName = meta.get("target_stat", &"") as StringName
		if ts == stat_key:
			show_delta = true
			dlt = int(meta.get("delta", 0))
	if show_delta and dlt > 0 and _purchaseable.get(_hover_upgrade, false):
		var gc := _DMG_PREVIEW_GREEN.to_html(false)
		rt.text = "%d [color=#%s]+ %d[/color]" % [base, gc, dlt]
	else:
		rt.text = str(base)


func _apply_stub_panel_style() -> void:
	modulate = _MOD_DISABLED
	_name_label.add_theme_color_override("font_color", _NAME_COLOR_DISABLED)
	remove_theme_stylebox_override("panel")
	var flat := StyleBoxFlat.new()
	flat.bg_color = _BG.darkened(0.12)
	flat.set_corner_radius_all(4)
	flat.set_content_margin_all(6)
	add_theme_stylebox_override("panel", flat)


func _make_panel_style(hover: bool, pressed: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(4)
	s.set_content_margin_all(6)
	if pressed:
		s.bg_color = _BG_PRESSED
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 2
		s.shadow_offset = Vector2(0, 1)
	elif hover:
		s.bg_color = _BG_HOVER
		s.shadow_color = Color(0, 0, 0, 0.4)
		s.shadow_size = 5
		s.shadow_offset = Vector2(2, 3)
	else:
		s.bg_color = _BG
		s.shadow_color = Color(0, 0, 0, 0.32)
		s.shadow_size = 4
		s.shadow_offset = Vector2(2, 2)
	return s


func _read_string_name(d: Dictionary, key: String) -> StringName:
	if not d.has(key):
		return &""
	var v = d[key]
	if v is StringName:
		return v
	return StringName(str(v))
