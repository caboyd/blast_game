extends GridContainer
class_name ResponsiveGrid

## Column count when viewport is landscape (or not forced to single column).
@export var columns_horizontal: int = 4:
	set(v):
		columns_horizontal = maxi(1, v)
		if is_inside_tree():
			_apply_columns()

## When true and viewport height > width, use 1 column (mobile portrait).
@export var force_single_column_when_portrait: bool = true


func _ready() -> void:
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_columns()


func _on_viewport_size_changed() -> void:
	_apply_columns()


func _apply_columns() -> void:
	if not is_inside_tree():
		return
	var vp_node := get_viewport()
	if vp_node == null:
		return
	var vp := vp_node.get_visible_rect().size
	var is_portrait := vp.y > vp.x
	if force_single_column_when_portrait and is_portrait:
		columns = 1
	else:
		columns = maxi(1, columns_horizontal)
