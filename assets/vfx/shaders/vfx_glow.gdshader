// Generic VFX sprite for the Compatibility renderer (WebGL 2): procedural shapes, no textures.
// Premultiplied blending: alpha 0 = purely additive glow (night), alpha > 0 also covers the
// background a little so bright effects stay readable on a sunny ground (day). See docs/VFX.md.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
render_mode fog_disabled;

// 0 orb (hot core + soft halo), 1 ring, 2 streak (capsule along Y), 3 glint (4 thin rays),
// 4 crescent, 5 scorch (dark burnt mark), 6 mote (small sharp diamond), 7 puff (soft smoke).
uniform int shape = 0;
// 0 flat (mesh orientation), 1 camera-facing, 2 axial (Y kept, faces the camera around it).
uniform int billboard = 1;
uniform vec4 core_color : source_color = vec4(0.945, 0.957, 1.0, 1.0);
uniform vec4 fringe_color : source_color = vec4(0.647, 0.541, 0.839, 1.0);
uniform float intensity = 1.0;
// Share of the background covered by the effect (0 = additive). Raised by day.
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// Shape controls: ring radius / width (UV units, 0..0.5), core size, crescent sweep.
uniform float radius : hint_range(0.0, 0.5) = 0.38;
uniform float width : hint_range(0.0, 0.5) = 0.04;
uniform float core : hint_range(0.0, 1.0) = 0.25;
uniform float sweep : hint_range(0.0, 1.0) = 0.5;
uniform float seed = 0.0;
// Axial mode: length multiplier of the Y axis (velocity-stretched sparks).
uniform float stretch = 1.0;
// In-plane rotation of the shape (radians), e.g. a turning glint on a billboard.
uniform float rot = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	if (billboard == 1) {
		// Camera-facing, keeps the instance scale (works for CPUParticles3D instances too).
		mat4 m = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		m = m * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * m;
	} else if (billboard == 2) {
		// Axial: the Y axis (length included) is kept, X turns to face the camera.
		vec3 axis = MODEL_MATRIX[1].xyz * stretch;
		vec3 pos = MODEL_MATRIX[3].xyz;
		vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - pos);
		vec3 side = cross(normalize(axis + vec3(1e-5)), to_cam);
		side = normalize(side + vec3(1e-6)) * length(MODEL_MATRIX[0].xyz);
		vec3 nrm = normalize(cross(side, axis) + vec3(1e-6));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(axis, 0.0), vec4(nrm, 0.0),
			vec4(pos, 1.0));
	}
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	p = mat2(vec2(cos(rot), sin(rot)), vec2(-sin(rot), cos(rot))) * p;
	float r = length(p) * 2.0;
	float hot = 0.0; // 0..1 white-hot core
	float glow = 0.0; // 0..1 coloured halo
	if (shape == 0) {
		hot = core > 0.0 ? smoothstep(core, core * 0.35, r) : 0.0;
		glow = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	} else if (shape == 1) {
		float d = abs(r * 0.5 - radius);
		hot = smoothstep(width * 0.55, width * 0.15, d);
		glow = smoothstep(width * 3.0, 0.0, d) * 0.6;
	} else if (shape == 2) {
		vec2 q = vec2(abs(p.x) * 2.0, abs(p.y) * 2.0);
		float edge = q.x / max(1.0 - q.y * q.y, 0.001);
		hot = smoothstep(core, core * 0.4, edge) * smoothstep(1.0, 0.6, q.y);
		glow = pow(clamp(1.0 - edge, 0.0, 1.0), 1.6) * smoothstep(1.0, 0.2, q.y);
	} else if (shape == 3) {
		vec2 a = abs(p) * 2.0;
		float rays = max(smoothstep(width, 0.0, a.y) * (1.0 - a.x),
			smoothstep(width, 0.0, a.x) * (1.0 - a.y));
		rays = max(rays, smoothstep(width * 0.7, 0.0, abs(a.x - a.y)) * (1.0 - r) * 0.5);
		hot = max(pow(rays, 3.0), smoothstep(core, 0.0, r));
		glow = max(rays, pow(clamp(1.0 - r, 0.0, 1.0), 3.0) * 0.6);
	} else if (shape == 4) {
		// Crescent: band at `radius`, opened over `sweep` of the circle, thick in the middle.
		float ang = (atan(p.y, p.x) / 6.2831853) + 0.5;
		float along = clamp(ang / max(sweep, 0.001), 0.0, 1.0);
		float in_arc = step(ang, sweep);
		float thick = width * sin(along * 3.14159);
		float d = abs(r * 0.5 - radius);
		hot = in_arc * smoothstep(thick * 0.5, thick * 0.1, d);
		glow = in_arc * smoothstep(thick * 2.0, 0.0, d) * 0.7;
	} else if (shape == 5) {
		float n = vnoise(p * 9.0 + seed) * 0.6 + vnoise(p * 21.0 - seed) * 0.4;
		float mask = smoothstep(0.95, 0.35, r + (n - 0.5) * 0.5);
		ALBEDO = vec3(0.0);
		ALPHA = mask * alpha * 0.55;
		float ember = smoothstep(0.62, 0.8, n) * mask * smoothstep(0.2, 0.7, r);
		ALBEDO = fringe_color.rgb * ember * intensity * alpha;
	} else if (shape == 6) {
		float d = abs(p.x) + abs(p.y);
		hot = smoothstep(0.22, 0.08, d);
		glow = smoothstep(0.5, 0.0, d) * 0.6;
	} else {
		float n = vnoise(p * 5.0 + seed);
		float m = smoothstep(1.0, 0.2, r + (n - 0.5) * 0.45);
		hot = 0.0;
		glow = m * 0.8;
	}
	if (shape != 5) {
		float a = alpha * COLOR.a;
		vec3 tint = COLOR.rgb;
		vec3 rgb = (core_color.rgb * hot + fringe_color.rgb * glow * (1.0 - hot)) * tint;
		rgb *= intensity * a;
		float cov = clamp(max(hot, glow * 0.7), 0.0, 1.0) * cover * a;
		if (shape == 7) {
			// Smoke / mist: plain alpha-blended tint, no glow.
			rgb = fringe_color.rgb * tint * glow * a;
			cov = glow * a * fringe_color.a;
		}
		ALBEDO = rgb;
		ALPHA = cov;
	}
}
