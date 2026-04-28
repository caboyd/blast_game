extends Control

@onready var _overflow_bar: ProgressBar = $MarginContainer/BarStack/BarsVBox/OverflowProgressBar
@onready var _bar: ProgressBar = $MarginContainer/BarStack/BarsVBox/ProgressBar
@onready var _label: Label = $MarginContainer/BarStack/ValueLabel


func _ready() -> void:
	_sync_from_stats()
	if not GameStatistics.fuel_changed.is_connected(_on_fuel_changed):
		GameStatistics.fuel_changed.connect(_on_fuel_changed)


func _sync_from_stats() -> void:
	var fm: float = maxf(GameStatistics.fuel_max, 1.0)
	var cur: float = GameStatistics.fuel
	var overflow_amt: float = maxf(cur - fm, 0.0)
	var ov_budget: float = GameStatistics.fuel_overflow_budget()

	_bar.max_value = fm
	_bar.value = clampf(cur, 0.0, fm)

	_overflow_bar.max_value = maxf(ov_budget, 0.001)
	_overflow_bar.value = clampf(overflow_amt, 0.0, ov_budget)
	_overflow_bar.visible = overflow_amt > 0.001

	if _label:
		_label.text = "%.0f / %.0f" % [cur, fm]


func _on_fuel_changed(_current: float, _max_fuel: float) -> void:
	_sync_from_stats()
