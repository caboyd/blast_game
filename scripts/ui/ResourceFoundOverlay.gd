extends MarginContainer

## Top-left mined-resource list for the current run (counts on full clears only).
## Base sizes × 1.25 from original HUD spec.

## Fixed cadence for mined-resource overlay rebuilds while the run has mined rows (not reset by each new block).
@export var mined_resource_refresh_interval_sec: float = 0.25
## Fixed cadence for overlay rebuilds after viewport width changes while resize keeps marking layout dirty.
@export var viewport_refresh_interval_sec: float = 0.05
## Max resource rows constructed per frame while building an off-tree list (swap happens once when complete).
@export var row_rebuild_budget_per_frame: int = 1

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

var _dirty_viewport: bool = false
var _mined_refresh_timer: Timer
var _viewport_refresh_timer: Timer
var _followup_rebuild_timer: Timer

var _incremental_rebuild_active: bool = false
var _pending_rows_host: VBoxContainer
var _pending_rows: Array[Dictionary] = []
var _pending_row_index: int = 0
var _pending_max_count: int = 0
var _pending_bar_full_w: int = 0
var _pending_line_h: int = 0
var _followup_after_current_rebuild: bool = false


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

	_mined_refresh_timer = Timer.new()
	_mined_refresh_timer.one_shot = false
	_mined_refresh_timer.timeout.connect(_on_mined_refresh_tick)
	add_child(_mined_refresh_timer)

	_viewport_refresh_timer = Timer.new()
	_viewport_refresh_timer.one_shot = false
	_viewport_refresh_timer.timeout.connect(_on_viewport_refresh_tick)
	add_child(_viewport_refresh_timer)

	_followup_rebuild_timer = Timer.new()
	_followup_rebuild_timer.one_shot = true
	_followup_rebuild_timer.timeout.connect(_on_followup_rebuild_timeout)
	add_child(_followup_rebuild_timer)

	if not GameStatistics.run_mined_resources_changed.is_connected(_on_mined_changed):
		GameStatistics.run_mined_resources_changed.connect(_on_mined_changed)

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)
	_sync_viewport_width_from_viewport()

	_refresh_rows()


func _process(_delta: float) -> void:
	if not _incremental_rebuild_active:
		set_process(false)
		return
	if _pending_rows_host == null:
		_incremental_rebuild_active = false
		set_process(false)
		return
	var budget: int = maxi(1, row_rebuild_budget_per_frame)
	var added: int = 0
	while added < budget and _pending_row_index < _pending_rows.size():
		_append_one_pending_row(_pending_row_index)
		_pending_row_index += 1
		added += 1
	if _pending_row_index >= _pending_rows.size():
		_finish_incremental_swap()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		if _hover_type_id != -1:
			_hover_type_id = -1
			_refresh_hover_visuals_only()


func _sync_viewport_width_from_viewport() -> void:
	var vp := get_viewport()
	if vp != null:
		_viewport_w_for_bars = maxi(1, int(vp.get_visible_rect().size.x))


func _run_mined_snapshot_is_empty() -> bool:
	return GameStatistics.get_run_mined_resource_rows_sorted().is_empty()


func _on_viewport_size_changed() -> void:
	_sync_viewport_width_from_viewport()
	_dirty_viewport = true
	_ensure_viewport_refresh_ticker()


func _on_mined_changed() -> void:
	if _run_mined_snapshot_is_empty():
		_stop_mined_refresh_ticker()
		_stop_viewport_refresh_ticker()
		_dirty_viewport = false
		_refresh_rows()
		return
	_ensure_mined_refresh_ticker()


func _stop_mined_refresh_ticker() -> void:
	if _mined_refresh_timer != null:
		_mined_refresh_timer.stop()


func _stop_viewport_refresh_ticker() -> void:
	if _viewport_refresh_timer != null:
		_viewport_refresh_timer.stop()


func _ensure_mined_refresh_ticker() -> void:
	if _mined_refresh_timer.is_stopped():
		_mined_refresh_timer.wait_time = maxf(0.001, mined_resource_refresh_interval_sec)
		_refresh_rows()
		_mined_refresh_timer.start()


func _ensure_viewport_refresh_ticker() -> void:
	if _viewport_refresh_timer.is_stopped():
		_viewport_refresh_timer.wait_time = maxf(0.001, viewport_refresh_interval_sec)
		_viewport_refresh_timer.start()


func _on_mined_refresh_tick() -> void:
	if _run_mined_snapshot_is_empty():
		_stop_mined_refresh_ticker()
		_refresh_rows()
		return
	_refresh_rows()


func _on_viewport_refresh_tick() -> void:
	if _dirty_viewport:
		_refresh_rows()
	if not _dirty_viewport:
		_stop_viewport_refresh_ticker()


func _on_followup_rebuild_timeout() -> void:
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


