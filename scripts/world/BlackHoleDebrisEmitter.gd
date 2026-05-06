extends GPUParticles2D
class_name BlackHoleDebrisEmitter
## Central planet2 debris sink: bursts from emit_particle + inward spiral ParticleProcessMaterial.

const GROUP := &"planet2_black_hole_debris"
const SHADER_PATH := "res://shaders/black_hole_particle.gdshader"

@export_range(0, 32) var particles_per_broken_cell: int = 0
@export_range(0.0, 32.0) var random_spawn_half_radius: float = 4.8

@export_range(0.0, 5000000.0) var gravity_strength: float = 180000.0
@export_range(1.0, 256.0) var gravity_softening: float = 24.0
@export_range(1.0, 2.0) var event_horizon_falloff_radius_mult = 1.08
@export_range(0.0, 8.0) var tangential_boost: float = 1.6
@export_range(-1.0, 1.0) var swirl_bias: float = 1.0
@export_range(0.0, 16.0) var radial_damping: float = 0.0
@export_range(0.0, 20000.0) var max_speed: float = 6000.0

@export_range(-1.0, 10.0) var burst_inward_bias: float = 0.35
@export_range(1.0, 12.0) var spaghetti_stretch: float = 3.4
@export_range(0.0, 120.0) var color_variation: float = 0.08

@export var shadow_offset: Vector2 = Vector2(1.2, 2.4)
@export_range(0.05, 1.0) var shadow_squish: float = 0.45
@export_range(0.0, 1.0) var shadow_alpha: float = 0.35
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 1.0)

var event_horizon_radius_px: float = 16.0
var event_horizon_falloff_radius_px: float = 18.0

var _mining_world: MiningWorld
var _spawn_rng := RandomNumberGenerator.new()
var _shadow_emitter: GPUParticles2D
var _flags_emit := GPUParticles2D.EMIT_FLAG_POSITION \
		| GPUParticles2D.EMIT_FLAG_VELOCITY \
		| GPUParticles2D.EMIT_FLAG_COLOR \
		| GPUParticles2D.EMIT_FLAG_ROTATION_SCALE


func _ready() -> void:
	add_to_group(GROUP)
	amount = 20000
	emitting = false
	draw_order = GPUParticles2D.DRAW_ORDER_REVERSE_LIFETIME
	lifetime = 600 #the engine stops rendering particles after this time even if they are still alive
	visibility_rect = Rect2(-16384.0, -16384.0, 32768.0, 32768.0)
	texture = _make_sphere_texture()
	material = _build_canvas_material(false)
	z_as_relative = false

	z_index = 2
	_build_shadow_emitter()
	_push_horizon_uniforms()


func _build_shadow_emitter() -> void:
	# Sibling particle node renders the shadow pass. Shares process_material
	# so its GPU simulation stays perfectly in lockstep with the main pass;
	# we mirror every emit_particle call into it so spawns match too.
	_shadow_emitter = GPUParticles2D.new()
	_shadow_emitter.name = "ShadowPass"
	_shadow_emitter.amount = amount
	_shadow_emitter.emitting = false
	_shadow_emitter.draw_order = draw_order
	_shadow_emitter.lifetime = lifetime
	_shadow_emitter.visibility_rect = visibility_rect
	_shadow_emitter.texture = texture
	_shadow_emitter.material = _build_canvas_material(true)
	_shadow_emitter.z_as_relative = false
	# Drawn first (lower z) so the real particles always sit on top.
	_shadow_emitter.z_index = z_index - 1
	# Share process_material so the GPU sim runs identically on both passes;
	# combined with mirrored emit_particle() calls this keeps shadows locked
	# to their owning particles every frame.
	_shadow_emitter.process_material = process_material
	add_child(_shadow_emitter)


func configure_event_horizon(radius_px: float) -> void:
	event_horizon_radius_px = maxf(radius_px, 1.0)
	event_horizon_falloff_radius_px = event_horizon_radius_px * event_horizon_falloff_radius_mult
	_push_horizon_uniforms()


