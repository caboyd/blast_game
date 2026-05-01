class_name GlobalPartEffect
extends Resource

## Base type for global part effects. Use [GlobalPartStatEffect] for numeric stats;
## [GlobalPartMovementPenaltyEffect] for treads movement stutter.

static func normalize_stat_id(raw: Variant) -> StringName:
	var s: String = str(raw).strip_edges()
	if s.is_empty():
		return &""
	var c: int = s.rfind(":")
	if c >= 0 and c < s.length() - 1:
		s = s.substr(c + 1).strip_edges()
	return StringName(s)
