// Ember thread (GDD 9.3): Morvaine's link to her lanterns read as a faint warm path with a few
// flickering embers drifting along it, outwards, rather than a solid line. Additive, unshaded.
// Ribbon mesh (cloister_pieces.gd): UV.x runs along the thread (0 at Morvaine), UV.y across,
// UV2.x is a per-thread phase. `thread_length` / `ribbon_width` turn the UVs into metres so the
// embers stay round whatever the ribbon size. `strength` fades the whole thread (0 when the boss
// falls: the link is cut).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.95, 0.42, 0.16, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.66, 0.34, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.6;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// faint path under the embers
uniform float path : hint_range(0.0, 1.0) = 0.2;
uniform float thread_length = 21.6;
uniform float ribbon_width = 0.44;
// embers: drift speed (m/s), mean spacing (m), radius (m)
uniform float drift = 0.55;
uniform float spacing = 1.1;
uniform float ember_radius = 0.11;
uniform float ember_gain = 1.7;
uniform float near_fade = 3.0;

// sin-free hash (stays stable at mediump precision on the web)
float hash(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	float phase = UV2.x;
	float along = UV.x * thread_length;  // metres from Morvaine
	float across = (UV.y - 0.5) * ribbon_width;  // metres from the centre line
	// the faint path: a hair-thin core that breathes in slow waves travelling outwards
	float core = exp(-across * across / (0.04 * 0.04));
	float wave = 0.55 + 0.45 * sin(along * 0.9 - TIME * 1.4 + phase * 3.0);
	float glow = path * core * wave;
	// embers: one candidate per cell, about half of them lit, each with its own flicker and life
	float u = along / spacing - TIME * drift / spacing + phase * 5.0;
	float cell = floor(u);
	float h1 = hash(cell + phase * 31.0);
	float h2 = hash(cell * 1.7 + 4.1 + phase * 11.0);
	float h3 = hash(cell * 2.3 + 9.7 + phase * 7.0);
	float d = (fract(u) - (0.3 + 0.4 * h2)) * spacing;
	d = d < 0.0 ? d * 0.45 : d;  // a short tail behind (towards Morvaine)
	float r = ember_radius * (0.7 + 0.6 * h3);
	float ember = exp(-(d * d + across * across) / (r * r));
	float lit = step(0.45, h1);
	float life = pow(sin(3.14159 * fract(TIME * (0.18 + 0.12 * h2) + h3)), 2.0);
	float flicker = 0.6 + 0.4 * sin(TIME * (9.0 + 7.0 * h1) + h2 * 40.0);
	float sparks = ember_gain * ember * lit * life * flicker;
	vec3 c = color.rgb * glow + mix(color.rgb, hot.rgb, h3 * flicker) * sparks;
	// fade in out of Morvaine, fade into the lantern, and near the camera
	float ends = smoothstep(0.0, 0.1, UV.x) * smoothstep(1.0, 0.9, UV.x);
	float cam = smoothstep(0.0, near_fade, -VERTEX.z);
	ALBEDO = c * intensity * strength * ends * cam;
}
