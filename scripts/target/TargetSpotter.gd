class_name TargetSpotter
extends Node2D

@export var line_width: float = 3.0
@export var line_color: Color = Color(1.0, 0.38, 0.12, 0.92)

var _line: Line2D
var _conveyor: TargetConveyor
var _tracked_cell: Vector2i = Vector2i(-1, -1)
var _current_dt: Node2D


func _ready() -> void:
	_line = get_node_or_null("Line2D") as Line2D
	if _line == null:
		_line = Line2D.new()
		_line.name = "Line2D"
		add_child(_line)
	_line.width = line_width
	_line.default_color = line_color
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND

	var n := get_parent()
	while n != null:
		_conveyor = n.get_node_or_null("TargetConveyor") as TargetConveyor
		if _conveyor != null:
			break
		n = n.get_parent()

	if _conveyor != null:
		if not _conveyor.active_target_changed.is_connected(_on_active_target_changed):
			_conveyor.active_target_changed.connect(_on_active_target_changed)
		_on_active_target_changed(_conveyor.get_active_target())


func get_tracked_cell() -> Vector2i:
	return _tracked_cell


func _on_active_target_changed(new_target: Node2D) -> void:
	_current_dt = null
	_tracked_cell = Vector2i(-1, -1)
	if new_target == null:
		return
	_current_dt = new_target


func _process(_delta: float) -> void:
	if _conveyor == null:
		return
	var dt := _conveyor.get_active_target()
	if dt == null:
		_clear_visual()
		return
	if dt != _current_dt:
		_on_active_target_changed(dt)

	if not dt.has_method(&"is_destroyed") or bool(dt.call(&"is_destroyed")):
		_clear_visual()
		return

	var from_local := dt.to_local(global_position)
	if _tracked_cell.x < 0 or not dt.has_method(&"is_cell_solid") or not bool(dt.call(&"is_cell_solid", _tracked_cell)):
		if dt.has_method(&"get_closest_row_leftmost_cell"):
			_tracked_cell = dt.call(&"get_closest_row_leftmost_cell", from_local) as Vector2i
		else:
			_tracked_cell = Vector2i(-1, -1)

	if _tracked_cell.x < 0:
		_clear_line_only()
		return

	if not dt.has_method(&"cell_center_local"):
		_clear_line_only()
		return
	var end_local := dt.call(&"cell_center_local", _tracked_cell) as Vector2
	_line.clear_points()
	_line.add_point(Vector2.ZERO)
	_line.add_point(to_local(dt.to_global(end_local)))


func _clear_line_only() -> void:
	_line.clear_points()


func _clear_visual() -> void:
	_clear_line_only()
