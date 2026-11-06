// Floor shade ring: a flat multiply-blended annulus that darkens the floor between `inner` and the disc
// edge, so a lit centre (moon pool) falls off into a dim rim. Unshaded, no depth write; lay it a few
// centimetres over the floor (PlaneMesh, UV 0-1 over the disc). Characters stand in front of it.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mul, depth_draw_never, shadows_disabled, fog_disabled;

uniform float inner : hint_range(0.0, 1.0) = 0.6;
uniform float darkness : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float shade = smoothstep(inner, 0.98, d) * (1.0 - smoothstep(0.98, 1.0, d));
	ALBEDO = vec3(1.0 - darkness * shade);
}
