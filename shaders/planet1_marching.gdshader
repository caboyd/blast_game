shader_type canvas_item;

// Low-res grid; nearest so texelFetch matches CPU grid.
uniform sampler2D mask_tex : source_color, filter_nearest;
// R = type id / 255, G = hp ratio 0..1
uniform sampler2D type_tex : source_color, filter_nearest;

uniform int type_count : hint_range(0, 16) = 6;
uniform vec4 type_colors[16];

// Contour outline between differing materials / material vs empty.
uniform vec4 edge_color : source_color = vec4(0.04, 0.04, 0.06, 1.0);
// Width in bilinear-weight / rank-diff units for boundaries where ranks compete (bias shifts dominance).
uniform float edge_width_between_materials : hint_range(0.0, 0.5) = 0.12;

// Pixel smoothing width for alpha boundary (in weight units).
uniform float alpha_aa : hint_range(0.0, 0.5) = 0.08;

// Ranking boost toward higher material indices (1..type_count-1). At 0, off. Largest index gets full +bias (×(1+bias)).
uniform float high_index_weight_bias : hint_range(0.0, 2.0) = 1.0;

// Top-left of the view texture in world cell coords; fuel uses `fuel_world_origin + p` so the
// galaxy scroll is world-locked and does not jump when the camera pans.
uniform vec2 fuel_world_origin = vec2(0.0, 0.0);

struct CellSample {
	int mid;
	float hp;
	float present;
};

CellSample sample_cell(ivec2 t, ivec2 ts, int tc1) {
	CellSample s;
	t = clamp(t, ivec2(0), ts - ivec2(1));
	float m = texelFetch(mask_tex, t, 0).r;
	vec4 td = texelFetch(type_tex, t, 0);
	s.hp = clamp(td.g, 0.0, 1.0);
	s.present = (m >= 0.5 && td.g > 0.01) ? 1.0 : 0.0;
	s.mid = int(clamp(round(td.r * 255.0), 0.0, float(tc1)));
	return s;
}

// TYPE_* in MiningWorld.gd (must match consts).
const int MATERIAL_DIRT = 1;
const int MATERIAL_FUEL = 4;
const vec3 DEFAULT_FUEL_MATERIAL_COLOR = vec3(0.22, 0.15, 0.10);

