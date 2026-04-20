extends Node

signal stats_changed

var total_blocks_destroyed: int = 0
var furthest_depth_cells: int = 0


func add_blocks_destroyed(count: int) -> void:
	if count <= 0:
		return
	total_blocks_destroyed += count
	stats_changed.emit()


func update_depth_in_cells(instantaneous_depth: int) -> void:
	if instantaneous_depth <= furthest_depth_cells:
		return
	furthest_depth_cells = instantaneous_depth
	stats_changed.emit()
