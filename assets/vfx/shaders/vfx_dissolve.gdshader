// Death dissolve: replaces a mesh surface material for the last second of an enemy.
// Keeps the albedo with a simple two-band light, eats the mesh from the bottom up with noise,
// and lights the eaten edge (ember for ash, pale for mist).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width = 0.08;
// Object-space height range of the mesh, so the burn runs from the feet up.
uniform float y_min = 0.0;
uniform float y_max = 1.6;

varying float h01;
varying vec3 opos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i);
	float n100 = hash(i + vec3(1, 0, 0));
	float n010 = hash(i + vec3(0, 1, 0));
	float n110 = hash(i + vec3(1, 1, 0));
	float n001 = hash(i + vec3(0, 0, 1));
	float n101 = hash(i + vec3(1, 0, 1));
	float n011 = hash(i + vec3(0, 1, 1));
	float n111 = hash(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	opos = VERTEX;
	h01 = clamp((VERTEX.y - y_min) / max(y_max - y_min, 0.001), 0.0, 1.0);
}

void fragment() {
	float n = vnoise(opos * 9.0) * 0.6 + vnoise(opos * 23.0) * 0.4;
	float v = h01 * 0.6 + n * 0.4;
	float cut = amount * 1.15 - 0.05;
	if (v < cut) {
		discard;
	}
	float e = smoothstep(edge_width, 0.0, v - cut) * step(0.001, amount);
	vec4 c = texture(albedo_tex, UV) * albedo_tint;
	ALBEDO = c.rgb * (1.0 - e);
	EMISSION = edge_color.rgb * e * 2.0;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = smoothstep(0.0, 0.05, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += mix(vec3(0.45, 0.5, 0.65), vec3(1.0), ndl * ATTENUATION) * LIGHT_COLOR / PI;
}
