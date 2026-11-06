// Ember thread: a soft red-ember line (additive, unshaded) with sparks pulsing along it, from Morvaine
// towards her lanterns (GDD 9.3). Ribbon mesh: UV.x runs along the thread (0 at Morvaine), UV.y across.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.95, 0.24, 0.12, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.75, 0.45, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.42;
uniform float speed = 0.18;
uniform float near_fade = 3.0;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float core = exp(-across * across * 9.0);
	float halo = (1.0 - across) * 0.25;
	// pulses travelling outwards, broken up so the threads do not beat in sync
	float t = UV.x * 5.0 - TIME * speed * 5.0 + UV2.x;
	float pulse = pow(0.5 + 0.5 * sin(t * 6.2831), 6.0);
	float ends = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.94, UV.x);
	float flicker = 0.85 + 0.15 * sin(TIME * 3.1 + UV2.x * 7.0);
	vec3 c = mix(color.rgb, hot.rgb, pulse * core);
	float cam = smoothstep(0.0, near_fade, -VERTEX.z);
	ALBEDO = c * intensity * (core * (0.55 + 0.9 * pulse) + halo) * ends * flicker * cam;
}
