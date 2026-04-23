class_name TurretSlotRing
extends Node2D

@onready var _ring: Polygon2D = $Ring
@onready var _label: Label = $SizeLabel


func _ready() -> void:
	call_deferred("_center_label")


func apply_stub_style(stub: bool) -> void:
	_ring.color = Color(0.5, 0.5, 0.5, 0.08) if stub else Color(1, 1, 1, 0.12)
	_label.modulate = Color(1, 1, 1, 0.35) if stub else Color(1, 1, 1, 0.85)


func _center_label() -> void:
	await get_tree().process_frame
	var sz := _label.get_minimum_size()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.position = -0.5 * sz
