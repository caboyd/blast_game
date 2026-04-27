extends Control

var _gold_spin: SpinBox
var _gold_give: Button
var _return_to_prep: Button
var _debug_visuals: CheckButton
var _viewport_info: Label


func _ready() -> void:
	_gold_spin = get_node_or_null("Panel/VBox/GoldRow/GoldSpin") as SpinBox
	_gold_give = get_node_or_null("Panel/VBox/GoldRow/GoldGive") as Button
	_return_to_prep = get_node_or_null("Panel/VBox/ReturnToPrep") as Button
	_debug_visuals = get_node_or_null("Panel/VBox/DebugVisuals") as CheckButton
	_viewport_info = get_node_or_null("../../GameplayBlock/AspectRatioContainer/ViewportFrame/ViewportInfo") as Label

	if _gold_give:
		_gold_give.pressed.connect(_on_gold_give_pressed)
	if _return_to_prep:
		_return_to_prep.pressed.connect(_on_return_to_prep_pressed)
	if _debug_visuals:
		_debug_visuals.toggled.connect(_on_debug_visuals_toggled)
	var on: bool = _debug_visuals.button_pressed if _debug_visuals else false
	_apply_debug_visuals(on)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _on_gold_give_pressed() -> void:
	if _gold_spin:
		GameStatistics.add_money(int(_gold_spin.value))


func _on_return_to_prep_pressed() -> void:
	GameSession.end_current_run_to_prep()


func _on_debug_visuals_toggled(pressed: bool) -> void:
	_apply_debug_visuals(pressed)


func _on_active_target_changed(_new_target: Node2D) -> void:
	if _debug_visuals:
		_apply_debug_visuals(_debug_visuals.button_pressed)


func _apply_debug_visuals(on: bool) -> void:
	GameStatistics.debug_world_visuals = on
	if _viewport_info != null:
		_viewport_info.visible = on
	# Re-paint so MiningShip clears when debug is off (toggle does not run _physics every frame for redraw).
	if get_tree() != null:
		for n in get_tree().get_nodes_in_group(&"mining_ship"):
			if n is CanvasItem:
				(n as CanvasItem).queue_redraw()
