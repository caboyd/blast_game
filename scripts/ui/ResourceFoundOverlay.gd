extends MarginContainer

## Top-left mined-resource list for the current run (counts on full clears only).
## Base sizes × 1.25 from original HUD spec.

const _UI_SCALE := 1.25
const _ROW_SEP := int(round(4.0 * _UI_SCALE))
const _BAR_HEIGHT := int(round(10.0 * _UI_SCALE))
const _FONT_SZ := int(round(13.0 * _UI_SCALE))
const _BAR_FRAC_OF_VIEWPORT_W := 0.1
const _OUTLINE_W := maxi(1, int(round(2.0 * _UI_SCALE)))
const _OUTLINE_COLOR := Color(0.06, 0.08, 0.11, 0.98)
const _LABEL_OUTLINE := maxi(1, int(round(4.0 * _UI_SCALE)))

## Parallel order to `MiningWorld` type ids (index 0 = TYPE_EMPTY …).
static var _BLOCK_TYPE_NAMES: PackedStringArray = PackedStringArray([
	"Empty",
	"Dirt",
	"Stone",
	"Gold",
	"Fuel",
	"Ruby",
	"Packed earth",
	"Clay",
	"Shale",
	"Copper",	
	"Tin",
	"Sandstone",
	"Obsidian",
	"Iron",
	"Silver",
])

var _rows_host: VBoxContainer
## Row under cursor (`type_id`); -1 = none.
var _hover_type_id: int = -1
var _viewport_w_for_bars: int = 1280


func _resource_stylebox(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(fill.r, fill.g, fill.b, 0.96)
	sb.set_border_width_all(_OUTLINE_W)
	sb.border_color = _OUTLINE_COLOR
	sb.set_corner_radius_all(maxi(1, int(round(2.0 * _UI_SCALE))))
	return sb


func _line_height_px() -> int:
	return maxi(
		_BAR_HEIGHT,
		_FONT_SZ * 2 + _LABEL_OUTLINE * 2 + 6
	)


func _block_name(type_id: int) -> String:
	var bname := "Block %d" % type_id
	if type_id >= 0 and type_id < _BLOCK_TYPE_NAMES.size():
		bname = String(_BLOCK_TYPE_NAMES[type_id])
	return bname


func _hover_detail_text(type_id: int) -> String:
	var hp := _max_hp_for_type(type_id)
	return "%s - %d HP" % [_block_name(type_id).to_upper(), hp]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("margin_left", int(round(12.0 * _UI_SCALE)))
	add_theme_constant_override("margin_top", int(round(2.0 * _UI_SCALE)))
	add_theme_constant_override("margin_bottom", int(round(4.0 * _UI_SCALE)))

	_rows_host = VBoxContainer.new()
	_rows_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_rows_host.add_theme_constant_override("separation", 0)
	_rows_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows_host)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	if not GameStatistics.run_mined_resources_changed.is_connected(_on_mined_changed):
		GameStatistics.run_mined_resources_changed.connect(_on_mined_changed)

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()

	_refresh_rows()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		if _hover_type_id != -1:
			_hover_type_id = -1
			_refresh_hover_visuals_only()


func _on_viewport_size_changed() -> void:
	var vp := get_viewport()
	if vp != null:
		_viewport_w_for_bars = maxi(1, int(vp.get_visible_rect().size.x))
	call_deferred("_refresh_rows")


func _on_mined_changed() -> void:
	_refresh_rows()


func _on_row_mouse_entered(type_id: int) -> void:
	_hover_type_id = type_id
	_refresh_hover_visuals_only()


func _on_hover_zone_mouse_exited(type_id: int) -> void:
	if _hover_type_id != type_id:
		return
	var gp: Vector2 = get_global_mouse_position()
	if _global_point_in_row_hover_region(type_id, gp):
		return
	_hover_type_id = -1
	_refresh_hover_visuals_only()


func _global_point_in_row_hover_region(type_id: int, global_p: Vector2) -> bool:
	for cand in _rows_host.get_children():
		if not cand is HBoxContainer:
			continue
		var hb: HBoxContainer = cand as HBoxContainer
		if int(hb.get_meta(&"type_id", -1)) != type_id:
			continue
		if hb.get_child_count() < 2:
			return false
		var bar_wrap: Control = hb.get_child(0) as Control
		var hover_lbl: Control = hb.get_child(1) as Control
		if bar_wrap != null and bar_wrap.get_global_rect().has_point(global_p):
			return true
		if hover_lbl != null and hover_lbl.visible and hover_lbl.get_global_rect().has_point(global_p):
			return true
		return false
	return false


func _max_hp_for_type(type_id: int) -> int:
	if type_id >= 0 and type_id < MiningWorld.TYPE_MAX_HP.size():
		return int(MiningWorld.TYPE_MAX_HP[type_id])
	return 0


func _apply_bar_label_layout(lbl: Label) -> void:
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.offset_top = 0
	lbl.offset_bottom = 0


