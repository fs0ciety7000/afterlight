// Soft light shaft / mist card: additive, unshaded, fades at the edges, the ends and close to the camera so it
// never pops; slow breathing so the forest light feels alive. Use on a QuadMesh (UV.y = 0 at the top).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.88, 0.62, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.22;
uniform float near_fade = 6.0;
uniform float phase = 0.0;

void fragment() {
	float side = smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.65, UV.x);
	float ends = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.45, UV.y);
	float breathe = 0.8 + 0.2 * sin(TIME * 0.6 + phase);
	float cam = smoothstep(0.0, near_fade, -VERTEX.z);
	ALBEDO = color.rgb * intensity * side * ends * breathe * cam;
}
