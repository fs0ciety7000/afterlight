// Moonlight pool on the floor: a flat additive disc with a feathered, slowly wavering edge, so the moon
// that falls through a broken roof reads as a soft patch instead of a hard-edged shadow-map rectangle.
// Unshaded, no depth write; lay it a few centimetres over the floor (PlaneMesh, UV 0-1 over the disc).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.74, 0.82, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.16;
// 0 = sharp edge, 1 = light fades from the centre outwards
uniform float feather : hint_range(0.05, 1.0) = 0.55;
// stretch of the pool along its local X (> 1: oval, a shaft seen at an angle)
uniform float aspect = 1.0;

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
	vec2 c = (UV - vec2(0.5)) * 2.0;
	float d = length(c);
	// wavering edge: noise on the direction, drifting slowly (clouds over the moon)
	float a = atan(c.y, c.x);
	float wobble = vnoise(vec2(a * 2.2, TIME * 0.05)) * 0.12 + vnoise(UV * 7.0 + TIME * 0.02) * 0.06;
	float pool = 1.0 - smoothstep(1.0 - feather, 1.0, d + wobble);
	float dapple = 0.82 + 0.18 * vnoise(UV * 11.0 - vec2(TIME * 0.03, 0.0));
	ALBEDO = color.rgb * intensity * pool * pool * dapple;
}
