extends CanvasLayer

## Global mining-mission HUD (fuel bar). Autoload: show while a mining planet scene is active.

const _BAR_SCENE := preload("res://scenes/ui/MiningFuelBar.tscn")

signal top_fuel_layout_changed

var _bar: Control


func _ready() -> void:
	layer = 1
	_bar = _BAR_SCENE.instantiate() as Control
	add_child(_bar)
	_bar.visible = false
	_bar.resized.connect(_emit_top_layout)
	_bar.item_rect_changed.connect(_emit_top_layout)


func _emit_top_layout() -> void:
	top_fuel_layout_changed.emit()


## Call from any mining planet root in `_ready()` so the fuel bar stays visible across planet scenes.
func attach_fuel_bar_for_mining_host(host: Node) -> void:
	if host == null:
		return
	set_mining_fuel_bar_active(true)
	if not host.tree_exiting.is_connected(_on_mining_host_exiting):
		host.tree_exiting.connect(_on_mining_host_exiting)


func _on_mining_host_exiting() -> void:
	set_mining_fuel_bar_active(false)


func set_mining_fuel_bar_active(active: bool) -> void:
	if _bar == null:
		return
	_bar.visible = active
	_emit_top_layout()


func get_top_fuel_band_px() -> float:
	if _bar == null or not _bar.visible:
		return 0.0
	var h: float = _bar.size.y
	if h <= 0.0:
		h = _bar.get_combined_minimum_size().y
	return maxf(h, 1.0)
