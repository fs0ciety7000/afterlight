// Frozen crystal shards (Gelé): pale translucent ice with a bright fresnel edge.
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_opaque, cull_back, shadows_disabled, fog_disabled;

uniform vec4 body_color : source_color = vec4(0.62, 0.84, 0.95, 1.0);
uniform vec4 edge_color : source_color = vec4(0.95, 0.99, 1.0, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float facet = 0.75 + 0.25 * NORMAL.y;
	ALBEDO = mix(body_color.rgb * facet, edge_color.rgb, fres);
	ALPHA = (0.55 + 0.4 * fres) * alpha;
}
