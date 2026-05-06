extends CanvasLayer

## Global mining-mission HUD (fuel bar + run stats pill). Autoload: show while a mining planet scene is active.

const _BAR_SCENE := preload("res://scenes/ui/TopMiningRunHud.tscn")

var _bar: Control


func _ready() -> void:
	layer = 10
	_bar = _BAR_SCENE.instantiate() as Control
	add_child(_bar)
	_bar.visible = false


## Call when overlays tied to the top HUD change layout so `TopMiningRunHud` refits its band height.
func notify_top_hud_layout_dirty() -> void:
	if _bar != null and _bar.has_method(&"refit_band_height"):
		_bar.refit_band_height()


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
