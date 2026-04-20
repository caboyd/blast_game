class_name DestructibleTarget
extends Node2D

signal fully_destroyed

@export var target_size_px: Vector2 = Vector2(640.0, 360.0)
@export var cell_size_px: float = 8.0
@export var fill_solid_on_reset: bool = true

@export var visual_color: Color = Color(0.25, 0.85, 0.45, 1.0)

@export var debug_destroy_on_key: bool = true
@export var debug_destroy_key: Key = KEY_K
@export var debug_damage_on_click: bool = true
@export var debug_damage_radius_px: float = 150.0

var _destroyed: bool = false

var _grid_w: int = 0
var _grid_h: int = 0
var _cells: PackedByteArray # 1 = solid, 0 = empty

var _leftmost_solid_cell_x: int = 0
var _leftmost_solid_dirty: bool = true

var _mask_image: Image
var _mask_texture: ImageTexture
var _mask_dirty: bool = true

## Per row: grid X of leftmost solid cell, or -1. _row_leftmost_pos_local[y] = cell center in local space (invalid if x < 0).
var _row_leftmost_x: PackedInt32Array = PackedInt32Array()
var _row_leftmost_pos_local: PackedVector2Array = PackedVector2Array()
var _row_leftmost_cache_dirty: bool = true

@onready var _visual: Sprite2D = $Visual


func is_destroyed() -> bool:
	return _destroyed


func set_target_visible(v: bool) -> void:
	if _visual != null:
		_visual.visible = v


func reset_target() -> void:
	_destroyed = false
	if _visual != null:
		_visual.visible = true
	_init_grid()
	_init_mask_visuals()
	_try_mark_destroyed()
	_leftmost_solid_dirty = true
	_mask_dirty = true
	_row_leftmost_cache_dirty = true


func apply_damage_circle_local(local_pos: Vector2, radius_px: float) -> void:
	if _destroyed:
		return

	var r_cells := int(ceil(radius_px / cell_size_px))
	var center := _local_to_cell(local_pos)

	var changed_any := false
	var destroyed_count := 0
	for dy in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			if dx * dx + dy * dy > r_cells * r_cells:
				continue
			var cx := center.x + dx
			var cy := center.y + dy
			if cx < 0 or cy < 0 or cx >= _grid_w or cy >= _grid_h:
				continue
			var idx := cy * _grid_w + cx
			if _cells[idx] == 0:
				continue
			_cells[idx] = 0
			destroyed_count += 1
			changed_any = true

	if destroyed_count > 0:
		GameStatistics.add_blocks_destroyed(destroyed_count)

	if changed_any:
		_try_mark_destroyed()
		_leftmost_solid_dirty = true
		_mask_dirty = true
		_row_leftmost_cache_dirty = true


func debug_destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	_row_leftmost_cache_dirty = true
	if _visual != null:
		_visual.visible = false
	fully_destroyed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not debug_destroy_on_key:
		pass
	else:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == debug_destroy_key:
				debug_destroy()
				return

	if debug_damage_on_click and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var lp := to_local(mb.position)
			apply_damage_circle_local(lp, debug_damage_radius_px)


func _ready() -> void:
	reset_target()


func _process(_delta: float) -> void:
	_update_mask_texture_if_dirty()
	_rebuild_row_leftmost_cache_if_dirty()


func _init_mask_visuals() -> void:
	if _visual == null:
		push_error("DestructibleTarget requires a child Sprite2D named 'Visual'.")
		return

	_visual.centered = true

	_mask_image = Image.create(_grid_w, _grid_h, false, Image.FORMAT_L8)
	_mask_image.fill(Color(1, 1, 1, 1))

	_mask_texture = ImageTexture.create_from_image(_mask_image)

	_visual.texture = _mask_texture
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Mask stays _grid_w x _grid_h; shader runs 8x8 marching-squares sub-cells per texel.
	_visual.scale = Vector2(cell_size_px, cell_size_px)

	var sm := ShaderMaterial.new()
	var sh: Shader = load("res://shaders/destructible_target_marching.gdshader")
	if sh == null:
		push_error("Failed to load res://shaders/destructible_target_marching.gdshader")
		return
	sm.shader = sh
	sm.set_shader_parameter("mask_tex", _mask_texture)
	sm.set_shader_parameter("solid_color", visual_color)
	_visual.material = sm
	clear_highlight()


func _update_mask_texture_if_dirty() -> void:
	if not _mask_dirty:
		return
	if _destroyed:
		return
	if _mask_image == null or _mask_texture == null:
		return

	for y in range(_grid_h):
		var row := y * _grid_w
		for x in range(_grid_w):
			_mask_image.set_pixel(x, y, Color(1, 1, 1, 1) if _cells[row + x] != 0 else Color(0, 0, 0, 1))

	_mask_texture.update(_mask_image)
	_mask_dirty = false


func cell_center_local(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * cell_size_px - target_size_px.x * 0.5,
		(float(cell.y) + 0.5) * cell_size_px - target_size_px.y * 0.5
	)


func is_cell_solid(cell: Vector2i) -> bool:
	if _destroyed:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_w or cell.y >= _grid_h:
		return false
	return _cells[cell.y * _grid_w + cell.x] != 0


func get_grid_width_cells() -> int:
	return _grid_w


