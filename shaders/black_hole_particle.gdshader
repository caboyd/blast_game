shader_type canvas_item;

uniform vec2 hole_center = vec2(0.0);
uniform float event_horizon_radius = 16.0;
uniform float event_horizon_falloff_radius = 20.0;
uniform float stretch_intensity : hint_range(0.0, 10.0) = 2.02;

varying float v_alpha_kill;
varying float v_spectral_shift;
varying float v_stretch_mask;

void vertex() {
    vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
    float dist = distance(world_pos, hole_center);

    // -------------------------------
    // 1. OUTER LIMIT (no spaghetti beyond this)
    // -------------------------------

    // 0 outside outer_radius, 1 near horizon
    float mask = 1.0 - smoothstep(event_horizon_radius, event_horizon_falloff_radius * 4.0, dist);

    v_stretch_mask = mask;

    // -------------------------------
    // 2. STRETCH ONLY INSIDE ZONE
    // -------------------------------
    float tight_dist = clamp(dist / 500.0, 0.0, 1.0);
    float stretch = (1.0 / (tight_dist + 0.1)) * stretch_intensity * 0.1;

    stretch *= mask; // <-- KEY FIX

    VERTEX.y *= (1.0 + stretch);
    VERTEX.x *= (1.0 / (1.0 + stretch * 0.5));

    // -------------------------------
    // 3. KILL SWITCH (unchanged)
    // -------------------------------
    v_alpha_kill = smoothstep(event_horizon_radius, event_horizon_falloff_radius, dist);
    v_spectral_shift = smoothstep(event_horizon_radius, event_horizon_falloff_radius * 1.5, dist);
}

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    float t = 0.5 + 0.5 * sin(TIME * 4.0); // oscillates 0 → 1 → 0

    vec3 spectral_shift_color = mix(
        vec3(1.1, 0.9, 1.3), // red shift
        vec3(0.8, 0.9, 1.5), // blue shift
        t
    );

    vec3 spectral_shift = mix(spectral_shift_color, vec3(1.0), v_spectral_shift);

    COLOR = vec4(
        tex.rgb * COLOR.rgb * spectral_shift,
        tex.a * COLOR.a * v_alpha_kill
    );
}