extends Control


@onready var _blocks_label: Label = $HBoxContainer/BlocksLabel
@onready var _depth_label: Label = $HBoxContainer/DepthLabel


func _ready() -> void:
	GameStatistics.stats_changed.connect(_on_stats_changed)
	refresh()


func _on_stats_changed() -> void:
	refresh()


func refresh() -> void:
	_blocks_label.text = "Blocks destroyed: %d" % GameStatistics.total_blocks_destroyed
	_depth_label.text = "Depth: %d" % GameStatistics.furthest_depth_cells
