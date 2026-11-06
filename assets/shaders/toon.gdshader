// Two-band cel shading with tinted shadow and a thin rim (DESIGN.md "Direction 3D").
// Works in the Compatibility renderer (web build). Shadow side = ambient + shadow_tint, never grey.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
// Colour the unlit band takes from each light (multiplied by the light colour), on top of ambient.
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.47, 0.62, 1.0);
// N.L where the band flips, and how soft the edge is (keep small for a crisp anime break).
uniform float band_threshold : hint_range(-1.0, 1.0) = 0.05;
uniform float band_softness : hint_range(0.0, 0.3) = 0.02;
// Shadow-map attenuation is also banded so cast shadows get the same crisp edge.
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.88, 1.0);
uniform float rim_width : hint_range(0.0, 1.0) = 0.22;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_tint;
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl);
	float shadow = smoothstep(shadow_threshold - 0.05, shadow_threshold + 0.05, ATTENUATION);
	lit *= shadow;
	vec3 light_rgb = LIGHT_COLOR / PI;
	if (!LIGHT_IS_DIRECTIONAL) {
		// point lights (dungeon fires, lanterns): ATTENUATION carries the distance falloff, so it
		// scales the light in two cel bands instead of acting as a shadow mask
		lit = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl);
		light_rgb *= smoothstep(0.02, 0.1, ATTENUATION) * 0.45 + smoothstep(0.3, 0.38, ATTENUATION) * 0.55;
		shadow = 1.0;
	}
	DIFFUSE_LIGHT += mix(shadow_tint.rgb, vec3(1.0), lit) * light_rgb;
	// Thin rim on the lit side only (reads as a light edge from the 3/4 top-down camera).
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.04, fres);
	DIFFUSE_LIGHT += rim * rim_strength * rim_color.rgb * light_rgb * smoothstep(-0.1, 0.3, ndl) * shadow;
}
