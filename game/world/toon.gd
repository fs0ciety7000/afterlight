class_name Toon
extends RefCounted
## Applies the cel-shading look (toon + ink outline, DESIGN.md) to every mesh
## under a node, keeping each surface's albedo texture and color.

const TOON_SHADER: Shader = preload("res://assets/shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/outline.gdshader")
const INK_DAY := Color("#2a2233")
const INK_NIGHT := Color("#0d1220")


static func apply(root: Node, night: bool = false, outline: bool = true) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var toon := ShaderMaterial.new()
			toon.shader = TOON_SHADER
			if src is BaseMaterial3D:
				var base := src as BaseMaterial3D
				toon.set_shader_parameter("albedo_tex", base.albedo_texture)
				toon.set_shader_parameter("albedo_tint", base.albedo_color)
			if outline:
				var ink := ShaderMaterial.new()
				ink.shader = OUTLINE_SHADER
				ink.set_shader_parameter("ink_color", INK_NIGHT if night else INK_DAY)
				toon.next_pass = ink
			mi.set_surface_override_material(s, toon)