// `world_cell_uv`: absolute world grid position (float; matches MiningWorld cell indices + sub-texel).
vec3 fuel_cell_rgb(vec2 world_cell_uv, float hp_ratio, float time_sec, vec3 material_color) {
	// ========== Fuel tunables (edit these) ==========
	vec2 scroll_dir_raw = vec2(1.0, 0.38);
	vec2 world_bias = vec2(0.416, 0.203);
	float drift_far = 0.0036;
	float drift_mid = 0.0068;
	float drift_near = 0.0108;
	float scale_far = 0.263;
	float scale_mid = 0.417;
	float scale_near = 0.683;
	float far_kx = 1.85;
	float far_ky_in = 1.45;
	float far_ky = 1.65;
	float far_kx_in = 1.15;
	vec2 mid_dot = vec2(1.55, 0.98);
	float mid_len_k = 1.25;
	float mid_len_w = 2.75;
	float near_kx = 2.35;
	float near_ky = 2.05;
	vec3 col_void = vec3(0.065, 0.04, 0.024);
	vec3 col_dust = vec3(0.13, 0.085, 0.052);
	vec3 col_neb = vec3(0.21, 0.135, 0.082);
	vec3 col_ember = vec3(0.36, 0.24, 0.13);
	float mix_neb_lo = 0.22;
	float mix_neb_hi = 0.9;
	float mix_neb_amt = 0.52;
	float mix_emb_lo = 0.52;
	float mix_emb_hi = 0.94;
	float mix_emb_amt = 0.38;
	float hp_damage_mul = 0.87;
	float spark_scale = 8.513;
	vec2 spark_origin = vec2(1.718, 0.427);
	float drift_spark = 0.152;
	// Constant spec-field drift (UV units per second); monotonic, same direction over time.
	vec2 spec_drift_vel = vec2(0.411, -0.238);
	float spark_j_mul = 0.6;
	float star_rad_in = 0.22;
	float star_rad_out = 0.44;
	float star_pick_lo = 0.84;
	float star_pick_hi = 0.93;
	vec3 col_star = vec3(0.92, 0.84, 0.62);
	float star_bright = 0.85;
	vec2 phase_world = vec2(0.107, 0.091);
	float phase_world_scale = 2.15;
	vec2 phase_spark = vec2(0.67, 0.59);
	float phase_spark_scale = 0.92;
	float pulse_rate = 2.95;
	float pulse_dim = 0.0;
	float pulse_bright = 0.4;
	// ========== end tunables ==========

	float t = time_sec;
	vec2 scroll_dir = normalize(scroll_dir_raw);
	vec2 u = world_cell_uv + world_bias;
	vec2 drift = t * scroll_dir;

	vec2 far_p = u * scale_far + drift * drift_far;
	float far_n = sin(far_p.x * far_kx + sin(far_p.y * far_ky_in)) * sin(far_p.y * far_ky + sin(far_p.x * far_kx_in));
	far_n = far_n * 0.5 + 0.5;

	vec2 mid_p = u * scale_mid + drift * drift_mid;
	float mid_n = sin(dot(mid_p, mid_dot) + sin(length(mid_p * mid_len_k) * mid_len_w));
	mid_n = mid_n * 0.5 + 0.5;

	vec2 near_p = u * scale_near + drift * drift_near;
	float near_n = sin(near_p.x * near_kx) * cos(near_p.y * near_ky);
	near_n = near_n * 0.5 + 0.5;

	vec3 body = mix(col_void, col_dust, far_n);
	body = mix(body, col_neb, smoothstep(mix_neb_lo, mix_neb_hi, mid_n) * mix_neb_amt);
	body = mix(body, col_ember, smoothstep(mix_emb_lo, mix_emb_hi, mid_n * near_n) * mix_emb_amt);
	body = mix(body * hp_damage_mul, body, hp_ratio);

	vec2 spec_drift = t * spec_drift_vel;
	vec2 sp_p = u * spark_scale + spark_origin + drift * drift_spark + spec_drift;
	vec2 sp_id = floor(sp_p);
	vec2 sp_f = fract(sp_p) - vec2(0.5);
	float sp_h = fract(sin(dot(sp_id, vec2(127.1, 311.7))) * 43758.5453);
	vec2 sp_j = vec2(fract(sp_h * 17.0), fract(sp_h * 47.3)) - vec2(0.5);
	float d_star = length(sp_f - sp_j * spark_j_mul);
	float star_core = 1.0 - smoothstep(star_rad_in, star_rad_out, d_star);
	float star_mask = smoothstep(star_pick_lo, star_pick_hi, sp_h) * star_core;
	vec3 star_c = col_star * star_mask * star_bright;

	float ph_base = dot(world_cell_uv, phase_world) * phase_world_scale;
	float ph_star = ph_base + dot(sp_id, phase_spark) * phase_spark_scale;
	float b = sin(t * pulse_rate + ph_star) * 0.5 + 0.5;
	float breathe_star = mix(pulse_dim, pulse_bright, b * b);

	vec3 tint = material_color / max(DEFAULT_FUEL_MATERIAL_COLOR, vec3(0.001));
	return (body + star_c * breathe_star) * tint;
}