func _clear_rows_host() -> void:
	while _rows_host.get_child_count() > 0:
		var c: Node = _rows_host.get_child(0)
		_rows_host.remove_child(c)
		c.free()


func _cancel_incremental_build() -> void:
	set_process(false)
	_incremental_rebuild_active = false
	if _pending_rows_host != null:
		_pending_rows_host.queue_free()
		_pending_rows_host = null
	_pending_rows.clear()
	_pending_row_index = 0


func _schedule_followup_rebuild() -> void:
	if _followup_rebuild_timer == null or not _followup_rebuild_timer.is_stopped():
		return
	var tw := minf(mined_resource_refresh_interval_sec, viewport_refresh_interval_sec)
	_followup_rebuild_timer.wait_time = maxf(0.001, tw)
	_followup_rebuild_timer.start()


func _recompute_hover_from_mouse() -> void:
	var gp: Vector2 = get_global_mouse_position()
	_hover_type_id = -1
	for cand in _rows_host.get_children():
		if not cand is HBoxContainer:
			continue
		var hb: HBoxContainer = cand as HBoxContainer
		var tid: int = int(hb.get_meta(&"type_id", -1))
		if tid < 0:
			continue
		if _global_point_in_row_hover_region(tid, gp):
			_hover_type_id = tid
			break
	_refresh_hover_visuals_only()


func _append_one_pending_row(i: int) -> void:
	var r: Dictionary = _pending_rows[i]
	var type_id: int = int(r["type_id"])
	var cnt: int = int(r["count"])
	var col: Color = r["color"] as Color
	var line_h: int = _pending_line_h
	var bar_full_w: int = _pending_bar_full_w
	var max_count: int = _pending_max_count

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

	_pending_rows_host.add_child(row)


func _start_incremental_rebuild(rows: Array[Dictionary], max_count: int) -> void:
	_cancel_incremental_build()
	_sync_viewport_width_from_viewport()

	_pending_rows_host = VBoxContainer.new()
	_pending_rows_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_rows_host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pending_rows_host.add_theme_constant_override("separation", 0)
	_pending_rows_host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_pending_rows = rows
	_pending_max_count = max_count
	_pending_line_h = _line_height_px()
	_pending_bar_full_w = maxi(8, int(roundf(float(_viewport_w_for_bars) * _BAR_FRAC_OF_VIEWPORT_W)))
	_pending_row_index = 0
	_incremental_rebuild_active = true
	set_process(true)


func _finish_incremental_swap() -> void:
	set_process(false)
	_incremental_rebuild_active = false

	var old_host: VBoxContainer = _rows_host
	remove_child(old_host)
	old_host.queue_free()

	_rows_host = _pending_rows_host
	_pending_rows_host = null
	add_child(_rows_host)
	move_child(_rows_host, 0)

	_pending_rows.clear()
	_pending_row_index = 0

	_recompute_hover_from_mouse()

	_rows_host.queue_sort()
	var inner: Vector2 = _rows_host.get_combined_minimum_size()
	var ml := get_theme_constant("margin_left", "MarginContainer")
	var mr := get_theme_constant("margin_right", "MarginContainer")
	var mt := get_theme_constant("margin_top", "MarginContainer")
	var mb := get_theme_constant("margin_bottom", "MarginContainer")
	custom_minimum_size = Vector2(inner.x + ml + mr, inner.y + mt + mb)
	MiningMissionUI.notify_top_hud_layout_dirty()

	var schedule_followup: bool = _followup_after_current_rebuild or _dirty_viewport
	_followup_after_current_rebuild = false
	if schedule_followup:
		_schedule_followup_rebuild()
	else:
		_dirty_viewport = false


func _refresh_rows() -> void:
	var rows: Array[Dictionary] = GameStatistics.get_run_mined_resource_rows_sorted()
	if rows.is_empty():
		_cancel_incremental_build()
		_followup_after_current_rebuild = false
		if _followup_rebuild_timer != null:
			_followup_rebuild_timer.stop()
		_hover_type_id = -1
		_clear_rows_host()
		visible = false
		custom_minimum_size = Vector2.ZERO
		MiningMissionUI.notify_top_hud_layout_dirty()
		_dirty_viewport = false
		return

	var max_count: int = 0
	for r in rows:
		max_count = maxi(max_count, int(r["count"]))
	if max_count <= 0:
		_cancel_incremental_build()
		_followup_after_current_rebuild = false
		if _followup_rebuild_timer != null:
			_followup_rebuild_timer.stop()
		_hover_type_id = -1
		_clear_rows_host()
		visible = false
		custom_minimum_size = Vector2.ZERO
		MiningMissionUI.notify_top_hud_layout_dirty()
		_dirty_viewport = false
		return

	visible = true

	if _incremental_rebuild_active:
		_followup_after_current_rebuild = true
		return

	_start_incremental_rebuild(rows, max_count)
