extends Node2D

@export var crack_texture: Texture2D
@export var frame_count: int = 5
@export_range(0.0, 1.0) var crack_alpha: float = 0.7
## Uniform scale multiplier range applied on each axis (stable per grid cell).
@export var jitter_scale_min: float = 0.8
@export var jitter_scale_max: float = 0.99
## Max absolute rotation (degrees); sign/random per cell, stable for that cell.
@export var jitter_rotation_degrees_max: float = 90.0

var _sprites: Array[Sprite2D] = []


func _ready() -> void:
	z_index = 1


func _physics_process(_delta: float) -> void:
	var mw := get_parent() as MiningWorld
	if mw == null:
		return
	var ship: ShipBase = _resolve_anchor_ship(mw)
	if ship == null or ship.follower_visual_only:
		_hide_all_sprites()
		return
	if crack_texture == null:
		_hide_all_sprites()
		return
	var drill_c: Vector2 = ship.get_drill_center_world()
	var drill_r: float = ship.get_effective_drill_world_radius_px()
	if not mw.has_solid_overlapping_circle_world(drill_c, drill_r):
		_hide_all_sprites()
		return
	var allowed: PackedInt32Array = PartRegistry.get_drill_allowed_mine_type_ids()
	var candidates: Array[Vector2i] = mw.get_mineable_cells_in_circle_world(drill_c, drill_r, allowed)
	var cells: Array[Vector2i] = []
	for c in candidates:
		var tid: int = mw.get_cell_type_at(c)
		var max_hp: int = 1
		if tid >= 0 and tid < MiningWorld.TYPE_MAX_HP.size():
			max_hp = maxi(1, int(MiningWorld.TYPE_MAX_HP[tid]))
		if mw.get_cell_hp_at(c) < max_hp:
			cells.append(c)
	_ensure_sprite_pool_size(cells.size())
	var fc: int = maxi(1, frame_count)
	var tex_w: float = float(crack_texture.get_width())
	var tex_h: float = float(crack_texture.get_height())
	var frame_w: float = tex_w / float(fc)
	var cell_scale := Vector2(MiningWorld.CELL_SIZE_PX / frame_w, MiningWorld.CELL_SIZE_PX / tex_h)
	for i in _sprites.size():
		var sp: Sprite2D = _sprites[i]
		if i >= cells.size():
			sp.visible = false
			continue
		var cell: Vector2i = cells[i]
		sp.visible = true
		sp.texture = crack_texture
		sp.centered = true
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.position = mw.cell_center_world(cell)
		var jid := _stable_jitter(cell)
		sp.scale = cell_scale * jid.x
		sp.rotation = deg_to_rad(jid.y)
		var type_id: int = mw.get_cell_type_at(cell)
		var max_hp: int = 1
		if type_id >= 0 and type_id < MiningWorld.TYPE_MAX_HP.size():
			max_hp = maxi(1, int(MiningWorld.TYPE_MAX_HP[type_id]))
		var hp: int = mw.get_cell_hp_at(cell)
		# Map current HP fraction directly: full HP -> frame 0, lowest HP -> last frame (no premature jump from round()).
		var hp_frac: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var frame_i: int = clampi(mini(fc - 1, int(floor((1.0 - hp_frac) * float(fc)))), 0, fc - 1)
		sp.region_enabled = true
		sp.region_rect = Rect2(float(frame_i) * frame_w, 0.0, frame_w, tex_h)
		sp.modulate = Color(1.0, 1.0, 1.0, clampf(crack_alpha, 0.0, 1.0))


func _stable_jitter(cell: Vector2i) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, 1265512049))
	var s0: float = minf(jitter_scale_min, jitter_scale_max)
	var s1: float = maxf(jitter_scale_min, jitter_scale_max)
	var s_mul: float = rng.randf_range(s0, s1)
	var d_max: float = maxf(0.0, jitter_rotation_degrees_max)
	var rot_deg: float = rng.randf_range(-d_max, d_max)
	return Vector2(s_mul, rot_deg)


func _resolve_anchor_ship(mw: MiningWorld) -> ShipBase:
	for lead in get_tree().get_nodes_in_group(&"leading_mining_ship"):
		if lead is ShipBase:
			var sb: ShipBase = lead as ShipBase
			if sb.grid == mw:
				return sb
	for n in get_tree().get_nodes_in_group(&"mining_ship"):
		var sb_: ShipBase = null
		if n is ShipBase:
			sb_ = n as ShipBase
		else:
			var par: Node = n.get_parent()
			if par is ShipBase:
				sb_ = par as ShipBase
		if sb_ != null and sb_.grid == mw and not sb_.follower_visual_only:
			return sb_
	return null


func _ensure_sprite_pool_size(n: int) -> void:
	while _sprites.size() < n:
		var sp := Sprite2D.new()
		sp.visible = false
		add_child(sp)
		_sprites.append(sp)


func _hide_all_sprites() -> void:
	for sp in _sprites:
		sp.visible = false
