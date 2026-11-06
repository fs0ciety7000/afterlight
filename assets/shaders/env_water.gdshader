// Stylised stream: flat painted water with drifting light streaks and a pale foam edge where it meets the
// bank (depth-free: the edge comes from UV.x across the ribbon mesh), unshaded to keep it bright and clean.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque, shadows_disabled;

uniform vec4 deep_color : source_color = vec4(0.36, 0.6, 0.78, 0.92);
uniform vec4 shallow_color : source_color = vec4(0.62, 0.82, 0.9, 0.9);
uniform vec4 foam_color : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform float flow_speed = 0.35;
uniform float streak_scale = 1.2;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// UV.x: 0..1 across the stream, UV.y: metres along it
	float across = abs(UV.x - 0.5) * 2.0;
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.2, 0.9, across));
	vec2 q = vec2(UV.x * 6.0, UV.y * 0.6 - TIME * flow_speed) * streak_scale;
	float streak = smoothstep(0.72, 0.8, vnoise(q * vec2(3.0, 0.5)));
	col = mix(col, foam_color.rgb, streak * 0.55);
	float foam = smoothstep(0.8, 0.95, across + (vnoise(vec2(UV.y * 1.5 - TIME * 0.2, UV.x * 4.0)) - 0.5) * 0.15);
	col = mix(col, foam_color.rgb, foam);
	ALBEDO = col;
	ALPHA = mix(deep_color.a, 1.0, foam);
}
