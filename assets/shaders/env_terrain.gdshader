// Painted ground: grass base + dirt / cobble / forest-floor layers from a splat map (R, G, B), world-space
// tiling with a second rotated sample and macro noise to hide repetition, noisy splat edges for a hand-painted
// border, then the same banded light as toon.gdshader (shadows banded and tinted, never grey).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

uniform sampler2D splat_tex : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cobble_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_tex : source_color, filter_linear_mipmap, repeat_enable;
// World rectangle the splat map covers: xy = min corner (x, z), zw = size.
uniform vec4 splat_rect = vec4(-70.0, -70.0, 140.0, 140.0);
uniform float grass_tile = 5.0;
uniform float dirt_tile = 5.0;
uniform float cobble_tile = 3.2;
uniform float forest_tile = 5.0;
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 macro_dark : source_color = vec4(0.84, 0.88, 0.8, 1.0);
uniform vec4 macro_light : source_color = vec4(1.08, 1.04, 0.92, 1.0);
uniform float edge_noise : hint_range(0.0, 1.0) = 0.35;
uniform vec4 shadow_tint : source_color = vec4(0.5, 0.58, 0.72, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5;

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 tiled(sampler2D tex, vec2 p, float tile) {
	// two samples, the second rotated and scaled, blended by noise: breaks the grid of the repeat
	vec2 uv1 = p / tile;
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (tile * 1.37) + vec2(0.31, 0.17);
	float n = smoothstep(0.3, 0.7, vnoise(p * 0.09));
	return mix(texture(tex, uv1).rgb, texture(tex, uv2).rgb, n);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	vec4 s = texture(splat_tex, (p - splat_rect.xy) / splat_rect.zw);
	float n = vnoise(p * 0.55) * 0.6 + vnoise(p * 1.9) * 0.4 - 0.5;
	vec3 col = tiled(grass_tex, p, grass_tile) * grass_tint.rgb;
	float wf = smoothstep(0.35, 0.65, s.b + n * edge_noise);
	col = mix(col, tiled(forest_tex, p, forest_tile), wf);
	float wd = smoothstep(0.35, 0.65, s.r + n * edge_noise);
	col = mix(col, tiled(dirt_tex, p, dirt_tile), wd);
	float wc = smoothstep(0.4, 0.6, s.g + n * edge_noise * 0.6);
	col = mix(col, tiled(cobble_tex, p, cobble_tile), wc);
	float m = vnoise(p * 0.035) * 0.65 + vnoise(p * 0.11) * 0.35;
	col *= mix(macro_dark.rgb, macro_light.rgb, smoothstep(0.25, 0.75, m));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.05, 0.05, ndl);
	if (LIGHT_IS_DIRECTIONAL) {
		lit *= smoothstep(shadow_threshold - 0.05, shadow_threshold + 0.05, ATTENUATION);
		DIFFUSE_LIGHT += mix(shadow_tint.rgb, vec3(1.0), lit) * LIGHT_COLOR / PI;
	} else {
		// point lights: distance falloff in two cel bands (ATTENUATION is not a shadow mask here)
		float a = smoothstep(0.02, 0.1, ATTENUATION) * 0.45 + smoothstep(0.3, 0.38, ATTENUATION) * 0.55;
		DIFFUSE_LIGHT += lit * a * LIGHT_COLOR / PI;
	}
}
