shader_type canvas_item;

// Low-res mask; nearest so texelFetch matches CPU grid.
uniform sampler2D mask_tex : source_color, filter_nearest;
uniform vec4 solid_color : source_color = vec4(0.25, 0.85, 0.45, 1.0);

const int HIGHLIGHT_MAX = 8;

uniform int highlight_count : hint_range(0, 8) = 0;
uniform vec2 highlight_cells[HIGHLIGHT_MAX];
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.92, 0.15, 1.0);
uniform float highlight_mix : hint_range(0.0, 1.0) = 0.72;

const int SUBDIV = 8;
const float ISO = 0.0;
const float SDF_RADIUS = 3.0;

float sample_mask(ivec2 t, ivec2 ts) {
	t = clamp(t, ivec2(0), ts - ivec2(1));
	return texelFetch(mask_tex, t, 0).r;
}

// Signed distance in texel units from neighbor fetches; negative = solid.
float corner_sdf_from_neighbors(ivec2 t, ivec2 ts) {
	t = clamp(t, ivec2(0), ts - ivec2(1));
	bool inside = sample_mask(t, ts) >= 0.5;
	float best = 1.0e9;
	int ri = int(SDF_RADIUS);
	for (int dy = -ri; dy <= ri; dy++) {
		for (int dx = -ri; dx <= ri; dx++) {
			ivec2 u = t + ivec2(dx, dy);
			if (u.x < 0 || u.y < 0 || u.x >= ts.x || u.y >= ts.y) {
				continue;
			}
			bool ins2 = sample_mask(u, ts) >= 0.5;
			if (ins2 != inside) {
				best = min(best, length(vec2(float(dx), float(dy))));
			}
		}
	}
	if (best > 1.0e8) {
		return inside ? -0.75 : 0.75;
	}
	return inside ? -best : best;
}

float edge_t(float va, float vb, float iso) {
	float d = vb - va;
	return abs(d) < 1e-6 ? 0.0 : clamp((iso - va) / d, 0.0, 1.0);
}

bool point_in_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 v0 = b - a;
	vec2 v1 = c - a;
	vec2 v2 = p - a;
	float d00 = dot(v0, v0);
	float d01 = dot(v0, v1);
	float d11 = dot(v1, v1);
	float d20 = dot(v2, v0);
	float d21 = dot(v2, v1);
	float denom = d00 * d11 - d01 * d01;
	if (abs(denom) < 1e-8) {
		return false;
	}
	float v = (d11 * d20 - d01 * d21) / denom;
	float w = (d00 * d21 - d01 * d20) / denom;
	float u = 1.0 - v - w;
	return u >= -1e-6 && v >= -1e-6 && w >= -1e-6;
}

// bn in texel space: x right, y down (0 = top row v_tl–v_tr).
float blerp_uv(vec2 bn, float v_tl, float v_tr, float v_br, float v_bl) {
	return mix(mix(v_tl, v_tr, bn.x), mix(v_bl, v_br, bn.x), bn.y);
}

// Scalar corners (BL, BR, TR, TL), y-up cell. Solid where field >= iso (use negated SDF so inside is positive).
bool ms_inside(vec4 k, vec2 q, float iso) {
	float a = k.x;
	float b = k.y;
	float c = k.z;
	float d = k.w;
	bool ba = a >= iso;
	bool bb = b >= iso;
	bool bc = c >= iso;
	bool bd = d >= iso;
	int idx = (ba ? 1 : 0) | (bb ? 2 : 0) | (bc ? 4 : 0) | (bd ? 8 : 0);

	if (idx == 0) {
		return false;
	}
	if (idx == 15) {
		return true;
	}

	if (idx == 5 || idx == 10) {
		float mid = 0.25 * (a + b + c + d);
		bool bm = mid >= iso;
		if (idx == 5) {
			idx = bm ? 7 : 13;
		} else {
			idx = bm ? 11 : 14;
		}
	}

	float eb = edge_t(a, b, iso);
	float et = edge_t(d, c, iso);
	float el = edge_t(a, d, iso);
	float er = edge_t(b, c, iso);

	vec2 BL = vec2(0.0, 0.0);
	vec2 BR = vec2(1.0, 0.0);
	vec2 TR = vec2(1.0, 1.0);
	vec2 TL = vec2(0.0, 1.0);
	vec2 Bm = vec2(eb, 0.0);
	vec2 Tm = vec2(et, 1.0);
	vec2 Lm = vec2(0.0, el);
	vec2 Rm = vec2(1.0, er);

	if (idx == 1) {
		return point_in_tri(q, BL, Bm, Lm);
	}
	if (idx == 2) {
		return point_in_tri(q, BR, Rm, Bm);
	}
	if (idx == 3) {
		return point_in_tri(q, BL, BR, Rm) || point_in_tri(q, BL, Rm, Lm);
	}
	if (idx == 4) {
		return point_in_tri(q, TR, Tm, Rm);
	}
	if (idx == 6) {
		return point_in_tri(q, BR, TR, Tm) || point_in_tri(q, BR, Tm, Bm);
	}
	if (idx == 7) {
		return !point_in_tri(q, TL, Tm, Lm);
	}
	if (idx == 8) {
		return point_in_tri(q, TL, Lm, Tm);
	}
	if (idx == 9) {
		return point_in_tri(q, BL, Bm, TL) || point_in_tri(q, Bm, TR, TL);
	}
	if (idx == 11) {
		return !point_in_tri(q, BR, Bm, Rm);
	}
	if (idx == 12) {
		return point_in_tri(q, TL, TR, Tm) || point_in_tri(q, TL, Tm, Lm);
	}
	if (idx == 13) {
		return !point_in_tri(q, BL, Bm, BR);
	}
	if (idx == 14) {
		return !point_in_tri(q, TR, Tm, BR);
	}
	return false;
}

