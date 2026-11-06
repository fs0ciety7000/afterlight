extends VfxBlock
## Vertical aura: heal (green), level up (gold), cleanse (pearl). Light column, ground ring,
## rising motes; level up adds a gold rune circle.
## Params: position, follow, kind ("heal" / "level_up" / "cleanse"), height (m), radius (m),
## duration, motes (count).

var _column: MeshInstance3D
var _ring: MeshInstance3D
var _circle: MeshInstance3D


func defaults() -> Dictionary:
	return {"kind": "heal", "height": 2.0, "radius": 0.8, "duration": 1.0, "motes": 18}


func _build() -> void:
	match String(p["kind"]):
		"heal":
			p["element"] = "heal"
		"level_up":
			p["element"] = "gold"
	life = num("duration")
	var r := num("radius") * size_scale()
	_column = sprite(Shape.STREAK, r * 1.4, Face.AXIAL)
	_column.scale = Vector3(r * 1.4, num("height") * size_scale(), 1.0)
	_column.position.y = num("height") * size_scale() * 0.5
	setp(_column, "core", 0.12)
	_ring = sprite(Shape.RING, r * 2.0, Face.FLAT)
	_ring.position.y = 0.04
	setp(_ring, "width", 0.03)
	if String(p["kind"]) == "level_up":
		var m := material(RUNE_SHADER)
		m.set_shader_parameter("glyph_count", 20.0)
		m.set_shader_parameter("line", 0.012)
		_circle = mesh_layer(ground_mesh(), m)
		_circle.scale = Vector3.ONE * r * 3.0
		_circle.position.y = 0.03
	particles(
		{
			"amount": int(num("motes")),
			"lifetime": 0.9,
			"one_shot": false,
			"ring": Vector2(r * 0.2, r),
			"direction": Vector3.UP,
			"spread": 5.0,
			"velocity": Vector2(1.0, 2.4),
			"size": 0.07,
			"local": true,
		}
	)


func _tick(t: float) -> void:
	global_position = where(p.get("follow"), where(p.get("position")))
	var a := ease_out(span(t, 0.0, 0.15)) * (1.0 - span(t, life * 0.55, life))
	a *= 1.0 - stop_t()
	var r := num("radius") * size_scale()
	setp(_column, "alpha", a * 0.7)
	_column.scale.x = r * 1.4 * (1.0 - 0.5 * span(t, life * 0.4, life))
	var k := ease_out(span(t, 0.0, life * 0.7))
	_ring.scale = Vector3.ONE * r * 2.0 * (0.7 + (0.0 if reduced() else 0.6 * k))
	setp(_ring, "alpha", a)
	if _circle:
		var cm := mat_of(_circle)
		cm.set_shader_parameter("appear", ease_out(span(t, 0.0, 0.3)))
		cm.set_shader_parameter("alpha", a)
		cm.set_shader_parameter("spin", 0.0 if reduced() else t * 0.6)
	if t > life * 0.6:
		for c in get_children():
			if c is CPUParticles3D:
				(c as CPUParticles3D).emitting = false
