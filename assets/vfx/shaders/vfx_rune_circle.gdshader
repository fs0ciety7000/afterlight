// Original procedural runic circle (no texture, no pentagram, no symbol from any existing work).
// Layout from outside in: double outer ring with the cast-progress sweep, a band of procedural
// glyphs, a ticked ring, three orbit circles on a ring, a small central eye.
// Drawn on a flat quad (ground or sky); premultiplied blending like vfx_glow.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
render_mode fog_disabled;

uniform vec4 core_color : source_color = vec4(0.945, 0.957, 1.0, 1.0);
uniform vec4 fringe_color : source_color = vec4(0.647, 0.541, 0.839, 1.0);
uniform float intensity = 1.0;
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// 0..1 draw-in of the rings and glyphs (anticipation).
uniform float appear : hint_range(0.0, 1.0) = 1.0;
// 0..1 cast / channel progress shown as a bright sweep on the outer ring (< 0 hides it).
uniform float progress = -1.0;
// Rotation in radians of the glyph band (inner parts turn the other way at half speed).
uniform float spin = 0.0;
uniform float glyph_count = 24.0;
uniform float seed = 3.0;
// Line thickness in UV units of the full circle (scaled by the quad size).
uniform float line = 0.006;
// 1 = full circle, 0 = only the outer ring + glyphs (small halos such as stun).
uniform float detail : hint_range(0.0, 1.0) = 1.0;

// 0 flat (quad orientation), 1 camera-facing (small orbiting runes).
uniform int billboard = 0;


float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distance to one procedural glyph in a unit cell (u across, v radial).
float glyph(vec2 q, float id) {
	float h1 = hash(id);
	float h2 = hash(id + 17.0);
	float h3 = hash(id + 31.0);
	float h4 = hash(id + 53.0);
	float sx = h1 < 0.5 ? 0.35 : 0.65;
	float d = seg(q, vec2(sx, 0.18), vec2(sx, 0.82));
	float y = mix(0.3, 0.7, h2);
	float dir = h3 < 0.5 ? -1.0 : 1.0;
	if (h2 > 0.25) {
		d = min(d, seg(q, vec2(sx, y), vec2(sx + dir * 0.3, y + (h4 - 0.5) * 0.5)));
	}
	if (h3 > 0.55) {
		d = min(d, seg(q, vec2(0.2, 1.0 - y), vec2(0.8, 1.0 - y)));
	}
	if (h4 > 0.6) {
		d = min(d, abs(length(q - vec2(1.0 - sx, 0.3)) - 0.09));
	} else if (h4 < 0.2) {
		d = min(d, length(q - vec2(1.0 - sx, 0.75)) - 0.03);
	}
	return d;
}

void vertex() {
	if (billboard == 1) {
		mat4 m = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		float k = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * m * mat4(vec4(k, 0.0, 0.0, 0.0), vec4(0.0, k, 0.0, 0.0),
			vec4(0.0, 0.0, k, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float aa = max(fwidth(r), 1e-4) * 1.2;
	float ang = atan(p.y, p.x);
	float a_out = fract((ang + spin) / TAU);
	float a_in = fract((ang - spin * 0.5) / TAU);
	float a_raw = fract(ang / TAU + 0.25);
	float lw = line;

	float ln = 0.0;
	// Outer double ring, drawn in by `appear` around the circle.
	float rings = min(abs(r - 0.965), abs(r - 0.915));
	float reveal = step(a_raw, appear);
	ln = max(ln, smoothstep(lw + aa, lw * 0.3, rings) * reveal);
	// Glyph band between 0.73 and 0.89.
	float band_in = 0.735;
	float band_out = 0.885;
	if (r > band_in && r < band_out) {
		float cell = a_out * glyph_count;
		float id = floor(cell);
		vec2 q = vec2(fract(cell), (r - band_in) / (band_out - band_in));
		float cell_w = TAU * r / glyph_count;
		float scale = max(cell_w, band_out - band_in);
		float d;
		if (mod(id, 6.0) == 0.0) {
			// Separator: a small diamond.
			vec2 c = abs(q - vec2(0.5));
			d = abs(c.x + c.y - 0.22);
		} else {
			d = glyph(q, id);
		}
		d *= scale;
		float shown = step(id / glyph_count, appear * 1.05 - 0.05);
		ln = max(ln, smoothstep(lw * 1.1 + aa, lw * 0.3, d) * shown);
	}
	ln = max(ln, smoothstep(lw + aa, lw * 0.3, abs(r - 0.705)) * reveal);
	float inner = smoothstep(0.35, 0.7, appear) * detail;
	if (inner > 0.0) {
		// Ticks on the inner side of the 0.705 ring.
		float tick = abs(fract(a_in * 48.0) - 0.5) * TAU * r / 48.0;
		float tick_len = mod(floor(a_in * 48.0), 4.0) == 0.0 ? 0.06 : 0.03;
		float in_tick = step(0.705 - tick_len, r) * step(r, 0.705);
		ln = max(ln, smoothstep(lw + aa, lw * 0.3, tick) * in_tick * inner);
		// Orbit ring with three small circles (120 degrees apart, turning).
		ln = max(ln, smoothstep(lw * 0.8 + aa, lw * 0.2, abs(r - 0.45)) * inner);
		for (int i = 0; i < 3; i++) {
			float oa = float(i) * TAU / 3.0 - spin * 0.5 + 1.5708;
			vec2 c = vec2(cos(oa), sin(oa)) * 0.45;
			float dc = length(p - c);
			ln = max(ln, smoothstep(lw + aa, lw * 0.3, abs(dc - 0.085)) * inner);
			ln = max(ln, smoothstep(0.03 + aa, 0.02, dc) * inner);
		}
		// Central eye: lens of two arcs plus pupil ring.
		vec2 e = p;
		float lens = max(length(e - vec2(0.0, 0.16)), length(e + vec2(0.0, 0.16))) - 0.26;
		ln = max(ln, smoothstep(lw + aa, lw * 0.3, abs(lens)) * inner);
		ln = max(ln, smoothstep(lw + aa, lw * 0.3, abs(r - 0.06)) * inner);
	}
	// Progress sweep on the outer ring (bright), head with a short comet tail.
	float prog = 0.0;
	if (progress >= 0.0) {
		float band = smoothstep(0.03 + aa, 0.0, abs(r - 0.94));
		float filled = step(a_raw, progress);
		float head = smoothstep(0.08, 0.0, abs(a_raw - progress)) * step(progress, 0.999);
		prog = band * (filled * 0.65 + head) * smoothstep(0.0, 0.3, appear);
	}
	float halo = smoothstep(0.08, 0.0, rings) * 0.35 * reveal + smoothstep(1.0, 0.2, r) * 0.08 * appear;
	float hot = clamp(ln + prog, 0.0, 1.0);
	vec3 rgb = core_color.rgb * hot + fringe_color.rgb * halo * (1.0 - hot) + fringe_color.rgb * prog * 0.4;
	rgb *= intensity * alpha;
	ALBEDO = rgb;
	ALPHA = clamp(hot * 0.9 + halo * 0.3, 0.0, 1.0) * cover * alpha;
}
