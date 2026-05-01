extends Control

var _gold_spin: SpinBox
var _gold_give: Button
var _return_to_prep: Button
var _debug_visuals: CheckButton
var _disable_fog: CheckButton
var _zoom_out: Button
var _zoom_in: Button
var _zoom_value: Label
var _viewport_info: Label


func _ready() -> void:
	_gold_spin = get_node_or_null("Panel/VBox/GoldRow/GoldSpin") as SpinBox
	_gold_give = get_node_or_null("Panel/VBox/GoldRow/GoldGive") as Button
	_return_to_prep = get_node_or_null("Panel/VBox/ReturnToPrep") as Button
	_debug_visuals = get_node_or_null("Panel/VBox/DebugVisuals") as CheckButton
	_disable_fog = get_node_or_null("Panel/VBox/DisableFog") as CheckButton
	_zoom_out = get_node_or_null("Panel/VBox/ZoomRow/ZoomOut") as Button
	_zoom_in = get_node_or_null("Panel/VBox/ZoomRow/ZoomIn") as Button
	_zoom_value = get_node_or_null("Panel/VBox/ZoomRow/ZoomValue") as Label
	_viewport_info = get_node_or_null("../../GameplayBlock/AspectRatioContainer/ViewportFrame/ViewportInfo") as Label

	if _gold_give:
		_gold_give.pressed.connect(_on_gold_give_pressed)
	if _return_to_prep:
		_return_to_prep.pressed.connect(_on_return_to_prep_pressed)
	if _debug_visuals:
		_debug_visuals.toggled.connect(_on_debug_visuals_toggled)
	if _disable_fog:
		_disable_fog.button_pressed = GameStatistics.debug_fog_disabled
		_disable_fog.toggled.connect(_on_disable_fog_toggled)
	if _zoom_out:
		_zoom_out.pressed.connect(_on_zoom_out_pressed)
	if _zoom_in:
		_zoom_in.pressed.connect(_on_zoom_in_pressed)
	var on: bool = _debug_visuals.button_pressed if _debug_visuals else false
	_apply_debug_visuals(on)
	_refresh_zoom_value()


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


func _on_disable_fog_toggled(pressed: bool) -> void:
	GameStatistics.set_debug_fog_disabled(pressed)


func _on_zoom_out_pressed() -> void:
	_adjust_debug_zoom(-1)


func _on_zoom_in_pressed() -> void:
	_adjust_debug_zoom(1)


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
		for n in get_tree().get_nodes_in_group(&"pickup_debug_redraw"):
			if n is CanvasItem:
				(n as CanvasItem).queue_redraw()


func _adjust_debug_zoom(step_delta: int) -> void:
	var host := _debug_host()
	if host != null and host.has_method(&"adjust_debug_camera_zoom"):
		host.call(&"adjust_debug_camera_zoom", step_delta)
	_refresh_zoom_value()


func _refresh_zoom_value() -> void:
	if _zoom_value == null:
		return
	var zoom_multiplier: float = 1.0
	var host := _debug_host()
	if host != null and host.has_method(&"get_debug_camera_zoom_multiplier"):
		zoom_multiplier = float(host.call(&"get_debug_camera_zoom_multiplier"))
	_zoom_value.text = "%d%%" % int(roundf(zoom_multiplier * 100.0))


func _debug_host() -> Node:
	var p := get_parent()
	if p == null:
		return null
	return p.get_parent()
