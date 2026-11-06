// Lantern halo: a camera-facing soft disc, additive and unshaded, with a slow per-instance flicker.
// Drawn through a MultiMesh (one draw call for every lantern of a place); fades close to the camera
// and ignores fog so the warm lights carry through the mist (DESIGN.md: warm point sources).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.74, 0.4, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.5;
uniform float near_fade = 2.5;

varying float v_phase;

void vertex() {
	// billboard that keeps the instance scale
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0), vec4(0.0, 0.0, s.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 0.9;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	float core = smoothstep(0.32, 0.0, d) * 0.6;
	float flicker = 0.88 + 0.08 * sin(TIME * 2.3 + v_phase) + 0.04 * sin(TIME * 7.1 + v_phase * 2.0);
	float cam = smoothstep(0.0, near_fade, -VERTEX.z);
	ALBEDO = color.rgb * intensity * (halo + core) * flicker * cam;
}
