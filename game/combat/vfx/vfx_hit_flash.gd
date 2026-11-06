class_name VfxHitFlash
extends RefCounted
## White hit flash (GDD §14, 60 ms) through GeometryInstance3D.material_overlay, so it works on
## skinned toon meshes without touching their materials. One overlay material per flash.

const FLASH_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_flash.gdshader")


static func flash(target: Node, color: Color = Color.WHITE, duration_s: float = 0.06) -> void:
	if target == null or not is_instance_valid(target):
		return
	var meshes: Array[GeometryInstance3D] = []
	for n in target.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n as GeometryInstance3D)
	if target is MeshInstance3D:
		meshes.append(target as GeometryInstance3D)
	if meshes.is_empty():
		return
	var m := ShaderMaterial.new()
	m.shader = FLASH_SHADER
	m.set_shader_parameter("flash_color", color)
	m.set_shader_parameter("amount", 1.0)
	for mi in meshes:
		var current := mi.material_overlay as ShaderMaterial
		if mi.material_overlay == null or (current and current.shader == FLASH_SHADER):
			mi.material_overlay = m
	var tw := target.create_tween()
	tw.tween_method(
		func(v: float) -> void: m.set_shader_parameter("amount", v), 1.0, 0.0, duration_s
	)
	tw.tween_callback(_clear.bind(meshes, m))


static func _clear(meshes: Array[GeometryInstance3D], m: ShaderMaterial) -> void:
	for mi in meshes:
		if is_instance_valid(mi) and mi.material_overlay == m:
			mi.material_overlay = null
