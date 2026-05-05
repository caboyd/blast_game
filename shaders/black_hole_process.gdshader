shader_type particles;
// Black hole debris process shader.
// Particle spawns at rest, gravity pulls inward, conservation-of-angular-momentum
// boosts tangential speed as it falls. Inside horizon: deactivate (recycled).

uniform vec2 hole_center = vec2(0.0);
uniform float event_horizon_radius = 16.0;
uniform float event_horizon_falloff_radius = 16.0;
uniform float gravity_strength : hint_range(0.0, 5000000.0) = 180000.0;
uniform float gravity_softening : hint_range(1.0, 256.0) = 24.0;
uniform float burst_inward_bias: hint_range(0.0, 10) = 0.0;
uniform float swirl_bias : hint_range(-1.0, 1.0) = 1.0;
uniform float tangential_boost : hint_range(0.0, 8.0) = 1.6;
uniform float radial_damping : hint_range(0.0, 16.0) = 0.0;
uniform float max_speed : hint_range(0.0, 20000.0) = 6000.0;
uniform float spawn_jitter : hint_range(0.0, 64.0) = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void start() {
    vec2 pos = TRANSFORM[3].xy;
    vec2 to_hole = hole_center - pos;

    vec2 radial = normalize(to_hole + vec2(0.0001));
    vec2 tangent = vec2(-radial.y, radial.x);

    float r = hash(pos); // optional variation

    float inward = burst_inward_bias;
    float swirl = inward * mix(0.5, 1.5, r);

    VELOCITY.xy =
        radial * inward +
        tangent * swirl;

    VELOCITY.z = 0.0;

    CUSTOM = vec4(0.0);
}
	
void process() {
	if (!ACTIVE) {
		
	} else {

		vec2 pos = TRANSFORM[3].xy;
		vec2 to_hole = hole_center - pos;

		// per-particle variation (stable)
		float r = hash(pos);

		float dist2 = dot(to_hole, to_hole);
		float horizon2 = event_horizon_radius * event_horizon_radius;
		float gravity_well2 = event_horizon_falloff_radius * event_horizon_falloff_radius;

		// vary the zone boundary ± range
		float radius_variation = gravity_well2 * 0.1; // 10–20% works well
		float effective_well2 = gravity_well2 + mix(-radius_variation, radius_variation, r);

		// Core kill (final absorption zone)
		if (dist2 <= horizon2) {
			ACTIVE = false;
		} else {

			float dist = sqrt(dist2);

			vec2 radial_dir = to_hole / max(dist, 0.0001);
			vec2 tangent_dir = vec2(-radial_dir.y, radial_dir.x) * sign(swirl_bias + 0.0001);

			vec2 v = VELOCITY.xy;

			float v_len = length(v);
			vec2 v_dir = v / max(v_len, 0.0001);

			float cos_theta = dot(v_dir, radial_dir);
			cos_theta = clamp(cos_theta, -1.0, 1.0);

			float angle = acos(cos_theta);

			float safe = max(dist, gravity_softening);
			float g = gravity_strength / (safe * safe);

			float t = clamp(dist / event_horizon_radius, 0.0, 1.0);

			// wider acceptance far away, tighter near center
			float max_angle = mix(1.4, 0.3, 1.0 - t);

			if (angle > max_angle) {

				float excess = angle - max_angle;

				// rotate velocity toward radial direction
				float correction_strength = excess * 2.0;

				vec2 corrected_dir = normalize(
					mix(v_dir, radial_dir, correction_strength)
				);

				VELOCITY.xy = corrected_dir * v_len;
			}

			vec2 accel = radial_dir * g;

			// same tangential/orbital term
			accel += tangent_dir * (g * tangential_boost);

			VELOCITY.xy += accel * DELTA;

			// -------------------------
			// HARD TANGENTIAL VELOCITY CAP (gamma curve)
			// -------------------------
			{
				float vt = dot(VELOCITY.xy, tangent_dir);

				// normalize distance (0 = center, 1 = outer range)
				float d = clamp(dist2 / (effective_well2 * 2.0), 0.0, 1.0);

				// gamma curve (higher = stronger suppression near center)
				float gamma = 4.0;

				float t = pow(d, gamma);

				float limit = mix(0.9, 80.0, t);

				vt = clamp(vt, -limit, limit);

				VELOCITY.xy -= tangent_dir * dot(VELOCITY.xy, tangent_dir);
				VELOCITY.xy += tangent_dir * vt;
			}

			// optional mild damping (unchanged)
			if (radial_damping > 0.0) {
				VELOCITY.xy *= exp(-radial_damping * DELTA);
			}
			

			// Speed clamp
			float sp = length(VELOCITY.xy);
			if (sp > max_speed) {
				VELOCITY.xy *= max_speed / sp;
			}



			// Orientation
			float ang = atan(VELOCITY.y, VELOCITY.x) - 1.5707963;
			float c = cos(ang);
			float s = sin(ang);

			mat4 rot = mat4(
				vec4( c,  s, 0.0, 0.0),
				vec4(-s,  c, 0.0, 0.0),
				vec4(0.0, 0.0, 1.0, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);

			vec3 sx_v = vec3(TRANSFORM[0].xyz);
			vec3 sy_v = vec3(TRANSFORM[1].xyz);
			float scx = length(sx_v);
			float scy = length(sy_v);

			mat4 scl = mat4(
				vec4(scx, 0.0, 0.0, 0.0),
				vec4(0.0, scy, 0.0, 0.0),
				vec4(0.0, 0.0, 1.0, 0.0),
				vec4(0.0, 0.0, 0.0, 1.0)
			);

			mat4 trs = rot * scl;
			trs[3] = vec4(pos, 0.0, 1.0);
			TRANSFORM = trs;

			// Debug / external use
			CUSTOM.x = clamp(sp / max(max_speed, 1.0), 0.0, 1.0);
			CUSTOM.y = clamp(1.0 - (dist / (event_horizon_radius * 8.0)), 0.0, 1.0);
		}
	}
}