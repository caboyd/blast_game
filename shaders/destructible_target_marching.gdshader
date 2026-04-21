shader_type canvas_item;

// Low-res grid; nearest so texelFetch matches CPU grid.
uniform sampler2D mask_tex : source_color, filter_nearest;
// R = type id / 255, G = hp ratio 0..1
uniform sampler2D type_tex : source_color, filter_nearest;

uniform int type_count : hint_range(0, 8) = 3;
uniform vec4 type_colors[8];

const int HIGHLIGHT_MAX = 8;

uniform int highlight_count : hint_range(0, 8) = 0;
uniform vec2 highlight_cells[HIGHLIGHT_MAX];
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.92, 0.15, 1.0);
uniform float highlight_mix : hint_range(0.0, 1.0) = 0.72;

// Contour outline between differing materials / material vs empty.
uniform vec4 edge_color : source_color = vec4(0.04, 0.04, 0.06, 1.0);
// Width in bilinear-weight units; larger = thicker outline.
uniform float edge_width : hint_range(0.0, 0.5) = 0.0;
// Pixel smoothing width for alpha boundary (in weight units).
uniform float alpha_aa : hint_range(0.0, 0.5) = 0.08;

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
	int best_id = 0;
	float best_w = -1.0;
	float best_hp_sum = 0.0;
	int second_id = 0;
	float second_w = -1.0;

	for (int i = 1; i < 8; i++) {
		if (i >= type_count) {
			break;
		}
		float w = 0.0;
		float wh = 0.0;
		if (s00.mid == i) { w += w00; wh += w00 * s00.hp; }
		if (s10.mid == i) { w += w10; wh += w10 * s10.hp; }
		if (s01.mid == i) { w += w01; wh += w01 * s01.hp; }
		if (s11.mid == i) { w += w11; wh += w11 * s11.hp; }
		if (w > best_w) {
			second_w = best_w;
			second_id = best_id;
			best_w = w;
			best_id = i;
			best_hp_sum = wh;
		} else if (w > second_w) {
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

	float hp_ratio = best_hp_sum / max(best_w, 1e-5);
	vec4 base = type_colors[best_id];
	vec3 rgb = base.rgb * mix(0.45, 1.0, clamp(hp_ratio, 0.0, 1.0));

	// Outline at contour between differing materials, or along outer boundary.
	// Inner contour: best vs other-material second.
	float inner_edge = 0.0;
	if (second_w > 0.0 && second_id != best_id) {
		float diff = best_w - second_w;
		inner_edge = 1.0 - smoothstep(0.0, edge_width, diff);
	}
	// Outer contour: against empty (missing weight in the 2x2).
	float outer_diff = best_w - (total - best_w);
	float outer_edge = 1.0 - smoothstep(0.0, edge_width, outer_diff);
	// Also draw edge where solid meets empty beyond the 2x2 footprint.
	outer_edge = max(outer_edge, 1.0 - smoothstep(0.5, 0.5 + edge_width, coverage));

	float e = clamp(max(inner_edge, outer_edge), 0.0, 1.0);
	rgb = mix(rgb, edge_color.rgb, e * edge_color.a);

	vec4 col = vec4(rgb, base.a * alpha);

	// Highlight cell resolution: pick the solid corner of the winning material
	// whose bilinear weight dominates this pixel.
	ivec2 cc = i00;
	float hl_best = -1.0;
	if (s00.present > 0.5 && s00.mid == best_id && w00 > hl_best) { hl_best = w00; cc = i00 + ivec2(0, 0); }
	if (s10.present > 0.5 && s10.mid == best_id && w10 > hl_best) { hl_best = w10; cc = i00 + ivec2(1, 0); }
	if (s01.present > 0.5 && s01.mid == best_id && w01 > hl_best) { hl_best = w01; cc = i00 + ivec2(0, 1); }
	if (s11.present > 0.5 && s11.mid == best_id && w11 > hl_best) { hl_best = w11; cc = i00 + ivec2(1, 1); }

	int hc_n = clamp(highlight_count, 0, HIGHLIGHT_MAX);
	for (int hi = 0; hi < hc_n; hi++) {
		vec2 hcv = highlight_cells[hi];
		if (hcv.x < -0.5 || hcv.y < -0.5) {
			continue;
		}
		ivec2 hc = ivec2(int(hcv.x + 0.5), int(hcv.y + 0.5));
		if (cc == hc) {
			col.rgb = mix(col.rgb, highlight_tint.rgb, highlight_mix);
			break;
		}
	}

	COLOR = col;
}