func _refresh_hover_visuals_only() -> void:
	for row in _rows_host.get_children():
		if not row is HBoxContainer:
			continue
		var h := row as HBoxContainer
		if h.get_child_count() < 2:
			continue
		var detail := h.get_child(1) as Label
		if detail == null:
			continue
		var tid: int = int(h.get_meta(&"type_id", -1))
		if tid == _hover_type_id:
			detail.text = _hover_detail_text(tid)
			detail.visible = true
			detail.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			detail.visible = false
			detail.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh_rows() -> void:
	_hover_type_id = -1
	while _rows_host.get_child_count() > 0:
		var c: Node = _rows_host.get_child(0)
		_rows_host.remove_child(c)
		c.free()

	var rows: Array[Dictionary] = GameStatistics.get_run_mined_resource_rows_sorted()
	if rows.is_empty():
		visible = false
		custom_minimum_size = Vector2.ZERO
		MiningMissionUI.notify_top_hud_layout_dirty()
		return

	visible = true
	var max_count: int = 0
	for r in rows:
		max_count = maxi(max_count, int(r["count"]))
	if max_count <= 0:
		visible = false
		custom_minimum_size = Vector2.ZERO
		MiningMissionUI.notify_top_hud_layout_dirty()
		return

	var line_h := _line_height_px()
	var bar_full_w: int = maxi(8, int(roundf(float(_viewport_w_for_bars) * _BAR_FRAC_OF_VIEWPORT_W)))

	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		var type_id: int = int(r["type_id"])
		var cnt: int = int(r["count"])
		var col: Color = r["color"] as Color

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(round(10.0 * _UI_SCALE)))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_meta(&"type_id", type_id)
		row.set_meta(&"count", cnt)
		if i > 0:
			row.add_theme_constant_override("margin_top", _ROW_SEP)

		var bar_wrap := Control.new()
		bar_wrap.custom_minimum_size = Vector2(bar_full_w, line_h)
		bar_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		bar_wrap.clip_contents = false
		bar_wrap.mouse_entered.connect(_on_row_mouse_entered.bind(type_id))
		bar_wrap.mouse_exited.connect(_on_hover_zone_mouse_exited.bind(type_id))
		row.add_child(bar_wrap)

		var fill_w: int = 0
		if max_count > 0:
			fill_w = int(roundf(float(cnt) / float(max_count) * float(bar_full_w)))
		fill_w = clampi(fill_w, 0, bar_full_w)
		if cnt > 0:
			fill_w = maxi(1, fill_w)

		var bar_fill := Panel.new()
		bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
		bar_fill.anchor_right = 0.0
		bar_fill.anchor_bottom = 0.0
		bar_fill.offset_left = 0.0
		bar_fill.offset_top = 0.0
		bar_fill.offset_right = float(fill_w)
		bar_fill.offset_bottom = float(line_h)
		bar_fill.add_theme_stylebox_override(&"panel", _resource_stylebox(col))
		bar_wrap.add_child(bar_fill)

		var bar_lbl := Label.new()
		bar_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar_lbl.offset_left = int(round(4.0 * _UI_SCALE))
		bar_lbl.offset_right = -int(round(4.0 * _UI_SCALE))
		bar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		bar_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		bar_lbl.add_theme_font_size_override("font_size", _FONT_SZ)
		bar_lbl.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0, 1.0))
		bar_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.98))
		bar_lbl.add_theme_constant_override("outline_size", _LABEL_OUTLINE)
		bar_lbl.text = str(cnt)
		_apply_bar_label_layout(bar_lbl)
		bar_wrap.add_child(bar_lbl)

		var hover_detail := Label.new()
		hover_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hover_detail.visible = false
		hover_detail.mouse_entered.connect(_on_row_mouse_entered.bind(type_id))
		hover_detail.mouse_exited.connect(_on_hover_zone_mouse_exited.bind(type_id))
		hover_detail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		hover_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hover_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hover_detail.autowrap_mode = TextServer.AUTOWRAP_OFF
		hover_detail.add_theme_font_size_override("font_size", _FONT_SZ)
		hover_detail.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0, 1.0))
		hover_detail.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.98))
		hover_detail.add_theme_constant_override("outline_size", _LABEL_OUTLINE)
		row.add_child(hover_detail)

		_rows_host.add_child(row)

	_rows_host.queue_sort()
	var inner: Vector2 = _rows_host.get_combined_minimum_size()
	var ml := get_theme_constant("margin_left", "MarginContainer")
	var mr := get_theme_constant("margin_right", "MarginContainer")
	var mt := get_theme_constant("margin_top", "MarginContainer")
	var mb := get_theme_constant("margin_bottom", "MarginContainer")
	custom_minimum_size = Vector2(inner.x + ml + mr, inner.y + mt + mb)
	MiningMissionUI.notify_top_hud_layout_dirty()
