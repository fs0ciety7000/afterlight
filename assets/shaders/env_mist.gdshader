// Ground mist bank: a soft alpha-blended card (not additive, so it veils bright grass instead of
// burning it white), unshaded, slowly drifting, faded at the edges and close to the camera.
// Use on a QuadMesh lying over water; one MultiMesh per place. Fades near and far from the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.86, 0.87, 0.94, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.35;
uniform float near_fade = 8.0;
// Banks beyond this range fade out: seen edge-on from a wide, low view they stack into a veil
// that washes out the far trees (shot_mire_vista.jpg); the gameplay camera only sees near banks.
uniform float far_fade_start = 20.0;
uniform float far_fade_end = 42.0;

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
	float shape = clamp(1.0 - dot(c, c), 0.0, 1.0);
	float wisps = vnoise(UV * vec2(5.0, 2.5) + vec2(TIME * 0.04, 0.0));
	float cam = smoothstep(0.0, near_fade, -VERTEX.z);
	cam *= 1.0 - smoothstep(far_fade_start, far_fade_end, -VERTEX.z);
	ALBEDO = color.rgb;
	ALPHA = opacity * shape * shape * (0.55 + 0.45 * wisps) * cam;
}
