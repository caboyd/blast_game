extends Node2D
class_name MiningDebrisField
## Global mining debris pool: one MultiMesh batch, circular overwrite.

const _DEBRIS_CIRCLE_SHADER: Shader = preload("res://shaders/debris_particle_circle.gdshader")
@export_range(16, 16384) var max_total_particles: int = 256
@export_range(1, 32) var particles_per_broken_cell: int = 6
@export_range(0, 1024) var old_particle_fade_window: int = 100

@export_range(0.0, 256.0) var repel_radius_px: float = 48.0
@export_range(0.0, 2000.0) var repel_strength: float = 520.0

@export_range(0.0, 120.0) var spring_strength: float = 38.0

@export_range(0.0, 120.0) var spawn_z_velocity_min: float = 18.0
@export_range(0.0, 200.0) var spawn_z_velocity_max: float = 52.0
@export_range(-800.0, 0.0) var gravity_z: float = -220.0
@export_range(0.0, 0.05) var z_scale: float = 0.008
## Initial fake height assigned when the ship passes over debris; then gravity_z pulls it back down.
@export_range(0.0, 200.0) var repel_z_kick_max: float = 36.0
## Min repel falloff (0..1, sqrt boundary distance) before Z lift starts; higher = only inner zone pops up.
@export_range(0.0, 0.999) var repel_z_falloff_threshold: float = 0.42

@export_range(0.0, 1.0) var shadow_alpha: float = 0.22
@export var shadow_offset: Vector2 = Vector2(1.2, 2.4)
@export_range(0.0, 0.35) var color_variation: float = 0.12

var _world: MiningWorld
var _pool: GlobalDebrisPool
var _planet2_gpu_black_hole: bool = false
## Planet2 QA: revert to circular MultiMesh + repel debris if true.
@export var force_planet2_legacy_multimesh: bool = false
var _cam_rect: Rect2 = Rect2()

var _white: ImageTexture
var _debris_circle_material: ShaderMaterial
var _debris_shadow_material: ShaderMaterial
var _rng_spawn := RandomNumberGenerator.new()
var _last_repeller_pos: Vector2 = Vector2.ZERO
var _last_repeller_valid: bool = false

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
	refresh_debris_backend_for_stage()


func refresh_debris_backend_for_stage() -> void:
	var want_gpu := _compute_planet2_gpu_black_hole()
	var had_gpu := _planet2_gpu_black_hole
	_planet2_gpu_black_hole = want_gpu
	if want_gpu != had_gpu:
		if _pool != null:
			_pool.free_renderers()
			_pool = null
	if not want_gpu:
		_ensure_pool()


func _compute_planet2_gpu_black_hole() -> bool:
	if force_planet2_legacy_multimesh:
		return false
	if _world == null:
		return false
	if _world.stage_id != &"planet2":
		return false
	return get_tree().get_first_node_in_group(&"planet2_black_hole_debris") != null


func _ensure_debris_circle_material(render_shadow: bool = false) -> ShaderMaterial:
	if render_shadow:
		if _debris_shadow_material == null:
			_debris_shadow_material = ShaderMaterial.new()
			_debris_shadow_material.shader = _DEBRIS_CIRCLE_SHADER
			_debris_shadow_material.set_shader_parameter("render_shadow", true)
		return _debris_shadow_material
	if _debris_circle_material == null:
		_debris_circle_material = ShaderMaterial.new()
		_debris_circle_material.shader = _DEBRIS_CIRCLE_SHADER
		_debris_circle_material.set_shader_parameter("render_shadow", false)
	return _debris_circle_material


func clear_all() -> void:
	if _planet2_gpu_black_hole:
		var emitter := get_tree().get_first_node_in_group(&"planet2_black_hole_debris")
		if emitter != null and emitter.has_method(&"restart"):
			emitter.restart(false)
		return
	if _pool != null:
		_pool.clear_particles()


func on_chunk_unloaded(_chunk: Vector2i) -> void:
	pass


func update_camera_rect(rect: Rect2) -> void:
	_cam_rect = rect


func on_block_broken(world_pos: Vector2, type_id: int) -> void:
	if _world == null:
		return
	if _planet2_gpu_black_hole:
		var emitter := get_tree().get_first_node_in_group(&"planet2_black_hole_debris")
		if emitter != null and emitter.has_method(&"emit_burst"):
			emitter.emit_burst(world_pos, type_id)
		return
	_ensure_pool()
	var n: int = _spawn_count_for_type(type_id)
	var base_col: Color = _world.display_color_for_mined_type(type_id)
	var sz_mul: float = _spawn_size_mul_for_type(type_id)
	for i in n:
		var seed_i: int = hash(
			Vector4(world_pos.x, world_pos.y, float(type_id), float(i)))
		var col := _vary_color(base_col, seed_i)
		_pool.spawn_particle(world_pos, col, seed_i, sz_mul)