void fragment() {
	ivec2 ts = textureSize(mask_tex, 0);
	if (ts.x < 1 || ts.y < 1) {
		discard;
	}

	vec2 p = UV * vec2(float(ts.x), float(ts.y));
	p = min(max(p, vec2(0.0)), vec2(float(ts.x)) - vec2(1e-4));

	ivec2 cell = ivec2(floor(p));
	vec2 f = fract(p);

	int x0 = clamp(cell.x, 0, ts.x - 1);
	int x1 = min(cell.x + 1, ts.x - 1);
	int y0 = clamp(cell.y, 0, ts.y - 1);
	int y1 = min(cell.y + 1, ts.y - 1);

	ivec2 c_tl = ivec2(x0, y0);
	ivec2 c_tr = ivec2(x1, y0);
	ivec2 c_br = ivec2(x1, y1);
	ivec2 c_bl = ivec2(x0, y1);

	float v_bl = corner_sdf_from_neighbors(c_bl, ts);
	float v_br = corner_sdf_from_neighbors(c_br, ts);
	float v_tr = corner_sdf_from_neighbors(c_tr, ts);
	float v_tl = corner_sdf_from_neighbors(c_tl, ts);

	float inv = 1.0 / float(SUBDIV);
	vec2 sf = f * float(SUBDIV);
	int six = min(int(floor(sf.x)), SUBDIV - 1);
	int siy = min(int(floor(sf.y)), SUBDIV - 1);
	vec2 ff = fract(sf);

	vec2 base = vec2(float(six), float(siy)) * inv;
	vec2 bn00 = base;
	vec2 bn10 = base + vec2(inv, 0.0);
	vec2 bn11 = base + vec2(inv, inv);
	vec2 bn01 = base + vec2(0.0, inv);

	// Macro-field samples at sub-rectangle corners (texel y-down): TL, TR, BR, BL.
	float s_tl = blerp_uv(bn00, v_tl, v_tr, v_br, v_bl);
	float s_tr = blerp_uv(bn10, v_tl, v_tr, v_br, v_bl);
	float s_br = blerp_uv(bn11, v_tl, v_tr, v_br, v_bl);
	float s_bl = blerp_uv(bn01, v_tl, v_tr, v_br, v_bl);

	vec2 q_sub = vec2(ff.x, 1.0 - ff.y);
	// ms_inside: x=BL, y=BR, z=TR, w=TL in y-up cell.
	vec4 k = -vec4(s_bl, s_br, s_tr, s_tl);

	if (!ms_inside(k, q_sub, ISO)) {
		discard;
	}

	COLOR = solid_color;

	int hc_n = clamp(highlight_count, 0, HIGHLIGHT_MAX);
	for (int hi = 0; hi < hc_n; hi++) {
		vec2 hcv = highlight_cells[hi];
		if (hcv.x < -0.5 || hcv.y < -0.5) {
			continue;
		}
		ivec2 hc = ivec2(int(hcv.x + 0.5), int(hcv.y + 0.5));
		if (cell == hc) {
			COLOR = mix(COLOR, highlight_tint, highlight_mix);
			break;
		}
	}
}
