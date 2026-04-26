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

	if not front_target.has_method(&"is_destroyed"):
		return
	if not front_target.call(&"is_destroyed"):
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
	if front_target == null:
		return 0.0
	var ts = front_target.get(&"target_size_px")
	if ts is Vector2:
		return (ts as Vector2).x
	return 0.0


func _update_game_statistics_depth() -> void:
	if front_target == null or next_target == null:
		return
	var dt_f := front_target
	var dt_n := next_target
	if not dt_f.has_method(&"get_grid_width_cells"):
		return
	var w: int = int(dt_f.call(&"get_grid_width_cells"))
	var base: int = _completed_front_targets * w
	var local_front: int = int(dt_f.call(&"get_furthest_right_empty_cell_x"))
	var instant: int = base + maxi(0, local_front)
	if dt_n != null and dt_n.has_method(&"get_furthest_right_empty_cell_x"):
		var local_next: int = int(dt_n.call(&"get_furthest_right_empty_cell_x"))
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
	next_target.position = Vector2(front_target.position.x + w, 0.0)


func _update_follow() -> void:
	if front_target == null or next_target == null:
		return
	var dt := front_target
	if not dt.has_method(&"get_leftmost_solid_local_x"):
		return

	_enforce_stack_spacing()

	var screen_mid_x: float
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		screen_mid_x = cam.get_screen_center_position().x
	else:
		var vr := get_viewport().get_visible_rect()
		screen_mid_x = vr.position.x + vr.size.x * 0.5

	var leftmost_local_x: float = float(dt.call(&"get_leftmost_solid_local_x"))
	var desired_x := screen_mid_x - (front_target.position.x + leftmost_local_x)
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
	if t == null:
		return
	if t.has_signal(&"fully_destroyed"):
		t.fully_destroyed.connect(_on_front_fully_destroyed.bind(t))


func _wire_neighbors() -> void:
	var f := front_target
	var n := next_target
	if f != null and f.has_method(&"set_neighbors"):
		f.call(&"set_neighbors", null, n)
	if n != null and n.has_method(&"set_neighbors"):
		n.call(&"set_neighbors", f, null)


func _on_front_fully_destroyed(dt: Node2D) -> void:
	if dt != front_target:
		return
	_begin_slide_swap()


func _begin_slide_swap() -> void:
	if _sliding:
		return
	_sliding = true

	var old_front := front_target
	var new_front := next_target

	front_target = new_front
	next_target = old_front

	if is_instance_valid(next_target):
		var t := next_target
		if t.has_method(&"set_target_visible"):
			t.call(&"set_target_visible", false)
		if t.has_method(&"reset_target"):
			t.call(&"reset_target")
		if t.has_method(&"set_target_visible"):
			t.call_deferred(&"set_target_visible", true)

	_enforce_stack_spacing()
	_wire_neighbors()
	_update_follow()

	_sliding = false
	_completed_front_targets += 1
	active_target_changed.emit(front_target)
