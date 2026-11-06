extends VfxBlock
## Enemy ground telegraph (GDD §9.1): circle, line or cone in danger red-ember with outline and
## hatching, filled over its duration, a short flash when it resolves. Always the danger palette
## (an element tint would hide the threat).
## Params: position, shape ("circle" / "line" / "cone"), radius (m, circle and cone), length,
## width (m, line), angle (cone half angle, deg), toward (Vector3 or Node3D: aim point),
## duration (s, >= 0.6 per GDD).

const SHAPES := {"circle": 0, "line": 1, "cone": 2}

var _decal: MeshInstance3D


func defaults() -> Dictionary:
	return {
		"shape": "circle",
		"radius": 3.0,
		"length": 6.0,
		"width": 1.2,
		"angle": 30.0,
		"duration": 1.2,
		"height": 0.035,
	}


func _build() -> void:
	life = num("duration") + 0.28
	var origin := where(p.get("position"))
	global_position = origin + Vector3.UP * num("height")
	var shape := int(SHAPES.get(String(p["shape"]), 0))
	var dir := where(p.get("toward"), origin + Vector3.FORWARD) - origin
	dir.y = 0.0
	dir = Vector3.FORWARD if dir.length() < 0.01 else dir.normalized()
	var m := ShaderMaterial.new()
	m.shader = TELEGRAPH_SHADER
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("cone_half_deg", num("angle"))
	m.set_shader_parameter("edge_color", VfxPalette.color("danger", "fringe"))
	m.set_shader_parameter("fill_color", VfxPalette.color("danger", "spark"))
	_decal = mesh_layer(ground_mesh(), m)
	var size := Vector2.ONE * num("radius") * 2.0
	match shape:
		1:
			size = Vector2(num("width"), num("length"))
			_decal.basis = Basis.looking_at(-dir, Vector3.UP)
			_decal.position = dir * num("length") * 0.5
		2:
			_decal.basis = Basis.looking_at(dir, Vector3.UP)
	m.set_shader_parameter("size_m", size)
	_decal.scale = Vector3(size.x, 1.0, size.y)


func _tick(t: float) -> void:
	var dur := num("duration")
	var m := mat_of(_decal)
	m.set_shader_parameter("fill", span(t, 0.0, dur))
	var resolve := span(t, dur, life)
	m.set_shader_parameter("flash", (1.0 - resolve) * step_f(t, dur))
	var appear := 1.0 if reduced() else ease_out(span(t, 0.0, 0.1))
	m.set_shader_parameter("alpha", appear * (1.0 - resolve) * (1.0 - stop_t()))


static func step_f(t: float, edge: float) -> float:
	return 1.0 if t >= edge else 0.0
