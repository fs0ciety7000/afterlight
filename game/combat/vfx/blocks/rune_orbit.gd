extends VfxBlock
## Protective runes orbiting the caster (follow-through / afterglow beat).
## Params: position, follow, count, radius (m), height (m), size (m), speed (rad/s), duration.

var _runes: Array[MeshInstance3D] = []


func defaults() -> Dictionary:
	return {"count": 3, "radius": 0.9, "height": 0.9, "size": 0.32, "speed": 2.4, "duration": 1.2}


func _build() -> void:
	life = num("duration")
	for i in int(num("count")):
		var m := material(RUNE_SHADER)
		m.set_shader_parameter("billboard", 1)
		m.set_shader_parameter("detail", 0.0)
		m.set_shader_parameter("glyph_count", 6.0)
		m.set_shader_parameter("seed", 11.0 + i)
		m.set_shader_parameter("line", 0.03)
		_runes.append(mesh_layer(quad_mesh(), m))


func _tick(t: float) -> void:
	global_position = where(p.get("follow"), where(p.get("position")))
	var n := _runes.size()
	var a := ease_out(span(t, 0.0, 0.2)) * (1.0 - span(t, life - 0.3, life)) * (1.0 - stop_t())
	var spin := 0.0 if reduced() else t * num("speed")
	for i in n:
		var ang := spin + TAU * i / n
		var r := num("radius") * size_scale() * (0.6 + 0.4 * ease_out(span(t, 0.0, 0.3)))
		_runes[i].position = Vector3(
			cos(ang) * r, num("height") + 0.08 * sin(ang * 2.0), sin(ang) * r
		)
		_runes[i].scale = Vector3.ONE * num("size") * size_scale()
		var m := _runes[i].material_override as ShaderMaterial
		m.set_shader_parameter("alpha", a)
		m.set_shader_parameter("appear", ease_out(span(t, 0.0, 0.25)))
		m.set_shader_parameter("spin", t * 1.5)
