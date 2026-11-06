// Environment props and vegetation: same two-band cel shading as toon.gdshader (DESIGN.md "Direction 3D"),
// plus what a kit needs: per-instance tint (MultiMesh custom data), wind sway for foliage, a soft contact
// darkening at the foot of each object, optional alpha scissor (grass / flower cards from an atlas).
// MultiMesh custom data (when use_instance_custom): r = tint strength (-1..1, warm/cool), g = brightness,
// b = wind phase, a = atlas cell (cards only).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 shadow_tint : source_color = vec4(0.5, 0.58, 0.72, 1.0);
uniform float band_threshold : hint_range(-1.0, 1.0) = 0.0;
uniform float band_softness : hint_range(0.0, 0.5) = 0.06;
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float rim_width : hint_range(0.0, 1.0) = 0.2;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.25;
uniform bool use_instance_custom = false;
// Warm and cool targets the per-instance tint pulls towards.
uniform vec4 warm_tint : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform vec4 cool_tint : source_color = vec4(0.78, 0.86, 0.72, 1.0);
// Wind: displacement grows with height above the pivot (metres, in mesh space).
uniform float wind_strength : hint_range(0.0, 0.5) = 0.0;
uniform float wind_height = 6.0;
// Darken the first metres above the ground so props sit in the grass instead of floating.
uniform float contact_height = 0.5;
uniform float contact_darkness : hint_range(0.0, 1.0) = 0.25;
// Atlas cards: columns, rows and alpha scissor (0 = opaque mesh).
uniform vec2 atlas_grid = vec2(1.0, 1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;
// Camera cut-out: hides what stands between the camera and the hero, so tree canopies and roofs
// never cover Fern. Only inside a screen circle around the hero, and only for fragments in front
// of her (hero_depth, set every frame by CameraRig). A clean cut with a thin dithered rim, not a
// screen-wide dither. cam_fade_near > 0 enables it (kept for scene compatibility).
global uniform float hero_depth;
uniform float cam_fade_near = 0.0;
uniform float cam_fade_focus = 13.2;
uniform float cam_fade_radius = 0.22;
// Treat the surface as facing up for lighting (cards and foliage read flat and soft, like painted grass).
uniform float normal_up_blend : hint_range(0.0, 1.0) = 0.0;

varying float v_height;
varying vec3 v_tint;

void vertex() {
	v_height = VERTEX.y;
	vec4 custom = use_instance_custom ? INSTANCE_CUSTOM : vec4(0.0, 1.0, 0.0, 0.0);
	float t = custom.r;
	v_tint = mix(vec3(1.0), t > 0.0 ? warm_tint.rgb : cool_tint.rgb, abs(t)) * custom.g;
	if (wind_strength > 0.0) {
		float h = clamp(VERTEX.y / wind_height, 0.0, 1.0);
		vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float ph = custom.b * 6.2831 + wp.x * 0.21 + wp.z * 0.17;
		float sway = sin(TIME * 1.3 + ph) * 0.7 + sin(TIME * 2.9 + ph * 1.7) * 0.3;
		VERTEX.x += sway * wind_strength * h * h;
		VERTEX.z += cos(TIME * 1.1 + ph) * wind_strength * 0.5 * h * h;
	}
	if (atlas_grid.x * atlas_grid.y > 1.0) {
		float cell = custom.a;
		vec2 c = vec2(mod(cell, atlas_grid.x), floor(cell / atlas_grid.x));
		UV = (UV + c) / atlas_grid;
	}
	NORMAL = normalize(mix(NORMAL, (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz, normal_up_blend));
}

float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	// orthographic projection = directional shadow pass: never fade the shadow casters
	if (cam_fade_near > 0.0 && PROJECTION_MATRIX[3][3] < 0.5) {
		float depth = -VERTEX.z;
		vec2 sc = SCREEN_UV - vec2(0.5);
		sc.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		float focus = hero_depth > 0.0 ? hero_depth - 1.2 : cam_fade_focus;
		float inside = 1.0 - smoothstep(cam_fade_radius * 0.9, cam_fade_radius, length(sc));
		float in_front = 1.0 - smoothstep(focus - 1.0, focus, depth);
		float cut = inside * in_front;
		if (cut > 0.999 || cut > 0.02 && cut > dither(FRAGCOORD.xy)) {
			discard;
		}
	}
	vec4 c = texture(albedo_tex, UV) * albedo_tint;
	float contact = 1.0 - contact_darkness * (1.0 - smoothstep(0.0, contact_height, v_height));
	ALBEDO = c.rgb * v_tint * contact;
	if (alpha_scissor > 0.0) {
		// mip levels average thin blades away: boost alpha with the mip level so clumps keep their shape
		vec2 texel = UV * vec2(textureSize(albedo_tex, 0));
		float lod = max(0.0, 0.5 * log2(max(dot(dFdx(texel), dFdx(texel)), dot(dFdy(texel), dFdy(texel)))));
		ALPHA = c.a * (1.0 + lod * 0.45);
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl);
	float shadow = smoothstep(shadow_threshold - 0.05, shadow_threshold + 0.05, ATTENUATION);
	lit *= shadow;
	vec3 light_rgb = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += mix(shadow_tint.rgb, vec3(1.0), lit) * light_rgb;
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.04, fres);
	DIFFUSE_LIGHT += rim * rim_strength * rim_color.rgb * light_rgb * smoothstep(-0.1, 0.3, ndl) * shadow;
}
