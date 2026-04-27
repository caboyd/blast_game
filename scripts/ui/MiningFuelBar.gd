extends Control

@onready var _bar: ProgressBar = $MarginContainer/BarStack/ProgressBar
@onready var _label: Label = $MarginContainer/BarStack/ValueLabel


func _ready() -> void:
	_sync_from_stats()
	if not GameStatistics.fuel_changed.is_connected(_on_fuel_changed):
		GameStatistics.fuel_changed.connect(_on_fuel_changed)


func _sync_from_stats() -> void:
	var mx: float = maxf(GameStatistics.fuel_max, 1.0)
	_bar.max_value = mx
	_bar.value = clampf(GameStatistics.fuel, 0.0, mx)
	if _label:
		_label.text = "%.0f / %.0f" % [GameStatistics.fuel, GameStatistics.fuel_max]


func _on_fuel_changed(_current: float, _max_fuel: float) -> void:
	_sync_from_stats()
