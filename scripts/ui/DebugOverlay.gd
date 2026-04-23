extends Control

const MAX_CLICK_DAMAGE := 1_000_000_000

var _prev_click_damage: int = -1
var _syncing_radius: bool = false

@onready var _conveyor: TargetConveyor = get_node("%TargetConveyor") as TargetConveyor
@onready var _radius_spin: SpinBox = $Panel/VBox/RadiusRow/RadiusSpin
@onready var _max_damage_btn: CheckButton = $Panel/VBox/MaxDamage
@onready var _gold_spin: SpinBox = $Panel/VBox/GoldRow/GoldSpin
@onready var _gold_give: Button = $Panel/VBox/GoldRow/GoldGive
@onready var _suicide: Button = $Panel/VBox/Suicide
@onready var _debug_visuals: CheckButton = $Panel/VBox/DebugVisuals
@onready var _show_attack_ranges: CheckButton = $Panel/VBox/ShowAttackRanges
@onready var _viewport_info: Label = get_node("../../GameplayBlock/AspectRatioContainer/ViewportFrame/ViewportInfo") as Label


func _ready() -> void:
	_radius_spin.value_changed.connect(_on_radius_changed)
	_max_damage_btn.toggled.connect(_on_max_damage_toggled)
	_gold_give.pressed.connect(_on_gold_give_pressed)
	if _suicide:
		_suicide.pressed.connect(_on_suicide_pressed)
	_debug_visuals.toggled.connect(_on_debug_visuals_toggled)
	_show_attack_ranges.toggled.connect(_on_show_attack_ranges_toggled)
	visibility_changed.connect(_on_visibility_changed)
	if _conveyor != null and not _conveyor.active_target_changed.is_connected(_on_active_target_changed):
		_conveyor.active_target_changed.connect(_on_active_target_changed)
	_apply_debug_visuals(_debug_visuals.button_pressed)
	_apply_attack_range_debug(_show_attack_ranges.button_pressed)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	if visible:
		_sync_radius_from_stats()


func _sync_radius_from_stats() -> void:
	_syncing_radius = true
	_radius_spin.value = GameStatistics.click_radius_cells
	_syncing_radius = false


func _on_radius_changed(value: float) -> void:
	if _syncing_radius:
		return
	GameStatistics.set_click_radius_cells(int(value))


func _on_max_damage_toggled(pressed: bool) -> void:
	if pressed:
		_prev_click_damage = GameStatistics.click_damage
		GameStatistics.set_click_damage(MAX_CLICK_DAMAGE)
	else:
		var restore: int = _prev_click_damage
		if restore < 1:
			restore = 1
		GameStatistics.set_click_damage(restore)


func _on_gold_give_pressed() -> void:
	GameStatistics.add_money(int(_gold_spin.value))


func _on_suicide_pressed() -> void:
	var ship := get_tree().get_first_node_in_group(&"player_ship") as Ship
	if ship == null:
		return
	ship.apply_damage(ship.max_health)


func _on_debug_visuals_toggled(pressed: bool) -> void:
	_apply_debug_visuals(pressed)


func _on_active_target_changed(_new_target: Node2D) -> void:
	_apply_debug_visuals(_debug_visuals.button_pressed)


func _apply_debug_visuals(on: bool) -> void:
	if _viewport_info != null:
		_viewport_info.visible = on
	if _conveyor == null:
		return
	for t in [_conveyor.front_target, _conveyor.next_target]:
		if t == null:
			continue
		var bounds: Node = t.get_node_or_null("DebugBounds")
		if bounds != null:
			bounds.visible = on


func _on_show_attack_ranges_toggled(pressed: bool) -> void:
	_apply_attack_range_debug(pressed)


func _apply_attack_range_debug(on: bool) -> void:
	Turret.debug_show_attack_ranges = on
	for n in get_tree().get_nodes_in_group(&"enemies"):
		if n is Enemy:
			(n as Enemy).queue_redraw()
	for n in get_tree().get_nodes_in_group(&"cannon_turrets"):
		if n is CannonTurret:
			(n as CannonTurret).queue_redraw()
