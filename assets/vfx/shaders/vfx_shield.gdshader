// Runic dome (Barrière défensive): fresnel rim, a light lattice (meridians + latitudes),
// a glyph-like dashed band, on-hit ripple and a break (shatter) dissolve. On a SphereMesh.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
render_mode fog_disabled;

uniform vec4 core_color : source_color = vec4(0.945, 0.957, 1.0, 1.0);
uniform vec4 fringe_color : source_color = vec4(0.663, 0.769, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float appear : hint_range(0.0, 1.0) = 1.0;
uniform float shatter : hint_range(0.0, 1.0) = 0.0;
// Hit ripple: direction in object space and progress 0..1 (< 0 = none).
uniform vec3 hit_dir = vec3(0.0, 0.0, -1.0);
uniform float hit_t = -1.0;
uniform float t = 0.0;

varying vec3 lpos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 n = normalize(lpos);
	float y01 = n.y * 0.5 + 0.5;
	if (y01 > appear * 1.02 || n.y < -0.05) {
		discard;
	}
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float lon = atan(n.z, n.x) / 6.2831853 + 0.5;
	float lat = asin(clamp(n.y, -1.0, 1.0)) / 1.5708;
	float aa = 0.004;
	float mer = abs(fract(lon * 8.0 + t * 0.03) - 0.5) / 8.0 * 6.28 * sqrt(max(1.0 - n.y * n.y, 0.0));
	float par = min(abs(lat - 0.35), abs(lat - 0.7));
	float lattice = max(smoothstep(0.012 + aa, 0.004, mer) * step(lat, 0.86),
		smoothstep(0.012 + aa, 0.004, par * 1.57));
	// Dashed "glyph" band near the base.
	float band = smoothstep(0.03, 0.0, abs(lat - 0.12)) * step(0.45, fract(lon * 40.0 - t * 0.1));
	float edge = smoothstep(0.04, 0.0, abs(y01 - appear)) * step(appear, 0.99);
	float ripple = 0.0;
	if (hit_t >= 0.0) {
		float ang = acos(clamp(dot(n, normalize(hit_dir)), -1.0, 1.0));
		ripple = smoothstep(0.18, 0.0, abs(ang - hit_t * 1.8)) * (1.0 - hit_t);
		ripple += smoothstep(0.5, 0.0, ang) * (1.0 - hit_t) * 0.6;
	}
	// Shatter: cells vanish by noise, their edges flare.
	float cell = hash(floor(n * 7.0));
	float gone = step(cell, shatter * 1.1 - 0.05);
	if (gone > 0.5) {
		discard;
	}
	float crack = smoothstep(0.15, 0.0, abs(cell - shatter)) * step(0.01, shatter);
	float hot = clamp(lattice * 0.8 + band * 0.7 + edge + ripple * 0.8 + crack, 0.0, 1.0);
	float glow = fres * 0.9 + 0.06;
	float a = alpha;
	vec3 rgb = (core_color.rgb * hot + fringe_color.rgb * glow * (1.0 - hot * 0.5)) * intensity * a;
	ALBEDO = rgb;
	ALPHA = clamp(hot * 0.6 + glow * 0.4, 0.0, 1.0) * cover * a;
}
