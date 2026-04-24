class_name HPBar
extends Node2D

const GROUP_NAME := &"hp_bars"

static var force_show_all: bool = false

@export var enabled: bool = true
@export var target_path: NodePath = NodePath("")
@export var offset: Vector2 = Vector2(0, -40)
@export var size: Vector2 = Vector2(40, 5)
@export var bg_color: Color = Color(0.15, 0.15, 0.15, 0.85)
@export var fill_color: Color = Color(0.25, 0.85, 0.35, 1.0)
@export var low_color: Color = Color(0.95, 0.25, 0.2, 1.0)
@export var border_color: Color = Color(0, 0, 0, 0.9)
@export var low_threshold: float = 0.3
@export var hide_when_full: bool = true
@export var hide_when_empty: bool = true

var _ratio: float = 1.0
var _target: Node


static func set_force_show_all(v: bool) -> void:
	force_show_all = v
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for n in tree.get_nodes_in_group(GROUP_NAME):
		if n is HPBar:
			(n as HPBar)._refresh_visibility()
			(n as HPBar).queue_redraw()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_target = _resolve_target()
	if _target != null and _target.has_signal(&"health_changed"):
		if not _target.health_changed.is_connected(_on_health_changed):
			_target.health_changed.connect(_on_health_changed)
	_sync_from_target_props()
	_refresh_visibility()
	queue_redraw()


func _resolve_target() -> Node:
	if target_path != NodePath():
		return get_node_or_null(target_path)
	return get_parent()


func _sync_from_target_props() -> void:
	if _target == null:
		return
	var mh: Variant = _target.get(&"max_health")
	var h: Variant = _target.get(&"health")
	if mh == null or h == null:
		return
	var max_h: int = int(mh)
	var cur: int = int(h)
	if max_h > 0:
		_ratio = clampf(float(cur) / float(max_h), 0.0, 1.0)
	else:
		_ratio = 0.0


func _on_health_changed(current: int, max_health: int) -> void:
	if max_health > 0:
		_ratio = clampf(float(current) / float(max_health), 0.0, 1.0)
	else:
		_ratio = 0.0
	_refresh_visibility()
	queue_redraw()


func _refresh_visibility() -> void:
	var should_show := (force_show_all or enabled) \
		and not (hide_when_full and _ratio >= 1.0 - 0.0001) \
		and not (hide_when_empty and _ratio <= 0.0001)
	visible = should_show
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var half := s * 0.5
	var r_bg := Rect2(offset - half, s)
	draw_rect(r_bg, bg_color, true)
	var fill_w: float = maxf(0.0, s.x * _ratio)
	if fill_w > 0.0:
		var fill_used := fill_color
		if _ratio <= low_threshold:
			fill_used = low_color
		var r_fill := Rect2(offset.x - half.x, offset.y - half.y, fill_w, s.y)
		draw_rect(r_fill, fill_used, true)
	draw_rect(r_bg, border_color, false, 1.0)