void fragment() {
	ivec2 ts = textureSize(mask_tex, 0);
	if (ts.x < 1 || ts.y < 1) {
		discard;
	}

	int tc1 = max(type_count - 1, 0);

	// Shift so sample points coincide with cell centers (integer coords).
	vec2 p = UV * vec2(float(ts.x), float(ts.y)) - vec2(0.5);
	vec2 fp = floor(p);
	vec2 f = p - fp;

	ivec2 i00 = ivec2(int(fp.x), int(fp.y));
	CellSample s00 = sample_cell(i00 + ivec2(0, 0), ts, tc1);
	CellSample s10 = sample_cell(i00 + ivec2(1, 0), ts, tc1);
	CellSample s01 = sample_cell(i00 + ivec2(0, 1), ts, tc1);
	CellSample s11 = sample_cell(i00 + ivec2(1, 1), ts, tc1);

	float w00 = (1.0 - f.x) * (1.0 - f.y) * s00.present;
	float w10 = f.x * (1.0 - f.y) * s10.present;
	float w01 = (1.0 - f.x) * f.y * s01.present;
	float w11 = f.x * f.y * s11.present;

	float total = w00 + w10 + w01 + w11;

	// Per-material bilinear weight and weighted hp. Find top two materials.
	// high_index_weight_bias scales ranking only (higher type id favored); hp uses raw winner weight.
	// Outlines use best_rank/second_rank so dominance matches color.
	int best_id = 0;
	float best_w = -1.0;
	float best_hp_sum = 0.0;
	int second_id = 0;
	float second_w = -1.0;
	float best_rank = -1.0;
	float second_rank = -1.0;

	for (int i = 1; i < 16; i++) {
		if (i >= type_count) {
			break;
		}
		float w = 0.0;
		float wh = 0.0;
		if (s00.mid == i) { w += w00; wh += w00 * s00.hp; }
		if (s10.mid == i) { w += w10; wh += w10 * s10.hp; }
		if (s01.mid == i) { w += w01; wh += w01 * s01.hp; }
		if (s11.mid == i) { w += w11; wh += w11 * s11.hp; }
		float hi_t = float(i - 1) / max(float(type_count - 2), 1.0);
		float rank = w * (1.0 + high_index_weight_bias * hi_t);
		if (rank > best_rank) {
			second_rank = best_rank;
			second_w = best_w;
			second_id = best_id;
			best_rank = rank;
			best_w = w;
			best_id = i;
			best_hp_sum = wh;
		} else if (rank > second_rank) {
			second_rank = rank;
			second_w = w;
			second_id = i;
		}
	}

	// No material present at this sample point.
	if (best_id == 0 || best_w <= 0.0) {
		discard;
	}

	// Coverage: fraction of the 2x2 footprint that is solid.
	// Contour happens at coverage ~0.5 so shape is smooth, not blocky.
	float coverage = total;
	float alpha = smoothstep(0.5 - alpha_aa, 0.5 + alpha_aa, coverage);
	if (alpha <= 0.001) {
		discard;
	}

	// float hp_ratio = clamp(best_hp_sum / max(best_w, 1e-5), 0.0, 1.0);
	// float damage_taken = 1.0 - hp_ratio;
	vec4 base = type_colors[best_id];
	vec3 rgb = base.rgb;
	
	// if (best_id == MATERIAL_FUEL) {
	// 	rgb = fuel_cell_rgb(fuel_world_origin + p, hp_ratio, TIME, base.rgb);
	// } else {
	// 	rgb = base.rgb * mix(0.45, 1.0, hp_ratio);
	// }

	// Outline at contour between differing materials, or along outer boundary.
	// Inner contour: best vs second using rank (matches color choice).
	float inner_edge = 0.0;
	if (second_w > 0.0 && second_id != best_id && second_rank >= 0.0) {
		float diff = best_rank - second_rank;
		inner_edge = 1.0 - smoothstep(0.0, edge_width_between_materials, diff);
	}
	// Outer contour: winning material vs all other solid mass in the 2×2 (rank for winner so bias stays consistent).
	float other_w = total - best_w;
	float outer_diff = best_rank - other_w;
	float outer_edge = 1.0 - smoothstep(0.0, edge_width_between_materials, outer_diff);
	// Also draw edge where solid meets empty beyond the 2x2 footprint.
	// Width for solid vs empty boundary (coverage smoothstep); independent of high_index_weight_bias.
	float edge_width_material_empty = edge_width_between_materials / (1.0 + high_index_weight_bias);
	outer_edge = max(outer_edge, 1.0 - smoothstep(0.5, 0.5 + edge_width_material_empty, coverage));

	float e = clamp(max(inner_edge, outer_edge), 0.0, 1.0);
	rgb = mix(rgb, edge_color.rgb, e * edge_color.a);

	COLOR = vec4(rgb, base.a * alpha);
}
