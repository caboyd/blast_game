class_name ShipUpgradeEffect
extends GlobalPartEffect

const OP_ADD := "add"
const OP_MULTIPLY := "multiply"

## Gameplay stat this effect modifies — must exist in ShipData.get_base_float_for_stat.
## Plain names only: Godot's "Label:value" enum form can save the whole token as the string and break matching.
@export_enum(
	"mine_damage_per_tick",
	"vision_radius_cells",
	"move_speed_px_s",
	"turn_rate_rad_s",
	"fuel_max",
	"fuel_drain_per_second",
	"drill_range_bonus_game_px",
	"money_double_chance"
)
var stat: String = "mine_damage_per_tick"

@export_enum("add", "multiply") var operation: String = "add"
@export var value: float = 0.0
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


## Alias for ship-upgrade code paths; same as [method normalize_stat_id].
static func normalize_effect_stat_id(raw: Variant) -> StringName:
	return normalize_stat_id(raw)


static func normalize_operation(raw: Variant) -> String:
	if raw is int:
		return OP_MULTIPLY if int(raw) == 1 else OP_ADD
	var s: String = str(raw).strip_edges().to_lower()
	if s == OP_MULTIPLY or s == "mul":
		return OP_MULTIPLY
	return OP_ADD


static func apply_effect(base: float, level: int, eff: Variant) -> float:
	if eff == null or level <= 0:
		return base
	var val: float = float(eff.get("value"))
	var op: String = normalize_operation(eff.get("operation"))
	var cmin: float = float(eff.get("clamp_min"))
	var cmax: float = float(eff.get("clamp_max"))
	var raw: float
	if op == OP_MULTIPLY:
		raw = base * pow(val, float(level))
	else:
		raw = base + val * float(level)
	return clampf(raw, cmin, cmax)
