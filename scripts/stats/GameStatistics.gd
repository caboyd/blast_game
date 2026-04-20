extends Node

signal stats_changed

const DAMAGE_SOURCE_TURRET := &"turret"
const DAMAGE_SOURCE_CLICK := &"click"

var total_blocks_destroyed: int = 0
var furthest_depth_cells: int = 0
## Total HP removed from block cells (not the same as blocks destroyed).
var damage_to_blocks_turret: int = 0
var damage_to_blocks_click: int = 0


func add_block_damage(amount: int, source: StringName) -> void:
	if amount <= 0:
		return
	if source == DAMAGE_SOURCE_TURRET:
		damage_to_blocks_turret += amount
	elif source == DAMAGE_SOURCE_CLICK:
		damage_to_blocks_click += amount
	stats_changed.emit()


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
