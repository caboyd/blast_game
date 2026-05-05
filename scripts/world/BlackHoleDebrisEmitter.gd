extends GPUParticles2D
class_name BlackHoleDebrisEmitter
## Central planet2 debris sink: bursts from emit_particle + inward spiral ParticleProcessMaterial.

const GROUP := &"planet2_black_hole_debris"

@export_range(4, 32) var particles_per_broken_cell: int = 6
@export_range(0.0, 32.0) var spawn_half_extent_px: float = 4.8
@export_range(0.0, 8000.0) var burst_outward_velocity_min: float = 140.0
@export_range(0.0, 8000.0) var burst_outward_velocity_max: float = 420.0
@export_range(0.0, 120.0) var color_variation: float = 0.08

var _mining_world: MiningWorld
var _spawn_rng := RandomNumberGenerator.new()
var _flags_emit := GPUParticles2D.EMIT_FLAG_POSITION \
		| GPUParticles2D.EMIT_FLAG_VELOCITY \
		| GPUParticles2D.EMIT_FLAG_COLOR \
		| GPUParticles2D.EMIT_FLAG_ROTATION_SCALE


func _ready() -> void:
	add_to_group(GROUP)
	amount = 20000
	fixed_fps = 0
	local_coords = false
	emitting = false
	explosiveness = 0.0
	randomness = 0.0
	interp_to_end = 0.0
	draw_order = GPUParticles2D.DRAW_ORDER_REVERSE_LIFETIME
	lifetime = 5.25
	process_material = _build_process_material()
	visibility_rect = Rect2(-16384.0, -16384.0, 32768.0, 32768.0)
	texture = _make_white_px_texture()
	z_as_relative = false
	z_index = 2


func bind_mining_world(world: MiningWorld) -> void:
	_mining_world = world


func emit_burst(world_pos: Vector2, type_id: int) -> void:
	if _mining_world == null:
		return
	var n := MiningDebrisField.black_hole_burst_count(type_id, particles_per_broken_cell)
	if n <= 0:
		return
	var base_col: Color = _mining_world.display_color_for_mined_type(type_id)
	var sz_mul := MiningDebrisField.black_hole_burst_size_multiplier(type_id)
	var half_extent: float = spawn_half_extent_px
	for i in n:
		var seed_i := hash(Vector4(world_pos.x, world_pos.y, float(type_id), float(i)))
		var col := _vary_color(base_col, seed_i)
		_spawn_rng.seed = seed_i
		var offset := Vector2(
			_spawn_rng.randf_range(-half_extent, half_extent),
			_spawn_rng.randf_range(-half_extent, half_extent))
		var p := world_pos + offset
		var ang := _spawn_rng.randf() * TAU
		var sp := _spawn_rng.randf_range(burst_outward_velocity_min, burst_outward_velocity_max)
		var vel := Vector2.from_angle(ang) * sp
		var rot := _spawn_rng.randf_range(-0.45, 0.45)
		var sx := _spawn_rng.randf_range(4.8, 7.8) * sz_mul
		var sy := sx * 1.06
		var xf := _xf_rot_scale_pos(rot, sx, sy, p)
		emit_particle(xf, vel, col, Color(0.0, 0.0, 0.0, 0.0), _flags_emit)


func _vary_color(base: Color, seed_i: int) -> Color:
	_spawn_rng.seed = seed_i
	var dv := color_variation
	return Color(
		clampf(base.r + _spawn_rng.randf_range(-dv, dv), 0.0, 1.0),
		clampf(base.g + _spawn_rng.randf_range(-dv, dv), 0.0, 1.0),
		clampf(base.b + _spawn_rng.randf_range(-dv, dv), 0.0, 1.0),
		base.a,
	)


func _build_process_material() -> ParticleProcessMaterial:
	var ppm := ParticleProcessMaterial.new()
	ppm.particle_flag_disable_z = true
	ppm.particle_flag_align_y = true
	ppm.lifetime_randomness = 0.32
	ppm.direction = Vector3.ZERO
	ppm.spread = 180.0
	ppm.initial_velocity_min = 1.0
	ppm.initial_velocity_max = 1.5
	ppm.angular_velocity_min = -14.0
	ppm.angular_velocity_max = 14.0
	ppm.radial_accel_min = -760.0
	ppm.radial_accel_max = -420.0
	ppm.orbit_velocity_min = 0.12
	ppm.orbit_velocity_max = 0.52
	ppm.tangential_accel_min = 24.0
	ppm.tangential_accel_max = 110.0
	ppm.linear_accel_min = -10.0
	ppm.linear_accel_max = -2.0
	ppm.damping_min = 0.25
	ppm.damping_max = 0.9

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.06))
	scale_curve.add_point(Vector2(0.45, 2.05))
	scale_curve.add_point(Vector2(1.0, 0.02))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	ppm.scale_min = 0.75
	ppm.scale_max = 1.08
	ppm.scale_curve = scale_tex

	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
	grad.add_point(0.25, Color(1.0, 1.0, 1.0, 0.94))
	grad.add_point(0.78, Color(1.0, 1.0, 1.0, 1.0))
	grad.add_point(1.0, Color(1.0, 1.0, 1.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	ppm.color_ramp = grad_tex

	return ppm


func _make_white_px_texture() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _xf_rot_scale_pos(rot: float, sx: float, sy: float, origin: Vector2) -> Transform2D:
	var cr := cos(rot)
	var sn := sin(rot)
	return Transform2D(Vector2(cr * sx, sn * sx), Vector2(-sn * sy, cr * sy), origin)
