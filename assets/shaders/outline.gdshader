// Inverted-hull outline. Use as next_pass of the toon material.
// Pushes the back faces out along the view-space normal by a constant number of pixels
// (DESIGN.md: ~1.5 px at 1080p), so the ink line stays thin at every zoom level.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform vec4 ink_color : source_color = vec4(0.165, 0.133, 0.2, 1.0); // #2a2233 day, #0d1220 night
uniform float thickness_px : hint_range(0.0, 8.0) = 1.5;
// Viewport height the pixel width is defined for; the line scales with the viewport.
uniform float reference_height = 1080.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 n_view = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(n_view, 0.0)).xy;
	float len_dir = length(dir);
	dir = len_dir > 1e-5 ? dir / len_dir : vec2(0.0);
	float px = thickness_px * VIEWPORT_SIZE.y / reference_height;
	clip.xy += dir * px * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
