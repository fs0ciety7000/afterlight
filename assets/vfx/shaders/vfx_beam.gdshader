// Fine, sharp beam on an axial quad: Y = from -> to (length in the Y scale), X faces the camera.
// Thin white-hot core, coloured fringe, scrolling energy streaks, head / tail window.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
render_mode fog_disabled;

uniform vec4 core_color : source_color = vec4(0.945, 0.957, 1.0, 1.0);
uniform vec4 fringe_color : source_color = vec4(0.647, 0.541, 0.839, 1.0);
uniform float intensity = 1.0;
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// Visible window along the beam, 0 = source, 1 = target.
uniform float head : hint_range(0.0, 1.0) = 1.0;
uniform float tail : hint_range(0.0, 1.0) = 0.0;
// Core half-width as a share of the quad width (the quad also holds the halo).
uniform float core_width : hint_range(0.0, 0.5) = 0.08;
// Effect-local time (seconds), fed by the script so recordings with fixed fps stay exact.
uniform float t = 0.0;
uniform float length_m = 10.0;
uniform float streaks = 1.0;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
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
	float s = 1.0 - UV.y;
	float x = abs(UV.x - 0.5) * 2.0;
	float win = smoothstep(tail, tail + 0.02, s) * smoothstep(head, head - 0.02, s);
	// Taper near the source and a slight swell at the head.
	float taper = smoothstep(0.0, 0.04, s) * (0.7 + 0.3 * smoothstep(head - 0.3, head, s));
	float cw = core_width * taper;
	float hot = smoothstep(cw, cw * 0.35, x);
	float glow = pow(clamp(1.0 - x, 0.0, 1.0), 3.0) * (0.55 + 0.45 * taper);
	// Energy streaks running toward the target (world-length based so they do not stretch).
	float lane = floor(UV.x * 7.0);
	float ph = s * length_m * 0.6 - t * 9.0 + hash(lane) * 10.0;
	float streak = smoothstep(0.75, 1.0, fract(ph)) * step(0.35, hash(lane + 3.0));
	streak *= smoothstep(0.85, 0.2, x) * streaks;
	glow = max(glow, streak * 0.45);
	float a = alpha * win;
	vec3 rgb = (core_color.rgb * hot + fringe_color.rgb * glow * (1.0 - hot)) * intensity * a;
	ALBEDO = rgb;
	ALPHA = clamp(hot + glow * 0.5, 0.0, 1.0) * cover * a;
}
