// Hit flash overlay (GeometryInstance3D.material_overlay): adds white over the mesh for ~60 ms.
// Skinned meshes are supported (the overlay pass shares the skinning of the surface).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, depth_test_disabled, cull_back;
render_mode shadows_disabled, fog_disabled;

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = flash_color.rgb * amount * (0.65 + 0.35 * fres);
}