func _physics_process(delta: float) -> void:
	if _planet2_gpu_black_hole:
		return
	if _world == null:
		_last_repeller_valid = false
		return
	_ensure_pool()
	var anchor_ship: ShipBase = _resolve_anchor_ship()
	var repeller: Vector2 = _repeller_world_pos(anchor_ship)
	var ship_fwd: Vector2 = _repeller_ship_forward(anchor_ship)
	var repeller_velocity := Vector2.ZERO
	if _last_repeller_valid and delta > 0.0:
		repeller_velocity = (repeller - _last_repeller_pos) / delta
	_last_repeller_pos = repeller
	_last_repeller_valid = true

	_push_debris_shader_params(repeller, ship_fwd, repeller_velocity)

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
	if _planet2_gpu_black_hole:
		return
	if _pool != null and _pool.capacity() == max_total_particles:
		return
	if _pool != null:
		_pool.free_renderers()
	_pool = GlobalDebrisPool.new()
	_pool.build(self, max_total_particles)


func _repeller_world_pos(ship: ShipBase) -> Vector2:
	if ship == null:
		return _cam_rect.get_center()
	return ship.get_hull_center_world()


func _repeller_ship_forward(ship: ShipBase) -> Vector2:
	var f := Vector2.RIGHT
	if ship == null:
		return f.normalized()
	f = ship.global_transform.x
	if not f.is_finite():
		return Vector2.RIGHT
	if f.length_squared() <= 1e-12:
		return Vector2.RIGHT
	return f.normalized()


func _push_debris_shader_params(player_global_location: Vector2, ship_forward: Vector2, player_global_velocity: Vector2) -> void:
	var time_s: float = float(Time.get_ticks_msec()) * 0.001
	var mats: Array[ShaderMaterial] = []
	if _debris_circle_material != null:
		mats.append(_debris_circle_material)
	if _debris_shadow_material != null:
		mats.append(_debris_shadow_material)
	for mat in mats:
		mat.set_shader_parameter("debris_time_s", time_s)
		mat.set_shader_parameter("player_global_location", player_global_location)
		mat.set_shader_parameter("player_global_velocity", player_global_velocity)
		mat.set_shader_parameter("repel_ship_forward", ship_forward)
		mat.set_shader_parameter("circular_next_slot", _pool.next_slot())
		mat.set_shader_parameter("circular_live_count", _pool.count_alive())
		mat.set_shader_parameter("circular_capacity", _pool.capacity())
		mat.set_shader_parameter("old_particle_fade_window", old_particle_fade_window)
		mat.set_shader_parameter("repel_radius_px", repel_radius_px)
		mat.set_shader_parameter("repel_strength", repel_strength)
		mat.set_shader_parameter("spring_strength", spring_strength)
		mat.set_shader_parameter("spawn_z_velocity_min", spawn_z_velocity_min)
		mat.set_shader_parameter("spawn_z_velocity_max", spawn_z_velocity_max)
		mat.set_shader_parameter("gravity_z", gravity_z)
		mat.set_shader_parameter("z_scale", z_scale)
		mat.set_shader_parameter("repel_z_kick_max", repel_z_kick_max)
		mat.set_shader_parameter("repel_z_falloff_threshold", repel_z_falloff_threshold)
		mat.set_shader_parameter("shadow_offset", shadow_offset)
		mat.set_shader_parameter("shadow_alpha", shadow_alpha)


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
			return 0.4
		MiningWorld.TYPE_STONE, MiningWorld.TYPE_SHALE, MiningWorld.TYPE_OBSIDIAN:
			return 0.8
		MiningWorld.TYPE_GOLD, MiningWorld.TYPE_RUBY, MiningWorld.TYPE_COPPER, MiningWorld.TYPE_TIN, MiningWorld.TYPE_IRON, MiningWorld.TYPE_SILVER:
			return 0.15
		_:
			return 1.0


static func black_hole_burst_count(type_id: int, particles_per_cell: int) -> int:
	if type_id == MiningWorld.TYPE_FUEL:
		return 0
	var base_i: int = particles_per_cell
	var mul: float = 1.0
	match type_id:
		MiningWorld.TYPE_DIRT, MiningWorld.TYPE_PACKED_EARTH, MiningWorld.TYPE_CLAY, MiningWorld.TYPE_SANDSTONE:
			mul = 1.35
		MiningWorld.TYPE_STONE, MiningWorld.TYPE_SHALE, MiningWorld.TYPE_OBSIDIAN:
			mul = 0.55
		MiningWorld.TYPE_GOLD, MiningWorld.TYPE_RUBY, MiningWorld.TYPE_COPPER, MiningWorld.TYPE_TIN, MiningWorld.TYPE_IRON, MiningWorld.TYPE_SILVER:
			mul = 0.65
		_:
			mul = 1.0
	return maxi(1, int(round(float(base_i) * mul)))


