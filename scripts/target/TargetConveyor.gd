class_name TargetConveyor
extends Node2D

signal active_target_changed(new_target: Node2D)

@export var target_scene: PackedScene
@export var active_target_position: Vector2 = Vector2.ZERO
@export var slide_duration_s: float = 0.0
@export var follow_tween_duration_s: float = 2.25

var front_target: Node2D
var next_target: Node2D
var _completed_front_targets: int = 0
var _sliding: bool = false
var _follow_tween: Tween
var _follow_target_pos: Vector2 = Vector2.INF
var _follow_instant_once: bool = true


func ensure_targets_spawned() -> void:
	if front_target != null and next_target != null:
		return
	_spawn_initial()


func get_active_target() -> Node2D:
	return front_target


func begin_swap_if_front_destroyed() -> void:
	if _sliding:
		return
	if front_target == null or next_target == null:
		return

	var dt := front_target as DestructibleTarget
	if dt == null:
		return
	if not dt.is_destroyed():
		return

	_begin_slide_swap()


func _ready() -> void:
	if target_scene == null:
		push_warning("TargetConveyor.target_scene is not set; targets will not spawn.")
		return
	_spawn_initial()


func _physics_process(_delta: float) -> void:
	begin_swap_if_front_destroyed()
	_update_follow()
	_update_game_statistics_depth()


func _stack_spacing_x() -> float:
	var dt := front_target as DestructibleTarget
	if dt == null:
		return 0.0
	return dt.target_size_px.x


func _update_game_statistics_depth() -> void:
	if front_target == null or next_target == null:
		return
	var dt_f := front_target as DestructibleTarget
	var dt_n := next_target as DestructibleTarget
	if dt_f == null:
		return
	var w: int = dt_f.get_grid_width_cells()
	var base: int = _completed_front_targets * w
	var local_front: int = dt_f.get_furthest_right_empty_cell_x()
	var instant: int = base + maxi(0, local_front)
	# Next slab starts one full grid width deeper; count it when it already has empty cells.
	if dt_n != null:
		var local_next: int = dt_n.get_furthest_right_empty_cell_x()
		if local_next >= 0:
			var from_next: int = (_completed_front_targets + 1) * w + local_next
			instant = maxi(instant, from_next)
	GameStatistics.update_depth_in_cells(instant)


func _enforce_stack_spacing() -> void:
	if front_target == null or next_target == null:
		return
	var w := _stack_spacing_x()
	if w <= 0.0:
		return
	# Next stays one full tile to the right of front; front local X never forced to 0 after spawn
	# so promoted "second" target does not jump left on swap.
	next_target.position = Vector2(front_target.position.x + w, 0.0)


func _update_follow() -> void:
	if front_target == null or next_target == null:
		return
	var dt := front_target as DestructibleTarget
	if dt == null:
		return

	_enforce_stack_spacing()

	# Keep the leftmost remaining edge of the FRONT target exactly at screen midpoint.
	var vr := get_viewport().get_visible_rect()
	var screen_mid_x := (vr.position.x + vr.size.x * 0.5)

	var leftmost_local_x := dt.get_leftmost_solid_local_x()
	# left edge world = conveyor.global_x + front_local_x + leftmost_local_x
	var desired_x := screen_mid_x - (front_target.position.x + leftmost_local_x)

	# Preserve existing vertical placement behavior.
	var desired_y := active_target_position.y

	var desired := Vector2(desired_x, desired_y)
	if _follow_target_pos.is_finite() and desired.is_equal_approx(_follow_target_pos):
		return
	_follow_target_pos = desired

	if is_instance_valid(_follow_tween):
		_follow_tween.kill()

	if _follow_instant_once:
		_follow_instant_once = false
		global_position = desired
		return

	_follow_tween = create_tween()
	_follow_tween.set_trans(Tween.TRANS_SINE)
	_follow_tween.set_ease(Tween.EASE_OUT)
	_follow_tween.tween_property(self, "global_position", desired, follow_tween_duration_s)


func _spawn_initial() -> void:
	front_target = target_scene.instantiate() as Node2D
	next_target = target_scene.instantiate() as Node2D

	add_child(front_target)
	add_child(next_target)

	global_position = active_target_position
	front_target.position = Vector2.ZERO
	_enforce_stack_spacing()
	_follow_instant_once = true

	_wire_target(front_target)
	_wire_target(next_target)
	_wire_neighbors()

	active_target_changed.emit(front_target)


func _wire_target(t: Node2D) -> void:
	var dt := t as DestructibleTarget
	if dt == null:
		return
	dt.fully_destroyed.connect(_on_front_fully_destroyed.bind(dt))


func _wire_neighbors() -> void:
	var f := front_target as DestructibleTarget
	var n := next_target as DestructibleTarget
	if f != null:
		f.set_neighbors(null, n)
	if n != null:
		n.set_neighbors(f, null)


func _on_front_fully_destroyed(dt: DestructibleTarget) -> void:
	if dt != front_target:
		return
	_begin_slide_swap()


func _begin_slide_swap() -> void:
	if _sliding:
		return
	_sliding = true

	var old_front := front_target
	var new_front := next_target

	# Ping-pong buffer: recycle the old front as the new "next".
	front_target = new_front
	next_target = old_front

	if is_instance_valid(next_target):
		var dt := next_target as DestructibleTarget
		if dt != null:
			# Avoid any visible tweening on the recycled target as it jumps behind.
			dt.set_target_visible(false)
			dt.reset_target()
			dt.call_deferred("set_target_visible", true)

	# New front keeps local position; recycled target slots in directly behind (to the right).
	_enforce_stack_spacing()
	_wire_neighbors()
	_update_follow()

	_sliding = false
	_completed_front_targets += 1
	active_target_changed.emit(front_target)
