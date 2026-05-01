class_name GlobalPartEffect
extends Resource

## Stat modified by this global part. Uses same multiply/add semantics as upgrades (level = 1).
@export_enum(
	"mine_damage_per_tick",
	"move_speed_px_s",
	"fuel_max",
	"fuel_drain_per_second",
	"movement_effect"
)
var stat: String = "mine_damage_per_tick"

@export_enum("add", "multiply") var operation: String = "multiply"
@export var value: float = 1.0

## Used when `stat` is `movement_effect`: every `movement_effect_every_s`, translation is scaled for `movement_effect_duration_s`.
@export var movement_effect_every_s: float = 0.0
@export var movement_effect_duration_s: float = 0.0

## During that window: `effective_move_speed × movement_effect_speed_multiplier`. Clamped to [0, 1]: 0 = full stop, 1 = no slowdown.
@export_range(0.0, 1.0) var movement_effect_speed_multiplier: float = 0.0
@export var clamp_min: float = -1e20
@export var clamp_max: float = 1e20


static func normalize_stat_id(raw: Variant) -> StringName:
	var s: String = str(raw).strip_edges()
	if s.is_empty():
		return &""
	var c: int = s.rfind(":")
	if c >= 0 and c < s.length() - 1:
		s = s.substr(c + 1).strip_edges()
	return StringName(s)
