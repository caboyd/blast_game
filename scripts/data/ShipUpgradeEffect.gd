class_name ShipUpgradeEffect
extends Resource

## Gameplay stat this effect modifies — must exist in ShipData.get_base_float_for_stat.
## Plain names only: Godot's "Label:value" enum form can save the whole token as the string and break matching.
@export_enum(
	"mine_damage_per_tick",
	"vision_radius_cells",
	"move_speed_px_s",
	"turn_rate_rad_s",
	"fuel_max",
	"drill_range_bonus_game_px",
	"money_double_chance"
)
var stat: String = "mine_damage_per_tick"


## Maps saved effect `stat` to the id used at runtime (handles legacy bad saves with "Label:stat_id").
static func normalize_effect_stat_id(raw: Variant) -> StringName:
	var s: String = str(raw).strip_edges()
	if s.is_empty():
		return &""
	var c: int = s.rfind(":")
	if c >= 0 and c < s.length() - 1:
		s = s.substr(c + 1).strip_edges()
	return StringName(s)
@export_enum("add", "multiply") var operation: String = "add"
@export var value: float = 0.0
@export var clamp_min: float = -1e20
@export var clamp_max: float = 1e20
