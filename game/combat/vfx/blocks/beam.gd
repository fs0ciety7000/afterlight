extends VfxBlock
## Fine, sharp beam (Zoltraak, sky rain): grows from the source in `grow_s`, holds, then thins
## and fades from the source end. Source flare and a head glint. Emits `arrived` when it hits.
## Params: from, to, to_offset, width (m, quad incl. halo), core_width (share of the quad),
## grow_s, hold_s, fade_s, flare (m), streaks (0..1).

var _beam: MeshInstance3D
var _flare: MeshInstance3D
var _glint: MeshInstance3D
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _hit := false


func defaults() -> Dictionary:
	return {
		"width": 0.42,
		"core_width": 0.1,
		"grow_s": 0.06,
		"hold_s": 0.16,
		"fade_s": 0.22,
		"flare": 0.6,
		"streaks": 1.0,
		"to_offset": Vector3.ZERO,
	}


func travel_time() -> float:
	return num("grow_s")


func _build() -> void:
	life = num("grow_s") + num("hold_s") + num("fade_s")
	_a = where(p.get("from"))
	_b = where(p.get("to"), _a) + (p["to_offset"] as Vector3)
	var m := material(BEAM_SHADER)
	m.set_shader_parameter("core_width", num("core_width"))
	m.set_shader_parameter("length_m", _a.distance_to(_b))
	m.set_shader_parameter("streaks", num("streaks"))
	_beam = mesh_layer(quad_mesh(), m)
	_beam.top_level = true
	orient_between(_beam, _a, _b, num("width") * size_scale())
	_flare = sprite(Shape.ORB, num("flare") * size_scale())
	_flare.top_level = true
	_flare.global_position = _a
	_glint = sprite(Shape.GLINT, num("flare") * 1.4 * size_scale())
	setp(_glint, "width", 0.04)
	_glint.top_level = true


func _tick(t: float) -> void:
	var grow := num("grow_s")
	var hold := num("hold_s")
	var head := ease_out(span(t, 0.0, grow))
	var fade := span(t, grow + hold, life)
	var tail := ease_in(fade)
	var m := mat_of(_beam)
	m.set_shader_parameter("head", head)
	m.set_shader_parameter("tail", tail * 0.9)
	m.set_shader_parameter("t", t)
	m.set_shader_parameter("alpha", (1.0 - fade * 0.6) * (1.0 - stop_t()))
	_beam.scale.x = num("width") * size_scale() * (1.0 - 0.6 * fade)
	setp(_flare, "alpha", (1.0 - span(t, 0.0, grow + hold * 0.5)) * 0.9)
	_glint.global_position = _a.lerp(_b, head)
	setp(_glint, "rot", 0.785)
	setp(_glint, "alpha", 1.0 - span(t, grow, grow + 0.12))
	if not _hit and t >= grow:
		_hit = true
		arrived.emit(index, _b)
