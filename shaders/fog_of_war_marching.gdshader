shader_type canvas_item;

uniform sampler2D reveal_tex : filter_nearest;
uniform vec2 fog_world_origin = vec2(0.0, 0.0);
// Planet-tinted fog: mid = main haze tint, dark = deep shadow layer (see MiningWorld.set_fog_shader_colors).
uniform vec4 fog_mid : source_color = vec4(0.42, 0.28, 0.18, 1.0);
uniform vec4 fog_dark : source_color = vec4(0.038, 0.025, 0.016, 1.0);
uniform float edge_soft : hint_range(0.0, 0.5) = 0.13;
uniform float edge_alpha_fade : hint_range(0.0, 1.0) = 0.58;
// How much the dark layer sits over the base fog tint (0 = base only, 1 = dark only).
uniform float dark_overlay : hint_range(0.0, 1.0) = 0.82;
// Global brightness pulse amplitude (0.02 ~= +/-2% intensity).
uniform float pulse_amplitude : hint_range(0.0, 0.1) = 0.02;
uniform float pulse_speed : hint_range(0.0, 4.0) = 0.4;
// Two simplex fields (lower scale = bigger blobs). Pulse crossfades between them.
uniform float noise_scale_a : hint_range(0.003, 0.3) = 0.098;
uniform float noise_scale_b : hint_range(0.003, 0.3) = 0.105;
uniform vec2 noise_b_offset = vec2(47.23, 108.91);
// Drift velocity per noise layer (noise UV units / sec); magnitude controls slowness.
uniform vec2 noise_drift_a = vec2(0.217, 0.110);
uniform vec2 noise_drift_b = vec2(-0.213, 0.116);
uniform float noise_strength : hint_range(0.0, 0.25) = 0.355;
// Mix factor swings within [0.5 ± 0.5 * depth]: depth 1 = full A↔B, depth 0 = frozen 50/50 blend.
uniform float noise_pulse_speed : hint_range(0.1, 4.0) = 1.55;
uniform float noise_pulse_depth : hint_range(0.0, 1.0) = 0.2;

vec3 mod289_3(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec2 mod289_2(vec2 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec3 permute289(vec3 x) {
	return mod289_3(((x * 34.0) + 1.0) * x);
}

// Ian McEwan / Ashima Arts — 2D simplex, ~[-1, 1].
float simplex_noise_2d(vec2 v) {
	const vec4 C = vec4(
			0.211324865405187,
			0.366025403784439,
			-0.577350269189626,
			0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = mod289_2(i);
	vec3 p = permute289(
			permute289(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(
			0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)),
			0.0);
	m = m * m;
	m = m * m;
	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

float blend_noise(vec2 world_xy) {
	vec2 va = TIME * noise_drift_a;
	vec2 vb = TIME * noise_drift_b;
	float na = simplex_noise_2d(world_xy * noise_scale_a + va);
	float nb = simplex_noise_2d(world_xy * noise_scale_b + noise_b_offset + vb);
	float wb = 0.5 + sin(TIME * noise_pulse_speed) * 0.5 * noise_pulse_depth;
	return mix(na, nb, wb);
}

float sample_reveal(ivec2 t, ivec2 tex_size) {
	t = clamp(t, ivec2(0), tex_size - ivec2(1));
	return texelFetch(reveal_tex, t, 0).r;
}

float reveal_gradient_length(float s00, float s10, float s01, float s11, vec2 f) {
	float dx = mix(s10 - s00, s11 - s01, f.y);
	float dy = mix(s01 - s00, s11 - s10, f.x);
	return max(length(vec2(dx, dy)), 0.001);
}

void fragment() {
	ivec2 tex_size = textureSize(reveal_tex, 0);
	if (tex_size.x < 1 || tex_size.y < 1) {
		vec3 rgb = mix(fog_mid.rgb, fog_dark.rgb, dark_overlay);
		float n = blend_noise(fog_world_origin);
		rgb *= 1.0 + n * noise_strength;
		float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amplitude;
		COLOR = vec4(rgb * pulse, 1.0);
	} else {
		vec2 p = UV * vec2(float(tex_size.x), float(tex_size.y)) - vec2(0.5);
		vec2 fp = floor(p);
		vec2 f = p - fp;
		ivec2 cell = ivec2(int(fp.x), int(fp.y));

		float s00 = sample_reveal(cell + ivec2(0, 0), tex_size);
		float s10 = sample_reveal(cell + ivec2(1, 0), tex_size);
		float s01 = sample_reveal(cell + ivec2(0, 1), tex_size);
		float s11 = sample_reveal(cell + ivec2(1, 1), tex_size);

		float reveal = mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
		float threshold = 0.5;
		float edge_width = max(edge_soft, 0.001);
		float signed_edge_distance = (reveal - threshold) / reveal_gradient_length(s00, s10, s01, s11, f);
		float fog_alpha = 1.0 - smoothstep(-edge_width, edge_width, signed_edge_distance);
		if (fog_alpha <= 0.001) {
			discard;
		}

		vec3 fog_rgb = mix(fog_mid.rgb, fog_dark.rgb, dark_overlay);
		float n = blend_noise(fog_world_origin + p);
		fog_rgb *= 1.0 + n * noise_strength;
		float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amplitude;
		fog_rgb *= pulse;

		float edge_density = smoothstep(0.0, 1.0, fog_alpha);
		float edge_fade = smoothstep(0.0, edge_alpha_fade, fog_alpha);
		float alpha = mix(0.0, 1.0, edge_fade) * mix(0.90, 1.0, edge_density);
		COLOR = vec4(fog_rgb, alpha);
	}
}
