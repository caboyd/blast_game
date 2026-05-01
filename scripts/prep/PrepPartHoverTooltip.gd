extends PanelContainer

const _GlobalPartStatEffect = preload("res://scripts/data/GlobalPartStatEffect.gd")
const _GlobalPartMovementPenaltyEffect = preload("res://scripts/data/GlobalPartMovementPenaltyEffect.gd")


func setup_from_equipped_slot(type_key: StringName, part_id: StringName) -> void:
	var pd: GlobalPartData = GlobalPartRegistry.get_part_data(part_id)
	var name_txt: String = "—"
	var type_txt: String = String(type_key).replace("_", " ").capitalize()

	if pd != null:
		var dn: String = pd.display_name.strip_edges()
		var base_type: String = String(pd.part_type).replace("_", " ").capitalize()
		var pti: int = int(pd.tier)
		type_txt = base_type if pti <= 0 else ("%s · Tier %d" % [base_type, pti])
		name_txt = base_type if dn.is_empty() else "%s %s" % [dn, base_type]

	var lvl: int = GlobalPartRegistry.get_part_level(part_id)
	var mx: int = GlobalPartRegistry.get_part_max_level(part_id)

	if has_node(^"%TooltipName"):
		(get_node(^"%TooltipName") as Label).text = name_txt
	if has_node(^"%TooltipType"):
		(get_node(^"%TooltipType") as Label).text = type_txt

	if has_node(^"%TooltipEffects"):
		var rtl: RichTextLabel = get_node(^"%TooltipEffects") as RichTextLabel
		rtl.text = _effects_summary_text(part_id)

	var bar: ProgressBar = null
	if has_node(^"%TooltipLevelBar"):
		bar = get_node(^"%TooltipLevelBar") as ProgressBar
	var lvl_lbl: Label = null
	if has_node(^"%TooltipLevelLabel"):
		lvl_lbl = get_node(^"%TooltipLevelLabel") as Label

	if bar != null:
		bar.max_value = float(mx)
		bar.value = float(mini(lvl, mx))

	if lvl_lbl != null:
		if lvl >= mx and mx > 0:
			lvl_lbl.text = "Lv. %d (MAX)" % lvl
			if bar != null:
				bar.value = bar.max_value
		else:
			lvl_lbl.text = "Lv. %d / %d" % [lvl, mx]


func _effects_summary_text(part_id: StringName) -> String:
	var pd: GlobalPartData = GlobalPartRegistry.get_part_data(part_id)
	if pd == null:
		return ""
	var lvl: int = GlobalPartRegistry.get_part_level(part_id)
	var rows: PackedStringArray = PackedStringArray()
	for eff in pd.get_effects_for_level(lvl):
		if eff == null:
			continue
		if eff is _GlobalPartMovementPenaltyEffect:
			var mpe := eff as _GlobalPartMovementPenaltyEffect
			var evs: float = float(mpe.every_s)
			var dus: float = float(mpe.duration_s)
			var msm: float = clampf(float(mpe.speed_multiplier), 0.0, 1.0)
			if evs > 0.0 and dus > 0.0:
				rows.append(
					(
						"Movement stutter (level %d): every %.2fs for %.2fs → speed × %.0f%%"
						% [lvl, evs, dus, msm * 100.0]
					)
				)
			continue
		if not (eff is _GlobalPartStatEffect):
			continue
		var se := eff as _GlobalPartStatEffect
		var est := GlobalPartEffect.normalize_stat_id(se.stat)
		var stat_nm: String = String(est).replace("_", " ")
		var op: String = String(se.operation)
		var val: float = float(se.value)
		var op_word: String = "mult" if op == "multiply" else "add"
		rows.append(
			"%s (level %d, %s) %s" % [stat_nm, lvl, op_word, _format_effect_value(val, op)]
		)

	var acc := ""
	for i in rows.size():
		if i > 0:
			acc += "\n"
		acc += rows[i]
	var hdr := ""
	if pd.get_max_level() > 1 and rows.size() > 0:
		hdr = "[b]Level %d effects[/b]\n" % lvl
	return hdr + acc


func _format_effect_value(val: float, operation: String) -> String:
	if operation == "multiply":
		return "× %.3f" % val
	return "%+.3f" % val
