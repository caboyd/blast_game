shader_type canvas_item;

uniform vec2 hole_center = vec2(0.0);
uniform float event_horizon_radius = 16.0;
uniform float event_horizon_falloff_radius = 20.0;
uniform float stretch_intensity : hint_range(0.0, 10.0) = 2.02;

uniform bool render_shadow = false;
uniform vec2 shadow_offset = vec2(1.2, 2.4);
uniform float shadow_squish : hint_range(0.05, 1.0) = 0.45;
uniform float shadow_alpha : hint_range(0.0, 1.0) = 0.35;
uniform vec3 shadow_color : source_color = vec3(0.0, 0.0, 0.0);

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

    // -------------------------------
    // 4. SHADOW PASS: squish vertically + offset, both in screen space.
    // VERTEX is in local model space and the particle's MODEL_MATRIX is
    // rotated/scaled per-instance, so we transform out to world space,
    // do the squish + offset around the particle origin there, then
    // bring it back into local space.
    // -------------------------------
    if (render_shadow) {
        // VERTEX already includes the spaghetti stretch from step 2,
        // so the shadow inherits the exact same stretched silhouette.
        // Transform the stretched vertex out to world space, squish on
        // the screen-Y axis around the particle origin, apply the
        // screen-space offset, then bring it back to local space.
        vec2 origin_world = MODEL_MATRIX[3].xy;
        vec2 vertex_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
        vec2 rel_world = vertex_world - origin_world;
        rel_world.y *= shadow_squish;
        vec2 squished_world = origin_world + rel_world + shadow_offset;
        mat2 m_inv = inverse(mat2(MODEL_MATRIX));
        VERTEX = m_inv * (squished_world - origin_world);
    }
}

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    if (render_shadow) {
        COLOR = vec4(
            shadow_color,
            tex.a * COLOR.a * v_alpha_kill * shadow_alpha
        );
    } else {
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
}

