extends PanelContainer
class_name UpgradeItem

signal purchase_pressed(upgrade_id: StringName)

const _BG := Color(0.290196, 0.180392, 0.117647, 1)
const _BG_HOVER := Color(0.36, 0.24, 0.16, 1)
const _BG_PRESSED := Color(0.22, 0.14, 0.09, 1)
const _NAME_COLOR := Color(0.96, 0.9, 0.78, 1)
const _NAME_COLOR_DISABLED := Color(0.55, 0.5, 0.48, 0.85)
const _COST_COLOR := Color(0.298039, 0.686275, 0.313726, 1)
const _COST_COLOR_DISABLED := Color(0.35, 0.42, 0.38, 0.75)
const _BUY_FONT := Color(0.29, 0.18, 0.12, 1)
const _BUY_FONT_DISABLED := Color(0.4, 0.38, 0.36, 0.9)
const _MOD_DISABLED := Color(0.72, 0.7, 0.74, 0.88)

@export var upgrade_id: StringName = &"melter"
@export var display_name: String = "MELTER"
@export var cost: int = 1000
@export var icon_texture: Texture2D
## When true, row is non-interactive: muted visuals, no hover/press.
@export var upgrade_disabled: bool = false

@onready var _hit: Control = $HBox
@onready var _right_col: Control = $HBox/RightCol
@onready var _icon: TextureRect = $HBox/Icon
@onready var _name_label: Label = $HBox/NameLabel
@onready var _cost_label: Label = $HBox/RightCol/CostLabel
@onready var _buy_button: Button = $HBox/RightCol/BuyButton

var _hover: bool = false
var _press_armed: bool = false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_buy_button.focus_mode = Control.FOCUS_NONE
	_wire_row_input_targets()
	_hit.mouse_entered.connect(_on_mouse_entered)
	_hit.mouse_exited.connect(_on_mouse_exited)
	_hit.gui_input.connect(_on_hit_gui_input)
	_apply_config_to_nodes()
	_apply_interactive_appearance()


func _wire_row_input_targets() -> void:
	# HBox receives hover/clicks for the full row; leaves ignore so events hit the row.
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	for c in [_icon, _name_label, _right_col, _cost_label, _buy_button]:
		if c:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_hit_gui_input(event: InputEvent) -> void:
	if upgrade_disabled:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			# Only consume primary clicks so wheel reaches parent ScrollContainer.
			if mb.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_armed = true
			else:
				if _press_armed and _hit.get_global_rect().has_point(get_global_mouse_position()):
					purchase_pressed.emit(upgrade_id)
				_press_armed = false
			_refresh_panel_style()
			accept_event()
		# Wheel / middle / other buttons: do not accept — let ScrollContainer scroll.


func _on_mouse_entered() -> void:
	if upgrade_disabled:
		return
	_hover = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_refresh_panel_style()


func _on_mouse_exited() -> void:
	_hover = false
	_press_armed = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_refresh_panel_style()


func _apply_config_to_nodes() -> void:
	_name_label.text = display_name
	if upgrade_disabled:
		_cost_label.text = "—"
		_buy_button.text = "LOCKED"
	else:
		_cost_label.text = "%d$" % cost
		_buy_button.text = "BUY"
	if icon_texture:
		_icon.texture = icon_texture
		_icon.visible = true
	else:
		_icon.texture = null
		_icon.visible = false


func _apply_interactive_appearance() -> void:
	if upgrade_disabled:
		modulate = _MOD_DISABLED
		_name_label.add_theme_color_override("font_color", _NAME_COLOR_DISABLED)
		_cost_label.add_theme_color_override("font_color", _COST_COLOR_DISABLED)
		_buy_button.add_theme_color_override("font_color", _BUY_FONT_DISABLED)
		_buy_button.disabled = true
		_buy_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		remove_theme_stylebox_override("panel")
		var flat := StyleBoxFlat.new()
		flat.bg_color = _BG.darkened(0.12)
		flat.set_corner_radius_all(4)
		flat.set_content_margin_all(6)
		add_theme_stylebox_override("panel", flat)
	else:
		modulate = Color.WHITE
		_name_label.add_theme_color_override("font_color", _NAME_COLOR)
		_cost_label.add_theme_color_override("font_color", _COST_COLOR)
		_buy_button.add_theme_color_override("font_color", _BUY_FONT)
		_buy_button.disabled = false
		_buy_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_refresh_panel_style()


func _make_panel_style(hover: bool, pressed: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if pressed:
		s.bg_color = _BG_PRESSED
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 2
		s.shadow_offset = Vector2(0, 1)
		s.set_content_margin(SIDE_TOP, 7)
		s.set_content_margin(SIDE_LEFT, 7)
		s.set_content_margin(SIDE_BOTTOM, 5)
		s.set_content_margin(SIDE_RIGHT, 5)
	elif hover:
		s.bg_color = _BG_HOVER
		s.shadow_color = Color(0, 0, 0, 0.4)
		s.shadow_size = 5
		s.shadow_offset = Vector2(2, 3)
	else:
		s.bg_color = _BG
		s.shadow_color = Color(0, 0, 0, 0.32)
		s.shadow_size = 4
		s.shadow_offset = Vector2(2, 2)
	if not pressed:
		s.set_corner_radius_all(4)
		s.set_content_margin_all(6)
	else:
		s.set_corner_radius_all(4)
	return s


func _refresh_panel_style() -> void:
	if upgrade_disabled:
		return
	add_theme_stylebox_override("panel", _make_panel_style(_hover, _press_armed))


func apply_config(id: StringName, name_str: String, cost_value: int, tex: Texture2D, disabled: bool = false) -> void:
	upgrade_id = id
	display_name = name_str
	cost = cost_value
	icon_texture = tex
	upgrade_disabled = disabled
	if is_node_ready():
		_apply_config_to_nodes()
		_apply_interactive_appearance()
