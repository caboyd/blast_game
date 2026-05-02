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
var _fuel_ovrd: CheckBox
var _fuel_spin: SpinBox
var _speed_ovrd: CheckBox
var _speed_spin: SpinBox
var _mine_ovrd: CheckBox
var _mine_spin: SpinBox
var _mine_rate_ovrd: CheckBox
var _mine_rate_spin: SpinBox
var _drill_ovrd: CheckBox
var _drill_spin: SpinBox
var _vision_ovrd: CheckBox
var _vision_spin: SpinBox
var _turn_ovrd: CheckBox
var _turn_spin: SpinBox


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
	_fuel_ovrd = get_node_or_null("Panel/VBox/DbgFuelRow/DbgFuelOvrd") as CheckBox
	_fuel_spin = get_node_or_null("Panel/VBox/DbgFuelRow/DbgFuelSpin") as SpinBox
	_speed_ovrd = get_node_or_null("Panel/VBox/DbgSpeedRow/DbgSpeedOvrd") as CheckBox
	_speed_spin = get_node_or_null("Panel/VBox/DbgSpeedRow/DbgSpeedSpin") as SpinBox
	_mine_ovrd = get_node_or_null("Panel/VBox/DbgMineRow/DbgMineOvrd") as CheckBox
	_mine_spin = get_node_or_null("Panel/VBox/DbgMineRow/DbgMineSpin") as SpinBox
	_mine_rate_ovrd = get_node_or_null("Panel/VBox/DbgMineRateRow/DbgMineRateOvrd") as CheckBox
	_mine_rate_spin = get_node_or_null("Panel/VBox/DbgMineRateRow/DbgMineRateSpin") as SpinBox
	_drill_ovrd = get_node_or_null("Panel/VBox/DbgDrillRangeRow/DbgDrillOvrd") as CheckBox
	_drill_spin = get_node_or_null("Panel/VBox/DbgDrillRangeRow/DbgDrillSpin") as SpinBox
	_vision_ovrd = get_node_or_null("Panel/VBox/DbgVisionRow/DbgVisionOvrd") as CheckBox
	_vision_spin = get_node_or_null("Panel/VBox/DbgVisionRow/DbgVisionSpin") as SpinBox
	_turn_ovrd = get_node_or_null("Panel/VBox/DbgTurnRow/DbgTurnOvrd") as CheckBox
	_turn_spin = get_node_or_null("Panel/VBox/DbgTurnRow/DbgTurnSpin") as SpinBox

	if _gold_give:
		_gold_give.pressed.connect(_on_gold_give_pressed)
	if _gold_spin:
		_gold_spin.value = float(GameStatistics.debug_menu_gold_give_spin)
		_gold_spin.value_changed.connect(_on_debug_gold_spin_changed)
	if _return_to_prep:
		_return_to_prep.pressed.connect(_on_return_to_prep_pressed)
	if _debug_visuals:
		_debug_visuals.button_pressed = GameStatistics.debug_world_visuals
		_debug_visuals.toggled.connect(_on_debug_visuals_toggled)
	if _disable_fog:
		_disable_fog.button_pressed = GameStatistics.debug_fog_disabled
		_disable_fog.toggled.connect(_on_disable_fog_toggled)
	if _zoom_out:
		_zoom_out.pressed.connect(_on_zoom_out_pressed)
	if _zoom_in:
		_zoom_in.pressed.connect(_on_zoom_in_pressed)
	_wire_debug_vehicle_overrides()
	var on: bool = _debug_visuals.button_pressed if _debug_visuals else false
	_apply_debug_visuals(on)
	_refresh_zoom_value()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_adjust_debug_zoom(1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_debug_zoom(-1)
				get_viewport().set_input_as_handled()


func _on_gold_give_pressed() -> void:
	if _gold_spin:
		GameStatistics.add_money(int(_gold_spin.value))


func _on_debug_gold_spin_changed(v: float) -> void:
	GameStatistics.debug_menu_gold_give_spin = int(roundf(v))
	GameStatistics.save_debug_preferences()


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


func _wire_debug_vehicle_overrides() -> void:
	if _fuel_ovrd:
		_fuel_ovrd.button_pressed = GameStatistics.debug_fuel_max_override_enabled
		_fuel_ovrd.toggled.connect(_on_dbg_fuel_ovrd_toggled)
	if _fuel_spin:
		_fuel_spin.value = GameStatistics.debug_fuel_max_override_value
		_fuel_spin.value_changed.connect(_on_dbg_fuel_spin_changed)
	if _speed_ovrd:
		_speed_ovrd.button_pressed = GameStatistics.debug_move_speed_override_enabled
		_speed_ovrd.toggled.connect(_on_dbg_speed_ovrd_toggled)
	if _speed_spin:
		_speed_spin.value = GameStatistics.debug_move_speed_override_value
		_speed_spin.value_changed.connect(_on_dbg_speed_spin_changed)
	if _mine_ovrd:
		_mine_ovrd.button_pressed = GameStatistics.debug_mine_damage_override_enabled
		_mine_ovrd.toggled.connect(_on_dbg_mine_ovrd_toggled)
	if _mine_spin:
		_mine_spin.value = GameStatistics.debug_mine_damage_override_value
		_mine_spin.value_changed.connect(_on_dbg_mine_spin_changed)
	if _mine_rate_ovrd:
		_mine_rate_ovrd.button_pressed = GameStatistics.debug_mine_interval_override_enabled
		_mine_rate_ovrd.toggled.connect(_on_dbg_mine_rate_ovrd_toggled)
	if _mine_rate_spin:
		_mine_rate_spin.value = GameStatistics.debug_mine_interval_override_value
		_mine_rate_spin.value_changed.connect(_on_dbg_mine_rate_spin_changed)
	if _drill_ovrd:
		_drill_ovrd.button_pressed = GameStatistics.debug_drill_range_game_px_override_enabled
		_drill_ovrd.toggled.connect(_on_dbg_drill_ovrd_toggled)
	if _drill_spin:
		_drill_spin.value = GameStatistics.debug_drill_range_game_px_override_value
		_drill_spin.value_changed.connect(_on_dbg_drill_spin_changed)
	if _vision_ovrd:
		_vision_ovrd.button_pressed = GameStatistics.debug_vision_radius_cells_override_enabled
		_vision_ovrd.toggled.connect(_on_dbg_vision_ovrd_toggled)
	if _vision_spin:
		_vision_spin.value = float(GameStatistics.debug_vision_radius_cells_override_value)
		_vision_spin.value_changed.connect(_on_dbg_vision_spin_changed)
	if _turn_ovrd:
		_turn_ovrd.button_pressed = GameStatistics.debug_turn_rate_rad_s_override_enabled
		_turn_ovrd.toggled.connect(_on_dbg_turn_ovrd_toggled)
	if _turn_spin:
		_turn_spin.value = GameStatistics.debug_turn_rate_rad_s_override_value
		_turn_spin.value_changed.connect(_on_dbg_turn_spin_changed)


func _on_dbg_fuel_ovrd_toggled(pressed: bool) -> void:
	if _fuel_spin:
		GameStatistics.notify_debug_fuel_max_override(pressed, float(_fuel_spin.value))


func _on_dbg_fuel_spin_changed(v: float) -> void:
	if _fuel_ovrd and _fuel_ovrd.button_pressed:
		GameStatistics.notify_debug_fuel_max_override(true, float(v))


func _on_dbg_speed_ovrd_toggled(pressed: bool) -> void:
	if _speed_spin:
		GameStatistics.notify_debug_move_speed_override(pressed, float(_speed_spin.value))


func _on_dbg_speed_spin_changed(v: float) -> void:
	if _speed_ovrd and _speed_ovrd.button_pressed:
		GameStatistics.notify_debug_move_speed_override(true, float(v))


func _on_dbg_mine_ovrd_toggled(pressed: bool) -> void:
	if _mine_spin:
		GameStatistics.notify_debug_mine_damage_override(pressed, float(_mine_spin.value))


func _on_dbg_mine_spin_changed(v: float) -> void:
	if _mine_ovrd and _mine_ovrd.button_pressed:
		GameStatistics.notify_debug_mine_damage_override(true, float(v))


func _on_dbg_mine_rate_ovrd_toggled(pressed: bool) -> void:
	if _mine_rate_spin:
		GameStatistics.notify_debug_mine_interval_override(pressed, float(_mine_rate_spin.value))


func _on_dbg_mine_rate_spin_changed(v: float) -> void:
	if _mine_rate_ovrd and _mine_rate_ovrd.button_pressed:
		GameStatistics.notify_debug_mine_interval_override(true, float(v))


func _on_dbg_drill_ovrd_toggled(pressed: bool) -> void:
	if _drill_spin:
		GameStatistics.notify_debug_drill_range_game_px_override(pressed, float(_drill_spin.value))


func _on_dbg_drill_spin_changed(v: float) -> void:
	if _drill_ovrd and _drill_ovrd.button_pressed:
		GameStatistics.notify_debug_drill_range_game_px_override(true, float(v))


func _on_dbg_vision_ovrd_toggled(pressed: bool) -> void:
	if _vision_spin:
		GameStatistics.notify_debug_vision_radius_cells_override(
			pressed,
			int(round(float(_vision_spin.value)))
		)


func _on_dbg_vision_spin_changed(v: float) -> void:
	if _vision_ovrd and _vision_ovrd.button_pressed:
		GameStatistics.notify_debug_vision_radius_cells_override(true, int(round(v)))


func _on_dbg_turn_ovrd_toggled(pressed: bool) -> void:
	if _turn_spin:
		GameStatistics.notify_debug_turn_rate_rad_s_override(pressed, float(_turn_spin.value))


func _on_dbg_turn_spin_changed(v: float) -> void:
	if _turn_ovrd and _turn_ovrd.button_pressed:
		GameStatistics.notify_debug_turn_rate_rad_s_override(true, float(v))


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
		for w in get_tree().get_nodes_in_group(&"mining_world"):
			if w is MiningWorld:
				(w as MiningWorld).refresh_chunk_border_debug()
	GameStatistics.save_debug_preferences()


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
