class_name TargetSpotterManager
extends Node2D

@export var spotter_scene: PackedScene
@export var spotter_count: int = 5

var _conveyor: TargetConveyor
var _last_highlight_dt: DestructibleTarget


func _ready() -> void:
	process_priority = 1
	var p := get_parent()
	if p != null:
		_conveyor = p.get_node_or_null("TargetConveyor") as TargetConveyor
	if spotter_scene == null:
		push_warning("TargetSpotterManager.spotter_scene is not set.")
		return
	for i in spotter_count:
		var s := spotter_scene.instantiate() as TargetSpotter
		if s == null:
			push_error("TargetSpotterManager: spotter_scene must be a TargetSpotter.")
			return
		s.name = "TargetSpotter_%d" % i
		add_child(s)
		s.global_position = _random_left_half_global()


func _process(_delta: float) -> void:
	_sync_highlights()


func _random_left_half_global() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return global_position
	var rect := vp.get_visible_rect()
	var inv := vp.get_canvas_transform().affine_inverse()
	var x := randf_range(rect.position.x, rect.position.x + rect.size.x * 0.5)
	var y := randf_range(rect.position.y, rect.position.y + rect.size.y)
	return inv * Vector2(x, y)


func _sync_highlights() -> void:
	if _conveyor == null:
		return
	var dt := _conveyor.get_active_target() as DestructibleTarget
	if dt == null or dt.is_destroyed():
		if _last_highlight_dt != null and is_instance_valid(_last_highlight_dt):
			_last_highlight_dt.clear_highlight()
		_last_highlight_dt = null
		return

	_last_highlight_dt = dt

	var cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	for c in get_children():
		var s := c as TargetSpotter
		if s == null:
			continue
		var tc := s.get_tracked_cell()
		if tc.x < 0:
			continue
		if not dt.is_cell_solid(tc):
			continue
		var key := Vector2i(tc.x, tc.y)
		if seen.has(key):
			continue
		seen[key] = true
		cells.append(tc)

	dt.set_highlight_cells(cells)
