// Electric arc on an axial quad (Y = from -> to): a jagged line that re-rolls `rate` times per
// second (stepped, not smooth, so it reads as electricity). Used for Choc and lightning hits.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
render_mode fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.988, 0.9, 1.0);
uniform vec4 fringe_color : source_color = vec4(0.95, 0.85, 0.42, 1.0);
uniform float intensity = 1.0;
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float t = 0.0;
uniform float rate = 14.0;
uniform float seed = 0.0;
uniform float jag = 0.32;

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 4.1) * 43758.5453);
}

void vertex() {
	vec3 axis = MODEL_MATRIX[1].xyz;
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - pos);
	vec3 side = normalize(cross(normalize(axis), to_cam) + vec3(1e-6)) * length(MODEL_MATRIX[0].xyz);
	vec3 nrm = normalize(cross(side, axis) + vec3(1e-6));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(axis, 0.0), vec4(nrm, 0.0),
		vec4(pos, 1.0));
}

void fragment() {
	float s = UV.y;
	float frame = floor(t * rate);
	float k = s * 7.0;
	float i = floor(k);
	float f = fract(k);
	float a0 = (hash(i + frame * 13.0) - 0.5);
	float a1 = (hash(i + 1.0 + frame * 13.0) - 0.5);
	float env = sin(s * 3.14159);
	float off = mix(a0, a1, f) * jag * env;
	float d = abs(UV.x - 0.5 - off);
	float hot = smoothstep(0.035, 0.01, d);
	float glow = smoothstep(0.3, 0.0, d) * 0.6;
	float a = alpha;
	ALBEDO = (core_color.rgb * hot + fringe_color.rgb * glow * (1.0 - hot)) * intensity * a;
	ALPHA = clamp(hot + glow * 0.4, 0.0, 1.0) * cover * a;
}
