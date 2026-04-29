class_name GlobalPartEffect
extends Resource

## Stat modified by this global part. Uses same multiply/add semantics as upgrades (level = 1).
@export_enum(
	"mine_damage_per_tick",
	"move_speed_px_s",
	"fuel_max",
	"fuel_drain_per_second"
)
var stat: String = "mine_damage_per_tick"

@export_enum("add", "multiply") var operation: String = "multiply"
@export var value: float = 1.0
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
