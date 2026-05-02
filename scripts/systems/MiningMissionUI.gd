extends CanvasLayer

## Global mining-mission HUD (fuel bar + run stats pill). Autoload: show while a mining planet scene is active.

const _BAR_SCENE := preload("res://scenes/ui/TopMiningRunHud.tscn")

signal top_fuel_layout_changed

var _bar: Control


func _ready() -> void:
	layer = 10
	_bar = _BAR_SCENE.instantiate() as Control
	add_child(_bar)
	_bar.visible = false
	_bar.resized.connect(_emit_top_layout)
	_bar.item_rect_changed.connect(_emit_top_layout)


func _emit_top_layout() -> void:
	top_fuel_layout_changed.emit()


## Call when a child of `TopMiningRunHud` changes height so planets can re-read `get_top_fuel_band_px()`.
func notify_top_hud_layout_dirty() -> void:
	if _bar != null and _bar.has_method(&"refit_band_height"):
		_bar.refit_band_height()
	_emit_top_layout()


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
