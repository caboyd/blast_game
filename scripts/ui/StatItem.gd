extends PanelContainer
class_name StatItem

@export var stat_id: StringName = &"blocks"
@export var icon_texture: Texture2D
@export var display_name: String = "":
	set(v):
		display_name = v
		if _name_label:
			_name_label.text = v

@export var value_text: String = "0":
	set(v):
		value_text = v
		if _value_label:
			_value_label.text = v

@onready var _icon: TextureRect = $HBox/Icon
@onready var _name_label: Label = $HBox/Labels/NameLabel
@onready var _value_label: Label = $HBox/Labels/ValueLabel


func _ready() -> void:
	if icon_texture:
		_icon.texture = icon_texture
		_icon.visible = true
	else:
		_icon.texture = null
		_icon.visible = false
	_name_label.text = display_name
	_value_label.text = value_text


func set_value(text: String) -> void:
	value_text = text
