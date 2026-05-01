class_name GlobalPartStatEffect
extends GlobalPartEffect

## Modifies a numeric ship/part stat with the same multiply/add semantics as upgrades (level = 1).

@export_enum(
	"mine_damage_per_tick",
	"move_speed_px_s",
	"fuel_max",
	"fuel_drain_per_second",
)
var stat: String = "mine_damage_per_tick"

@export_enum("add", "multiply") var operation: String = "multiply"
@export var value: float = 1.0
@export var clamp_min: float = -1e20
@export var clamp_max: float = 1e20
