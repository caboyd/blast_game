shader_type canvas_item;
render_mode world_vertex_coords;

uniform bool render_shadow = false;
uniform float debris_time_s = 0.0;
uniform vec2 player_global_location = vec2(0.0);
uniform vec2 player_global_velocity = vec2(0.0);
uniform float circular_next_slot = 0.0;
uniform float circular_live_count = 0.0;
uniform float circular_capacity = 1.0;
uniform float old_particle_fade_window = 100.0;
uniform float repel_radius_px = 48.0;
uniform vec2 repel_ship_forward = vec2(1.0, 0.0);
uniform float repel_strength = 520.0;
uniform float spring_strength = 38.0;
uniform float spawn_z_velocity_min = 18.0;
uniform float spawn_z_velocity_max = 52.0;
uniform float gravity_z = -220.0;
uniform float z_scale = 0.008;
uniform float repel_z_kick_max = 36.0;
uniform float repel_z_falloff_threshold = 0.42;
uniform vec2 shadow_offset = vec2(1.2, 2.4);
uniform float shadow_alpha = 0.22;

float debris_rand(vec2 p, float salt) {
	return fract(sin(dot(vec3(p, salt), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float circular_age_alpha(float slot) {
	float capacity = max(circular_capacity, 1.0);
	float live_count = clamp(circular_live_count, 0.0, capacity);
	if (live_count < capacity || old_particle_fade_window <= 0.0) {
		return 1.0;
	}
	float rank_from_oldest = mod(slot - circular_next_slot + capacity, capacity);
	float fade_last_rank = min(old_particle_fade_window, capacity) - 1.0;
	if (rank_from_oldest >= fade_last_rank) {
		return 1.0;
	}
	return clamp(rank_from_oldest / max(fade_last_rank, 1.0), 0.0, 1.0);
}

void vertex() {
	float spawned_s = INSTANCE_CUSTOM.x;
	float slot = INSTANCE_CUSTOM.y;
	float age_s = max(debris_time_s - spawned_s, 0.0);

	vec2 center_world = MODEL_MATRIX[3].xy;
	vec2 rel = VERTEX - center_world;

	// Circular repel anchored at drill; ship forward still drives pass-timing for the Z kick.
	vec2 fwd_raw = repel_ship_forward;
	float fwd_len = length(fwd_raw);
	vec2 fwd = fwd_len > 1e-5 ? fwd_raw / fwd_len : vec2(1.0, 0.0);
	vec2 perp_fwd = vec2(-fwd.y, fwd.x);

	vec2 d = center_world - player_global_location;
	float dst = length(d);
	float fwd_along = dot(d, fwd);
	float aft = max(0.0, -fwd_along);

	float eps = 1e-5;
	float Rmul = max(repel_radius_px, 0.001);
	float dn = dst / Rmul;
	float side_abs = abs(dot(d, perp_fwd));

	float falloff = 0.0;
	bool in_repel = dst > eps && dn <= 1.0;
	vec2 repel_offset = vec2(0.0);
	if (in_repel) {
		falloff = sqrt(max(1.0 - dn, 0.0));
		float spring = max(spring_strength, 0.001);
		vec2 radial = d / dst;
		repel_offset = radial * (repel_strength / spring) * falloff;
	}

	float z_seed = debris_rand(center_world, spawned_s);
	float z_vel = mix(min(spawn_z_velocity_min, spawn_z_velocity_max), max(spawn_z_velocity_min, spawn_z_velocity_max), z_seed);
	float z_ball = max(0.0, z_vel * age_s + 0.5 * gravity_z * age_s * age_s);
	float z_repel = 0.0;
	float forward_speed = dot(player_global_velocity, fwd);
	if (forward_speed > 1.0 && fwd_along < 0.0) {
		float kick_age = aft / forward_speed;
		float closest_falloff = sqrt(max(1.0 - side_abs / Rmul, 0.0));
		if (kick_age >= 0.0 && closest_falloff > repel_z_falloff_threshold) {
			float t = clamp((closest_falloff - repel_z_falloff_threshold) / max(1.0 - repel_z_falloff_threshold, 1e-4), 0.0, 1.0);
			float kick_height = repel_z_kick_max * t;
			z_repel = max(0.0, kick_height + 0.5 * gravity_z * kick_age * kick_age);
		}
	}
	float z = max(0.0, z_ball + z_repel);
	float lift_scale = 1.0 + z * z_scale;
	float age_alpha = circular_age_alpha(slot);

	if (render_shadow) {
		float height_fade = clamp(1.0 - z * 0.035, 0.15, 1.0);
		VERTEX = center_world + repel_offset + shadow_offset + rel * lift_scale;
		COLOR.a *= shadow_alpha * height_fade * age_alpha;
	} else {
		VERTEX = center_world + repel_offset + vec2(0.0, -z) + rel * lift_scale;
		COLOR.a *= age_alpha;
	}
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float mask = 1.0 - smoothstep(0.92, 1.0, r);
	vec4 tex_sample = texture(TEXTURE, UV);
	COLOR = tex_sample * COLOR;
	COLOR.a *= mask;
}
