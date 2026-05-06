extends VBoxContainer

## Min time between full pill refreshes (run $, rolling $/s, fuel ETA). Burst signals do not bypass this.
@export_range(50, 2000, 1)
var pill_refresh_interval_ms: int = 250

@onready var _stats_label: Label = $PillWrap/StatsPill/StatsLabel

var _last_pill_refresh_ms: int = 0


func _ready() -> void:
	for c in get_children():
		if c is Control:
			var ch: Control = c as Control
			if not ch.resized.is_connected(_on_child_band_resized):
				ch.resized.connect(_on_child_band_resized)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	_sync_pill_immediate()
	call_deferred("refit_band_height")


func refit_band_height() -> void:
	## `anchor_preset` top-wide uses height = `offset_bottom`; keep it in sync with stacked children.
	queue_sort()
	var h: float = get_combined_minimum_size().y
	offset_bottom = maxf(h, 1.0)


func _on_child_band_resized() -> void:
	call_deferred("refit_band_height")


func _on_visibility_changed() -> void:
	set_process(visible)
	if visible:
		call_deferred("_sync_pill_immediate")
		call_deferred("refit_band_height")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var interval_ms: int = maxi(pill_refresh_interval_ms, 1)
	if now - _last_pill_refresh_ms < interval_ms:
		return
	_sync_pill_immediate()


func _sync_pill_immediate() -> void:
	if _stats_label == null:
		return
	var run_money: int = GameStatistics.run_mined_money_awarded
	var rps: float = GameStatistics.get_run_rolling_money_per_second()
	var sec: float = GameStatistics.get_fuel_seconds_remaining_from_leading_ship_drain()
	_stats_label.text = "$%s  ·  $%.1f/s  ·  %s" % [
		_format_int_commas(run_money),
		rps,
		_format_time_remaining(sec),
	]
	_last_pill_refresh_ms = Time.get_ticks_msec()


func _format_int_commas(v: int) -> String:
	var s := str(abs(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c == 3 and i > 0:
			out = "," + out
			c = 0
	if v < 0:
		out = "-" + out
	return out


func _format_time_remaining(seconds: float) -> String:
	if is_inf(seconds):
		return "∞"
	if not is_finite(seconds) or seconds < 0.0:
		return "—"
	var total := int(floorf(seconds + 0.5))
	total = maxi(0, total)
	var m: int = int(floorf(float(total) / 60.0))
	var s: int = total - m * 60
	if m >= 60:
		var h: int = int(floorf(float(m) / 60.0))
		m = m - h * 60
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]
