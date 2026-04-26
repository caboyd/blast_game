shader_type canvas_item;

uniform sampler2D reveal_tex : filter_nearest;
uniform vec4 fog_color : source_color = vec4(0.02, 0.02, 0.05, 0.92);
uniform float edge_soft : hint_range(0.0, 0.5) = 0.12;

void fragment() {
	ivec2 ts = textureSize(reveal_tex, 0);
	if (ts.x < 1 || ts.y < 1) {
		COLOR = fog_color;
	} else {
		vec2 p = UV * vec2(float(ts.x), float(ts.y)) - vec2(0.5);
		vec2 fp = floor(p);
		vec2 f = p - fp;
		ivec2 i00 = ivec2(int(fp.x), int(fp.y));
		float s00 = texelFetch(reveal_tex, clamp(i00 + ivec2(0, 0), ivec2(0), ts - ivec2(1)), 0).r;
		float s10 = texelFetch(reveal_tex, clamp(i00 + ivec2(1, 0), ivec2(0), ts - ivec2(1)), 0).r;
		float s01 = texelFetch(reveal_tex, clamp(i00 + ivec2(0, 1), ivec2(0), ts - ivec2(1)), 0).r;
		float s11 = texelFetch(reveal_tex, clamp(i00 + ivec2(1, 1), ivec2(0), ts - ivec2(1)), 0).r;
		float rev = mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
		float fog_a = 1.0 - smoothstep(0.5 - edge_soft, 0.5 + edge_soft, rev);
		COLOR = vec4(fog_color.rgb, fog_color.a * fog_a);
	}
}
