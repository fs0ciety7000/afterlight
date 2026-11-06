shader_type canvas_item;
// Fog of war over the painted region map. Revealed places clear a soft
// circle; everything else is veiled with a parchment mist.

uniform vec4 fog_color : source_color = vec4(0.93, 0.89, 0.80, 0.92);
uniform vec4 fog_shade : source_color = vec4(0.78, 0.72, 0.62, 0.92);
uniform int count = 0;
uniform vec2 points[16];
uniform float radius = 0.16;
uniform float softness = 0.08;
uniform float aspect = 1.7778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float n = noise(uv * 9.0) * 0.6 + noise(uv * 23.0) * 0.4;
	float clear = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= count) {
			break;
		}
		vec2 d = uv - points[i];
		d.x *= aspect;
		float r = radius * (0.85 + 0.3 * n);
		clear = max(clear, 1.0 - smoothstep(r - softness, r, length(d)));
	}
	vec4 mist = mix(fog_color, fog_shade, n);
	COLOR = vec4(mist.rgb, mist.a * (1.0 - clear));
}
