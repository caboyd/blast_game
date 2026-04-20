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


func apply_damage_circle_local(local_pos: Vector2, radius_px: float) -> void:
	if _destroyed:
		return

	var r_cells := int(ceil(radius_px / cell_size_px))
	var center := _local_to_cell(local_pos)

	var changed_any := false
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
			changed_any = true

	if changed_any:
		_try_mark_destroyed()
		_leftmost_solid_dirty = true
		_mask_dirty = true


func debug_destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
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
	if _visual != null:
		_visual.visible = false
	fully_destroyed.emit()
