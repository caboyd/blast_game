extends Node2D
class_name MiningDebrisField
## Global mining debris pool: one MultiMesh batch, global lifecycle.

const _DEBRIS_CIRCLE_SHADER: Shader = preload("res://shaders/debris_particle_circle.gdshader")
const _GLOBAL_DESPAWN_SAMPLE: int = 64

@export_range(16, 4096) var max_total_particles: int = 256
@export_range(1, 32) var particles_per_broken_cell: int = 6
@export_range(0.0, 60.0) var particle_min_age_s: float = 4.0
@export_range(0.05, 5.0) var particle_despawn_interval_s: float = 0.35
@export_range(1, 128) var particle_despawns_per_tick: int = 8
@export_range(0.05, 5.0) var particle_fade_out_s: float = 0.8

@export_range(8.0, 256.0) var repel_radius_px: float = 48.0
@export_range(0.0, 2000.0) var repel_strength: float = 520.0

@export_range(0.0, 120.0) var spring_strength: float = 38.0
@export_range(0.0, 30.0) var damping: float = 9.5
@export_range(0.0001, 4.0) var sleep_velocity_threshold: float = 0.35
@export_range(0.0001, 4.0) var sleep_z_threshold: float = 0.08
@export_range(0.0001, 2.0) var sleep_displacement_px: float = 0.06

@export_range(0.0, 120.0) var spawn_z_velocity_min: float = 18.0
@export_range(0.0, 200.0) var spawn_z_velocity_max: float = 52.0
@export_range(-800.0, 0.0) var gravity_z: float = -220.0
@export_range(0.0, 0.05) var z_scale: float = 0.008

@export_range(0.0, 1.0) var shadow_alpha: float = 0.22
@export var shadow_offset: Vector2 = Vector2(1.2, 2.4)
@export_range(0.0, 0.35) var color_variation: float = 0.12

var _world: MiningWorld
var _pool: GlobalDebrisPool
var _cam_rect: Rect2 = Rect2()

var _white: ImageTexture
var _debris_circle_material: ShaderMaterial
var _rng_spawn := RandomNumberGenerator.new()
var _despawn_accum: float = 0.0

# Debug (updated when GameStatistics.debug_world_visuals)
var debug_simulated_particles: int = 0
var debug_total_alive_particles: int = 0
var _dbg_tick: int = 0


func setup(world: MiningWorld) -> void:
	_world = world
	if _white == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	_ensure_debris_circle_material()
	_ensure_pool()


func _ensure_debris_circle_material() -> ShaderMaterial:
	if _debris_circle_material == null:
		_debris_circle_material = ShaderMaterial.new()
		_debris_circle_material.shader = _DEBRIS_CIRCLE_SHADER
	return _debris_circle_material


func clear_all() -> void:
	if _pool != null:
		_pool.clear_particles()


func on_chunk_unloaded(_chunk: Vector2i) -> void:
	pass


func update_camera_rect(rect: Rect2) -> void:
	_cam_rect = rect


func on_block_broken(world_pos: Vector2, type_id: int) -> void:
	if _world == null:
		return
	_ensure_pool()
	var n: int = _spawn_count_for_type(type_id)
	var base_col: Color = _world.display_color_for_mined_type(type_id)
	var sz_mul: float = _spawn_size_mul_for_type(type_id)
	for i in n:
		if not _reserve_particle_budget():
			continue
		var seed_i: int = hash(
			Vector4(world_pos.x, world_pos.y, float(type_id), float(i)))
		var col := _vary_color(base_col, seed_i)
		_pool.spawn_particle(world_pos, col, seed_i, sz_mul)


func _physics_process(delta: float) -> void:
	if _world == null or delta <= 0.0:
		return
	_ensure_pool()
	var anchor_ship: ShipBase = _resolve_anchor_ship()
	var repeller: Vector2 = _repeller_world_pos(anchor_ship)

	_pool.simulate(delta, repeller)
	_update_global_despawn(delta)
	_pool.sync_dirty_slots(z_scale, shadow_offset, shadow_alpha)

	if GameStatistics.debug_world_visuals:
		debug_simulated_particles = _pool.count_alive()
		debug_total_alive_particles = _pool.count_alive()
		_dbg_tick += 1
		if _dbg_tick >= 45:
			_dbg_tick = 0
			print(
				"[MiningDebris] sim_parts=", debug_simulated_particles,
				" total_alive=", debug_total_alive_particles,
			)