func _push_horizon_uniforms() -> void:
	var mats: Array[ShaderMaterial] = []
	var mat := material as ShaderMaterial
	if mat != null:
		mats.append(mat)
	if _shadow_emitter != null:
		var smat := _shadow_emitter.material as ShaderMaterial
		if smat != null:
			mats.append(smat)
	for m in mats:
		m.set_shader_parameter(&"hole_center", global_position)
		m.set_shader_parameter(&"event_horizon_radius", event_horizon_radius_px)
		m.set_shader_parameter(&"event_horizon_falloff_radius", event_horizon_falloff_radius_px)
		m.set_shader_parameter(&"stretch_intensity", spaghetti_stretch)
		m.set_shader_parameter(&"shadow_offset", shadow_offset)
		m.set_shader_parameter(&"shadow_squish", shadow_squish)
		m.set_shader_parameter(&"shadow_alpha", shadow_alpha)
		m.set_shader_parameter(&"shadow_color", Vector3(shadow_color.r, shadow_color.g, shadow_color.b))
	var pm := process_material as ShaderMaterial
	if pm != null:
		pm.set_shader_parameter(&"hole_center", global_position)
		pm.set_shader_parameter(&"event_horizon_radius", event_horizon_radius_px)
		pm.set_shader_parameter(&"event_horizon_falloff_radius", event_horizon_falloff_radius_px)
		pm.set_shader_parameter(&"gravity_strength", gravity_strength)
		pm.set_shader_parameter(&"gravity_softening", gravity_softening)
		pm.set_shader_parameter(&"burst_inward_bias", burst_inward_bias)
		pm.set_shader_parameter(&"tangential_boost", tangential_boost)
		pm.set_shader_parameter(&"swirl_bias", swirl_bias)
		pm.set_shader_parameter(&"radial_damping", radial_damping)
		pm.set_shader_parameter(&"max_speed", max_speed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_push_horizon_uniforms()


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
	var hole := global_position
	for i in n:
		var seed_i := hash(Vector4(world_pos.x, world_pos.y, float(type_id), float(i)))
		var col := _vary_color(base_col, seed_i)
		_spawn_rng.seed = seed_i
		var offset := Vector2(
			_spawn_rng.randf_range(-random_spawn_half_radius, random_spawn_half_radius),
			_spawn_rng.randf_range(-random_spawn_half_radius, random_spawn_half_radius))
		var p := world_pos + offset
		var to_hole := hole - p
		var dist := maxf(to_hole.length(), 0.001)
		var radial_dir := to_hole / dist
		var tangent_dir := Vector2(-radial_dir.y, radial_dir.x)
		if _spawn_rng.randf() < 0.5:
			tangent_dir = -tangent_dir
		# Spawn at rest: process shader pulls particle into the hole.
		var vel := Vector2.ZERO
		var rot := tangent_dir.angle()
		var sx := _spawn_rng.randf_range(0.2, 0.25) * sz_mul 
		var sy := sx
		var xf := _xf_rot_scale_pos(rot, sx, sy, p)
		emit_particle(xf, vel, col, Color(0.0, 0.0, 0.0, 0.0), _flags_emit)
		if _shadow_emitter != null:
			_shadow_emitter.emit_particle(xf, vel, col, Color(0.0, 0.0, 0.0, 0.0), _flags_emit)


func _vary_color(base: Color, seed_i: int) -> Color:
	_spawn_rng.seed = seed_i
	var dv := color_variation
	return Color(
		clampf(base.r + _spawn_rng.randf_range(-dv, dv), 0.0, 1.0),
		clampf(base.g + _spawn_rng.randf_range(-dv, dv), 0.0, 1.0),
		clampf(base.b + _spawn_rng.randf_range(-dv, dv), 0.0, 1.0),
		base.a,
	)



func _make_sphere_texture() -> Texture2D:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size - 1) * 0.5
	var r := c
	for y in size:
		for x in size:
			var dx := float(x) - c
			var dy := float(y) - c
			var d := sqrt(dx * dx + dy * dy) / r
			var a := clampf(1.0 - smoothstep(0.86, 1.0, d), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _build_canvas_material(is_shadow: bool = false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	mat.set_shader_parameter(&"render_shadow", is_shadow)
	return mat


func _xf_rot_scale_pos(rot: float, sx: float, sy: float, origin: Vector2) -> Transform2D:
	var cr := cos(rot)
	var sn := sin(rot)
	return Transform2D(Vector2(cr * sx, sn * sx), Vector2(-sn * sy, cr * sy), origin)
