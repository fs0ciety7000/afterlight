extends VfxBlock
## Death: dissolves the target meshes from the feet up and releases ash (demons, Morvaine,
## constructs) or mist (wolves, spirits). Works on a bare position too (particles only).
## The target is hidden at the end; the combat scene frees it.
## Params: target (Node3D), position, style ("ash" / "mist"), height (m), duration.

const DISSOLVE_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_dissolve.gdshader")

var _mats: Array[ShaderMaterial] = []
var _target: Node3D


func defaults() -> Dictionary:
	return {"style": "ash", "height": 1.4, "duration": 1.3}


func _build() -> void:
	life = num("duration")
	p["element"] = String(p["style"])
	_target = p.get("target") as Node3D
	global_position = where(_target, where(p.get("position")))
	if is_instance_valid(_target):
		_swap_materials(_target)
	var h := num("height") * size_scale()
	if String(p["style"]) == "ash":
		var flakes := particles(
			{
				"amount": 26,
				"lifetime": 1.1,
				"one_shot": false,
				"radius": 0.45 * size_scale(),
				"velocity": Vector2(0.3, 0.9),
				"gravity": Vector3(0.3, 1.2, 0),
				"size": 0.08,
				"shape": Shape.PUFF,
				"roles": ["dark", "dark"],
				"scale_curve": "flat",
			}
		)
		flakes.position.y = h * 0.3
		var embers := particles(
			{
				"amount": 14,
				"lifetime": 0.9,
				"one_shot": false,
				"radius": 0.4 * size_scale(),
				"velocity": Vector2(0.4, 1.0),
				"gravity": Vector3(0, 1.5, 0),
				"size": 0.06,
				"scale_curve": "pop",
			}
		)
		embers.position.y = h * 0.2
	else:
		var mist := particles(
			{
				"amount": 12,
				"lifetime": 1.2,
				"one_shot": false,
				"radius": 0.5 * size_scale(),
				"velocity": Vector2(0.2, 0.6),
				"gravity": Vector3(0.6, 0.3, 0),
				"size": 0.7,
				"shape": Shape.PUFF,
				"roles": ["fringe", "fringe"],
				"scale_curve": "grow",
			}
		)
		mist.position.y = h * 0.35


func _swap_materials(root: Node3D) -> void:
	var edge := col("fringe")
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var aabb := mi.mesh.get_aabb()
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var m := ShaderMaterial.new()
			m.shader = DISSOLVE_SHADER
			if src is ShaderMaterial:
				var sm := src as ShaderMaterial
				m.set_shader_parameter("albedo_tex", sm.get_shader_parameter("albedo_tex"))
				var tint: Variant = sm.get_shader_parameter("albedo_tint")
				if tint is Color:
					m.set_shader_parameter("albedo_tint", tint)
			elif src is BaseMaterial3D:
				m.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
				m.set_shader_parameter("albedo_tint", (src as BaseMaterial3D).albedo_color)
			m.set_shader_parameter("edge_color", edge)
			m.set_shader_parameter("y_min", aabb.position.y)
			m.set_shader_parameter("y_max", aabb.end.y)
			mi.set_surface_override_material(s, m)
			_mats.append(m)


func _tick(t: float) -> void:
	var k := span(t, 0.1, life * 0.85)
	for m in _mats:
		m.set_shader_parameter("amount", k)
	if t > life * 0.7:
		for c in get_children():
			if c is CPUParticles3D:
				(c as CPUParticles3D).emitting = false
	if k >= 1.0 and is_instance_valid(_target):
		_target.visible = false