func _ensure_pool() -> void:
	if _pool != null and _pool.capacity() == max_total_particles:
		return
	if _pool != null:
		_pool.free_renderers()
	_pool = GlobalDebrisPool.new()
	_pool.build(self, max_total_particles)


func _reserve_particle_budget() -> bool:
	if _pool == null:
		return false
	if _pool.count_alive() < max_total_particles:
		return true
	_start_global_old_particle_fades(1)
	return _pool.count_alive() < max_total_particles


func _update_global_despawn(delta: float) -> void:
	_despawn_accum += delta
	if _despawn_accum < particle_despawn_interval_s:
		return
	_despawn_accum = 0.0
	_start_global_old_particle_fades(particle_despawns_per_tick)


func _start_global_old_particle_fades(max_count: int) -> bool:
	if max_count <= 0:
		return false
	if _pool == null:
		return false
	return _pool.fade_oldest_weighted_sample(max_count, particle_min_age_s, _GLOBAL_DESPAWN_SAMPLE, _rng_spawn)


func _repeller_world_pos(ship: ShipBase) -> Vector2:
	if ship == null:
		return _cam_rect.get_center()
	if ship.has_method(&"get_drill_center_world"):
		return ship.call(&"get_drill_center_world") as Vector2
	return ship.global_position


func _resolve_anchor_ship() -> ShipBase:
	var lead_nodes := get_tree().get_nodes_in_group(&"leading_mining_ship")
	for n in lead_nodes:
		if n is ShipBase:
			var sb: ShipBase = n as ShipBase
			if sb.grid == _world:
				return sb
	var fallback := get_tree().get_nodes_in_group(&"mining_ship")
	for n in fallback:
		var sb_: ShipBase = null
		if n is ShipBase:
			sb_ = n as ShipBase
		else:
			var par: Node = n.get_parent()
			if par is ShipBase:
				sb_ = par as ShipBase
		if sb_ != null and sb_.grid == _world and not sb_.follower_visual_only:
			return sb_
	return null


func _spawn_count_for_type(type_id: int) -> int:
	var base: int = particles_per_broken_cell
	var mul: float = 1.0
	match type_id:
		MiningWorld.TYPE_DIRT, MiningWorld.TYPE_PACKED_EARTH, MiningWorld.TYPE_CLAY, MiningWorld.TYPE_SANDSTONE:
			mul = 1.35
		MiningWorld.TYPE_STONE, MiningWorld.TYPE_SHALE, MiningWorld.TYPE_OBSIDIAN:
			mul = 0.55
		MiningWorld.TYPE_GOLD, MiningWorld.TYPE_RUBY, MiningWorld.TYPE_COPPER, MiningWorld.TYPE_TIN, MiningWorld.TYPE_IRON, MiningWorld.TYPE_SILVER:
			mul = 0.65
		MiningWorld.TYPE_FUEL:
			mul = 0.0
		_:
			mul = 1.0
	return maxi(1, int(round(float(base) * mul)))


func _spawn_size_mul_for_type(type_id: int) -> float:
	match type_id:
		MiningWorld.TYPE_DIRT, MiningWorld.TYPE_PACKED_EARTH, MiningWorld.TYPE_CLAY, MiningWorld.TYPE_SANDSTONE:
			return 0.8
		MiningWorld.TYPE_STONE, MiningWorld.TYPE_SHALE, MiningWorld.TYPE_OBSIDIAN:
			return 1.2
		MiningWorld.TYPE_GOLD, MiningWorld.TYPE_RUBY, MiningWorld.TYPE_COPPER, MiningWorld.TYPE_TIN, MiningWorld.TYPE_IRON, MiningWorld.TYPE_SILVER:
			return 0.15
		_:
			return 1.0


func _vary_color(base: Color, seed_i: int) -> Color:
	_rng_spawn.seed = seed_i as int
	var dv: float = color_variation
	return Color(
		clampf(base.r + _rng_spawn.randf_range(-dv, dv), 0.0, 1.0),
		clampf(base.g + _rng_spawn.randf_range(-dv, dv), 0.0, 1.0),
		clampf(base.b + _rng_spawn.randf_range(-dv, dv), 0.0, 1.0),
		base.a,
	)


