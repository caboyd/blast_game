extends RefCounted

const OP_ADD := "add"
const OP_MULTIPLY := "multiply"


static func _normalize_cost_op(raw: Variant) -> String:
	if raw is int:
		return OP_MULTIPLY if int(raw) == 1 else OP_ADD
	var s: String = str(raw).strip_edges().to_lower()
	if s == OP_MULTIPLY or s == "mul":
		return OP_MULTIPLY
	return OP_ADD


static func cost_at_level(ud: Variant, current_level_before_purchase: int) -> int:
	if ud == null:
		return 999999999
	var L: float = float(current_level_before_purchase)
	var base_c: float = float(ud.get("base_cost"))
	var val: float = float(ud.get("cost_value"))
	var op: String = _normalize_cost_op(ud.get("cost_operation"))
	var raw: float
	if op == OP_MULTIPLY:
		raw = base_c * pow(val, L)
	else:
		raw = base_c + val * L
	return maxi(1, int(round(raw)))
