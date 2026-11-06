// Distant painted backdrop card (hills + cloister): unshaded, alpha-blended, tinted toward the sky haze.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 haze : source_color = vec4(0.9, 0.86, 0.95, 1.0);
uniform float haze_amount : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = mix(c.rgb, haze.rgb, haze_amount);
	ALPHA = c.a;
}