## Max over rows of each row's rightmost empty column index; -1 if no empty cells (all solid).
func get_furthest_right_empty_cell_x() -> int:
	var best := -1
	for y in range(_grid_h):
		var row := y * _grid_w
		var row_best := -1
		for x in range(_grid_w - 1, -1, -1):
			if _cells[row + x] == 0:
				row_best = x
				break
		if row_best > best:
			best = row_best
	return best


func _rebuild_row_leftmost_cache_if_dirty() -> void:
	if not _row_leftmost_cache_dirty:
		return
	_row_leftmost_cache_dirty = false
	if _destroyed:
		_row_leftmost_x.clear()
		_row_leftmost_pos_local.clear()
		return
	if _row_leftmost_x.size() != _grid_h:
		_row_leftmost_x.resize(_grid_h)
		_row_leftmost_pos_local.resize(_grid_h)
	for y in range(_grid_h):
		var lx := -1
		var row := y * _grid_w
		for x in range(_grid_w):
			if _cells[row + x] != 0:
				lx = x
				break
		_row_leftmost_x[y] = lx
		if lx < 0:
			_row_leftmost_pos_local[y] = Vector2.ZERO
		else:
			_row_leftmost_pos_local[y] = cell_center_local(Vector2i(lx, y))


## Among each row's leftmost solid cell, returns grid cell whose cached center is closest to `from_local`.
func get_closest_row_leftmost_cell(from_local: Vector2) -> Vector2i:
	if _destroyed:
		return Vector2i(-1, -1)
	_rebuild_row_leftmost_cache_if_dirty()
	var best: Vector2i = Vector2i(-1, -1)
	var best_d2 := INF
	for y in range(_grid_h):
		var x := _row_leftmost_x[y]
		if x < 0:
			continue
		var d2 := _row_leftmost_pos_local[y].distance_squared_to(from_local)
		if d2 < best_d2:
			best_d2 = d2
			best = Vector2i(x, y)
	return best


func get_row_leftmost_cell_for_row(row_y: int) -> Vector2i:
	if row_y < 0 or row_y >= _grid_h:
		return Vector2i(-1, -1)
	_rebuild_row_leftmost_cache_if_dirty()
	var x := _row_leftmost_x[row_y]
	if x < 0:
		return Vector2i(-1, -1)
	return Vector2i(x, row_y)


func get_cached_row_leftmost_local_pos(row_y: int) -> Vector2:
	if row_y < 0 or row_y >= _grid_h:
		return Vector2.ZERO
	_rebuild_row_leftmost_cache_if_dirty()
	return _row_leftmost_pos_local[row_y]


const HIGHLIGHT_SHADER_MAX: int = 8


func set_highlight_cells(cells: Array[Vector2i]) -> void:
	if _visual == null:
		return
	var sm := _visual.material as ShaderMaterial
	if sm == null:
		return
	var packed := PackedVector2Array()
	var n := 0
	if not _destroyed:
		for c in cells:
			if n >= HIGHLIGHT_SHADER_MAX:
				break
			if c.x < 0 or c.y < 0:
				continue
			packed.append(Vector2(c.x, c.y))
			n += 1
	while packed.size() < HIGHLIGHT_SHADER_MAX:
		packed.append(Vector2(-1.0, -1.0))
	sm.set_shader_parameter("highlight_cells", packed)
	sm.set_shader_parameter("highlight_count", n)


func set_highlight_cell(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0:
		clear_highlight()
	else:
		set_highlight_cells([cell])


func clear_highlight() -> void:
	set_highlight_cells([])


func get_leftmost_solid_local_x() -> float:
	# Local-space X of the left edge of the leftmost undestroyed cell.
	if _leftmost_solid_dirty:
		_leftmost_solid_cell_x = _find_leftmost_solid_cell_x()
		_leftmost_solid_dirty = false
	return float(_leftmost_solid_cell_x) * cell_size_px - target_size_px.x * 0.5


func _find_leftmost_solid_cell_x() -> int:
	# Scan columns left->right; first column containing any solid cell wins.
	for x in range(_grid_w):
		for y in range(_grid_h):
			if _cells[y * _grid_w + x] != 0:
				return x
	return 0


func _init_grid() -> void:
	_grid_w = max(1, int(round(target_size_px.x / cell_size_px)))
	_grid_h = max(1, int(round(target_size_px.y / cell_size_px)))

	_cells = PackedByteArray()
	_cells.resize(_grid_w * _grid_h)

	if fill_solid_on_reset:
		for i in range(_cells.size()):
			_cells[i] = 1
	else:
		for i in range(_cells.size()):
			_cells[i] = 0

func _local_to_cell(local_pos: Vector2) -> Vector2i:
	var gx := int(floor((local_pos.x + target_size_px.x * 0.5) / cell_size_px))
	var gy := int(floor((local_pos.y + target_size_px.y * 0.5) / cell_size_px))
	return Vector2i(gx, gy)


func _try_mark_destroyed() -> void:
	if _destroyed:
		return

	for i in range(_cells.size()):
		if _cells[i] != 0:
			return

	_destroyed = true
	_row_leftmost_cache_dirty = true
	if _visual != null:
		_visual.visible = false
	fully_destroyed.emit()