static func black_hole_burst_size_multiplier(type_id: int) -> float:
	match type_id:
		MiningWorld.TYPE_DIRT, MiningWorld.TYPE_PACKED_EARTH, MiningWorld.TYPE_CLAY, MiningWorld.TYPE_SANDSTONE:
			return 0.4
		MiningWorld.TYPE_STONE, MiningWorld.TYPE_SHALE, MiningWorld.TYPE_OBSIDIAN:
			return 0.8
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
	var _max: int = 0
	var _live_count: int = 0
	var _next_slot: int = 0

	var _particles_mmi: MultiMeshInstance2D
	var _shadows_mmi: MultiMeshInstance2D
	var _mm_p: MultiMesh
	var _mm_s: MultiMesh
	var _rng := RandomNumberGenerator.new()


	func build(field: MiningDebrisField, max_n: int) -> void:
		_max = max_n
		_live_count = 0
		_next_slot = 0

		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)

		_mm_p = MultiMesh.new()
		_mm_p.transform_format = MultiMesh.TRANSFORM_2D
		_mm_p.use_colors = true
		_mm_p.use_custom_data = true
		_mm_p.mesh = quad
		_mm_p.instance_count = max_n

		_mm_s = MultiMesh.new()
		_mm_s.transform_format = MultiMesh.TRANSFORM_2D
		_mm_s.use_colors = true
		_mm_s.use_custom_data = true
		_mm_s.mesh = quad
		_mm_s.instance_count = max_n

		var shadow_mat: ShaderMaterial = field._ensure_debris_circle_material(true)
		_shadows_mmi = MultiMeshInstance2D.new()
		_shadows_mmi.z_index = -1
		_shadows_mmi.texture = field._white
		_shadows_mmi.multimesh = _mm_s
		_shadows_mmi.material = shadow_mat

		var circ_mat: ShaderMaterial = field._ensure_debris_circle_material(false)
		_particles_mmi = MultiMeshInstance2D.new()
		_particles_mmi.texture = field._white
		_particles_mmi.multimesh = _mm_p
		_particles_mmi.material = circ_mat

		field.add_child(_shadows_mmi)
		field.add_child(_particles_mmi)

		for i in max_n:
			_hide_slot(i)


	func capacity() -> int:
		return _max


	func count_alive() -> int:
		return _live_count


	func next_slot() -> int:
		return _next_slot


	func clear_particles() -> void:
		for slot in _max:
			_hide_slot(slot)
		_live_count = 0
		_next_slot = 0


	func free_renderers() -> void:
		if _particles_mmi != null and is_instance_valid(_particles_mmi):
			_particles_mmi.queue_free()
		if _shadows_mmi != null and is_instance_valid(_shadows_mmi):
			_shadows_mmi.queue_free()
		_particles_mmi = null
		_shadows_mmi = null


	func spawn_particle(world_center: Vector2, col: Color, seed_i: int, size_mul: float) -> void:
		if _max <= 0:
			return
		var slot: int = _next_slot
		_next_slot = (_next_slot + 1) % _max
		_live_count = mini(_live_count + 1, _max)
		var cs: float = MiningWorld.CELL_SIZE_PX
		var half: float = cs * 0.45
		_rng.seed = seed_i
		var p: Vector2 = world_center + Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))

		var base_size: float = _rng.randf_range(3.2, 5.6) * size_mul
		var rot: float = _rng.randf_range(-0.55, 0.55)
		_sync_slot(slot, p, col, base_size, rot)


	func _sync_slot(slot: int, center: Vector2, col: Color, size: float, rot: float) -> void:
		var spawn_time_s: float = _shader_time_s()
		var xf_p := _xf_rot_scale_pos(rot, size, size, center)
		_mm_p.set_instance_transform_2d(slot, xf_p)
		_mm_p.set_instance_color(slot, col)
		_mm_p.set_instance_custom_data(slot, Color(spawn_time_s, float(slot), 0.0, 0.0))

		var xf_s := _xf_rot_scale_pos(rot * 0.35, size * 1.15, size * 0.38, center)
		_mm_s.set_instance_transform_2d(slot, xf_s)
		_mm_s.set_instance_color(slot, Color(0.0, 0.0, 0.0, 1.0))
		_mm_s.set_instance_custom_data(slot, Color(spawn_time_s, float(slot), 0.0, 0.0))


	func _hide_slot(slot: int) -> void:
		_mm_p.set_instance_transform_2d(slot, Transform2D())
		_mm_p.set_instance_color(slot, Color(0, 0, 0, 0))
		_mm_p.set_instance_custom_data(slot, Color(0, 0, 0, 0))
		_mm_s.set_instance_transform_2d(slot, Transform2D())
		_mm_s.set_instance_color(slot, Color(0, 0, 0, 0))
		_mm_s.set_instance_custom_data(slot, Color(0, 0, 0, 0))


	func _shader_time_s() -> float:
		return float(Time.get_ticks_msec()) * 0.001


	func _xf_rot_scale_pos(rot: float, sx: float, sy: float, origin: Vector2) -> Transform2D:
		var cr := cos(rot)
		var sn := sin(rot)
		return Transform2D(Vector2(cr * sx, sn * sx), Vector2(-sn * sy, cr * sy), origin)
