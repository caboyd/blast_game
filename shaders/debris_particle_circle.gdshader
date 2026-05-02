shader_type canvas_item;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float mask = 1.0 - smoothstep(0.92, 1.0, r);
	vec4 tex_sample = texture(TEXTURE, UV);
	COLOR = tex_sample * COLOR;
	COLOR.a *= mask;
}
