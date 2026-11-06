// Enemy ground telegraph (GDD §9.1): danger red-ember, solid outline, diagonal hatching, and a
// fill that grows over the telegraph duration. Flat quad lying on the ground (XZ).
// shape 0 circle (quad = diameter), 1 line (quad = width x length, fills from the caster end),
// 2 cone (quad = 2R x 2R centred on the apex, half-angle `cone_half_deg`, opens toward -Z).
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int shape = 0;
uniform vec4 edge_color : source_color = vec4(0.769, 0.333, 0.247, 1.0);
uniform vec4 fill_color : source_color = vec4(1.0, 0.55, 0.32, 1.0);
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float cone_half_deg = 30.0;
// Quad size in metres, used to keep the outline and hatch width constant in metres.
uniform vec2 size_m = vec2(6.0, 6.0);
uniform float edge_m = 0.07;
// Interruptible casts get the pearl ring (GDD §9.1), others a dark solid ring.
uniform float flash = 0.0;

void fragment() {
	vec2 m = (UV - vec2(0.5)) * size_m; // metres from the quad centre
	float inside;
	float edge;
	float prog;
	if (shape == 0) {
		float R = size_m.x * 0.5;
		float r = length(m);
		inside = step(r, R);
		edge = smoothstep(edge_m, edge_m * 0.4, R - r) * inside;
		prog = r / R; // fill grows from the centre
	} else if (shape == 1) {
		vec2 hs = size_m * 0.5;
		vec2 d = hs - abs(m);
		inside = step(0.0, min(d.x, d.y));
		edge = smoothstep(edge_m, edge_m * 0.4, min(d.x, d.y)) * inside;
		prog = UV.y; // caster at UV.y = 0
	} else {
		float R = size_m.x * 0.5;
		float r = length(m);
		float ang = abs(atan(m.x, -m.y));
		float half_a = radians(cone_half_deg);
		inside = step(r, R) * step(ang, half_a);
		float side_d = r * sin(half_a - ang);
		edge = smoothstep(edge_m, edge_m * 0.4, min(R - r, side_d)) * inside;
		prog = r / R;
	}
	if (inside < 0.5) {
		discard;
	}
	float hatch = step(0.5, fract((m.x + m.y) * 1.6)) * 0.12;
	float filled = step(prog, fill);
	float front = smoothstep(0.06, 0.0, abs(prog - fill)) * step(fill, 0.999);
	vec3 rgb = mix(edge_color.rgb * 0.6, fill_color.rgb, filled * 0.7 + front);
	rgb = mix(rgb, edge_color.rgb, edge);
	rgb += vec3(flash) * 0.6;
	float a = 0.14 + hatch + filled * 0.22 + front * 0.5 + edge * 0.75;
	ALBEDO = rgb;
	ALPHA = clamp(a, 0.0, 1.0) * alpha;
}