class GlobalDebrisPool extends RefCounted:
	var _field: MiningDebrisField
	var _max: int = 0
	var _live_count: int = 0

	var _rest: PackedVector2Array = PackedVector2Array()
	var _pos: PackedVector2Array = PackedVector2Array()
	var _vel: PackedVector2Array = PackedVector2Array()
	var _z: PackedFloat32Array = PackedFloat32Array()
	var _z_vel: PackedFloat32Array = PackedFloat32Array()
	var _age: PackedFloat32Array = PackedFloat32Array()
	var _fade_t: PackedFloat32Array = PackedFloat32Array()
	var _base_size: PackedFloat32Array = PackedFloat32Array()
	var _colors: PackedColorArray = PackedColorArray()
	var _rots: PackedFloat32Array = PackedFloat32Array()
	var _live_index: PackedInt32Array = PackedInt32Array()

	var _alive: PackedByteArray = PackedByteArray()
	var _sleeping: PackedByteArray = PackedByteArray()
	var _fading: PackedByteArray = PackedByteArray()
	var _dirty: PackedByteArray = PackedByteArray()

	var _live_slots: Array[int] = []
	var _free_slots: Array[int] = []
	var _dirty_slots: Array[int] = []

	var _particles_mmi: MultiMeshInstance2D
	var _shadows_mmi: MultiMeshInstance2D
	var _mm_p: MultiMesh
	var _mm_s: MultiMesh
	var _rng := RandomNumberGenerator.new()


	func build(field: MiningDebrisField, max_n: int) -> void:
		_field = field
		_max = max_n
		_live_count = 0
		_rest.resize(max_n)
		_pos.resize(max_n)
		_vel.resize(max_n)
		_z.resize(max_n)
		_z_vel.resize(max_n)
		_age.resize(max_n)
		_fade_t.resize(max_n)
		_base_size.resize(max_n)
		_colors.resize(max_n)
		_rots.resize(max_n)
		_live_index.resize(max_n)
		_alive.resize(max_n)
		_sleeping.resize(max_n)
		_fading.resize(max_n)
		_dirty.resize(max_n)

		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)

		_mm_p = MultiMesh.new()
		_mm_p.transform_format = MultiMesh.TRANSFORM_2D
		_mm_p.use_colors = true
		_mm_p.mesh = quad
		_mm_p.instance_count = max_n

		_mm_s = MultiMesh.new()
		_mm_s.transform_format = MultiMesh.TRANSFORM_2D
		_mm_s.use_colors = true
		_mm_s.mesh = quad
		_mm_s.instance_count = max_n

		var circ_mat: ShaderMaterial = field._ensure_debris_circle_material()
		_shadows_mmi = MultiMeshInstance2D.new()
		_shadows_mmi.z_index = -1
		_shadows_mmi.texture = field._white
		_shadows_mmi.multimesh = _mm_s
		_shadows_mmi.material = circ_mat

		_particles_mmi = MultiMeshInstance2D.new()
		_particles_mmi.texture = field._white
		_particles_mmi.multimesh = _mm_p
		_particles_mmi.material = circ_mat

		field.add_child(_shadows_mmi)
		field.add_child(_particles_mmi)

		_live_slots.clear()
		_free_slots.clear()
		_dirty_slots.clear()
		for i in max_n:
			_alive[i] = 0
			_sleeping[i] = 0
			_fading[i] = 0
			_dirty[i] = 0
			_live_index[i] = -1
			_free_slots.append(max_n - 1 - i)
			_hide_slot(i)


	func capacity() -> int:
		return _max


	func count_alive() -> int:
		return _live_count


	func clear_particles() -> void:
		var slots := _live_slots.duplicate()
		for slot in slots:
			_kill_slot(slot as int)
		sync_dirty_slots(_field.z_scale, _field.shadow_offset, _field.shadow_alpha)


	func free_renderers() -> void:
		if _particles_mmi != null and is_instance_valid(_particles_mmi):
			_particles_mmi.queue_free()
		if _shadows_mmi != null and is_instance_valid(_shadows_mmi):
			_shadows_mmi.queue_free()
		_particles_mmi = null
		_shadows_mmi = null


	func spawn_particle(world_center: Vector2, col: Color, seed_i: int, size_mul: float) -> void:
		var slot: int = _take_slot()
		if slot < 0:
			return
		var cs: float = MiningWorld.CELL_SIZE_PX
		var half: float = cs * 0.45
		_rng.seed = seed_i
		var p: Vector2 = world_center + Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))

		_rest[slot] = p
		_pos[slot] = p
		_vel[slot] = Vector2.ZERO
		_z[slot] = 0.0
		_age[slot] = 0.0
		_fade_t[slot] = 0.0
		var zvmin: float = minf(_field.spawn_z_velocity_min, _field.spawn_z_velocity_max)
		var zvmax: float = maxf(_field.spawn_z_velocity_min, _field.spawn_z_velocity_max)
		_z_vel[slot] = _rng.randf_range(zvmin, zvmax)
		_base_size[slot] = _rng.randf_range(3.2, 5.6) * size_mul
		_colors[slot] = col
		_rots[slot] = _rng.randf_range(-0.55, 0.55)
		_alive[slot] = 1
		_sleeping[slot] = 0
		_fading[slot] = 0
		_add_live_slot(slot)
		_mark_dirty(slot)


	func simulate(delta: float, repeller: Vector2) -> void:
		var rs: float = _field.repel_radius_px
		var rs_wake: float = rs * 1.35
		var rs2: float = rs * rs
		var wake2: float = rs_wake * rs_wake
		var rep_st: float = _field.repel_strength
		var spr: float = _field.spring_strength
		var damp: float = _field.damping
		var gz: float = _field.gravity_z
		var vz_thresh: float = _field.sleep_velocity_threshold
		var vz2: float = vz_thresh * vz_thresh
		var sz_thresh: float = _field.sleep_z_threshold
		var disp_lim: float = _field.sleep_displacement_px
		var disp_lim2: float = disp_lim * disp_lim

		for live_i in range(_live_slots.size() - 1, -1, -1):
			var slot: int = _live_slots[live_i]
			if _alive[slot] == 0:
				continue

			_age[slot] += delta
			if _fading[slot] != 0:
				_fade_t[slot] += delta
				if _fade_t[slot] >= _field.particle_fade_out_s:
					_kill_slot(slot)
				else:
					_mark_dirty(slot)
				continue

			var p: Vector2 = _pos[slot]
			var to_r: Vector2 = p - repeller
			var dist2: float = to_r.length_squared()
			if _sleeping[slot] != 0:
				if dist2 > wake2:
					continue
				_sleeping[slot] = 0

			if dist2 <= rs2 and dist2 > 1e-6:
				var d: float = sqrt(dist2)
				var falloff: float = 1.0 - clampf(d / rs, 0.0, 1.0)
				falloff *= falloff
				_vel[slot] += (to_r / d) * rep_st * falloff * delta

			var ax: Vector2 = spr * (_rest[slot] - p) - damp * _vel[slot]
			_vel[slot] += ax * delta
			p += _vel[slot] * delta
			_pos[slot] = p

			_z_vel[slot] += gz * delta
			_z[slot] += _z_vel[slot] * delta
			if _z[slot] < 0.0:
				_z[slot] = 0.0
				_z_vel[slot] *= -0.22

			var drift2: float = p.distance_squared_to(_rest[slot])
			if _vel[slot].length_squared() < vz2 and absf(_z[slot]) < sz_thresh and absf(_z_vel[slot]) < vz_thresh and drift2 < disp_lim2:
				_pos[slot] = _rest[slot]
				_vel[slot] = Vector2.ZERO
				_z[slot] = 0.0
				_z_vel[slot] = 0.0
				_sleeping[slot] = 1
			_mark_dirty(slot)


	func fade_oldest_weighted_sample(
		max_fades: int, min_age_s: float, sample_n: int, rng: RandomNumberGenerator,
	) -> bool:
		var did: bool = false
		for _t in max_fades:
			var slot: int = _pick_old_weighted_slot(sample_n, min_age_s, rng)
			if slot < 0:
				return did
			start_fade_slot(slot)
			did = true
		return did


	func _pick_old_weighted_slot(sample_n: int, min_age_s: float, rng: RandomNumberGenerator) -> int:
		if _live_slots.is_empty():
			return -1
		var n_live: int = _live_slots.size()
		var k: int = mini(sample_n, n_live)
		var total: float = 0.0
		var pick: int = -1
		for _i in k:
			var slot: int = _live_slots[rng.randi_range(0, n_live - 1)]
			if _alive[slot] == 0 or _fading[slot] != 0:
				continue
			var age: float = _age[slot]
			var w: float = maxf(0.0, age - min_age_s)
			if w <= 0.0:
				continue
			total += w
			if rng.randf() * total <= w:
				pick = slot
		return pick


	func start_fade_slot(slot: int) -> void:
		if slot < 0 or slot >= _max or _alive[slot] == 0 or _fading[slot] != 0:
			return
		_fading[slot] = 1
		_fade_t[slot] = 0.0
		_sleeping[slot] = 1
		_vel[slot] = Vector2.ZERO
		_z_vel[slot] = 0.0
		_mark_dirty(slot)


	func sync_dirty_slots(z_sc: float, sh_off: Vector2, sh_alpha: float) -> void:
		if _particles_mmi == null:
			return
		for slot in _dirty_slots:
			_sync_slot(slot, z_sc, sh_off, sh_alpha)
			_dirty[slot] = 0
		_dirty_slots.clear()


	func _take_slot() -> int:
		if not _free_slots.is_empty():
			return _free_slots.pop_back() as int
		var slot: int = _pick_old_weighted_slot(_GLOBAL_DESPAWN_SAMPLE, _field.particle_min_age_s, _rng)
		if slot < 0:
			return -1
		_kill_slot(slot)
		return slot


	func _add_live_slot(slot: int) -> void:
		if _live_index[slot] >= 0:
			return
		_live_index[slot] = _live_slots.size()
		_live_slots.append(slot)
		_live_count += 1


	func _remove_live_slot(slot: int) -> void:
		var idx: int = _live_index[slot]
		if idx < 0:
			return
		var last_slot: int = _live_slots[_live_slots.size() - 1]
		_live_slots[idx] = last_slot
		_live_index[last_slot] = idx
		_live_slots.pop_back()
		_live_index[slot] = -1
		_live_count -= 1


	func _kill_slot(slot: int) -> void:
		if slot < 0 or slot >= _max or _alive[slot] == 0:
			return
		_alive[slot] = 0
		_sleeping[slot] = 0
		_fading[slot] = 0
		_age[slot] = 0.0
		_fade_t[slot] = 0.0
		_vel[slot] = Vector2.ZERO
		_z_vel[slot] = 0.0
		_z[slot] = 0.0
		_remove_live_slot(slot)
		_free_slots.append(slot)
		_mark_dirty(slot)


	func _mark_dirty(slot: int) -> void:
		if _dirty[slot] != 0:
			return
		_dirty[slot] = 1
		_dirty_slots.append(slot)


	func _sync_slot(slot: int, z_sc: float, sh_off: Vector2, sh_alpha: float) -> void:
		if _alive[slot] == 0:
			_hide_slot(slot)
			return
		var zi: float = _z[slot]
		var p_draw: Vector2 = _pos[slot] + Vector2(0.0, -zi)
		var s: float = _base_size[slot] * (1.0 + zi * z_sc)
		var xf_p := _xf_rot_scale_pos(_rots[slot], s, s, p_draw)
		_mm_p.set_instance_transform_2d(slot, xf_p)
		var co: Color = _colors[slot]
		co.a = clampf(co.a * _fade_alpha(slot), 0.0, 1.0)
		_mm_p.set_instance_color(slot, co)

		var height_fade: float = clampf(1.0 - zi * 0.035, 0.15, 1.0)
		var xf_s := _xf_rot_scale_pos(_rots[slot] * 0.35, s * 1.15, s * 0.38, _pos[slot] + sh_off)
		_mm_s.set_instance_transform_2d(slot, xf_s)
		var sa: float = sh_alpha * height_fade * co.a
		_mm_s.set_instance_color(slot, Color(0.0, 0.0, 0.0, clampf(sa, 0.0, 1.0)))


	func _hide_slot(slot: int) -> void:
		_mm_p.set_instance_transform_2d(slot, Transform2D())
		_mm_p.set_instance_color(slot, Color(0, 0, 0, 0))
		_mm_s.set_instance_transform_2d(slot, Transform2D())
		_mm_s.set_instance_color(slot, Color(0, 0, 0, 0))


	func _fade_alpha(slot: int) -> float:
		if _fading[slot] == 0:
			return 1.0
		var fade_s: float = maxf(0.001, _field.particle_fade_out_s)
		return clampf(1.0 - (_fade_t[slot] / fade_s), 0.0, 1.0)


	func _xf_rot_scale_pos(rot: float, sx: float, sy: float, origin: Vector2) -> Transform2D:
		var cr := cos(rot)
		var sn := sin(rot)
		return Transform2D(Vector2(cr * sx, sn * sx), Vector2(-sn * sy, cr * sy), origin)
