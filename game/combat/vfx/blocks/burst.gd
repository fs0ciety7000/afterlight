extends VfxBlock
## Impact: white-hot flash, a turning glint, a camera-facing ring and element sparks.
## `crit` makes it bigger, adds a gold glint and requests hit-stop + camera shake (GDD §14).
## Params: position, size, crit (bool), sparks (count), ring (bool), glint (bool),
## duration, hitstop_ms / shake (crit feel, defaults from GDD §14).

var _flash: MeshInstance3D
var _glint: MeshInstance3D
var _gold: MeshInstance3D
var _ring: MeshInstance3D
var _arcs: Array[MeshInstance3D] = []


func defaults() -> Dictionary:
	return {
		"size": 1.0,
		"crit": false,
		"sparks": 14,
		"ring": true,
		"glint": true,
		"duration": 0.4,
		"hitstop_ms": 50.0,
		"shake": 0.3,
	}


func _size() -> float:
	return num("size") * size_scale() * (1.5 if p["crit"] else 1.0)


func _build() -> void:
	life = num("duration")
	global_position = where(p.get("position"))
	var s := _size()
	_flash = sprite(Shape.ORB, s * 1.5)
	setp(_flash, "core", 0.32)
	if p["glint"]:
		_glint = sprite(Shape.GLINT, s * 1.7)
		setp(_glint, "width", 0.035)
		setp(_glint, "rot", float(index) * 0.7 + 0.3)
	if p["ring"]:
		_ring = sprite(Shape.RING, s)
		setp(_ring, "width", 0.025)
	if p["crit"]:
		_gold = sprite(Shape.GLINT, s * 2.4, Face.CAMERA, ["core", "fringe"])
		var gm := mat_of(_gold)
		gm.set_shader_parameter("core_color", VfxPalette.color("gold", "core"))
		gm.set_shader_parameter("fringe_color", VfxPalette.color("gold", "fringe"))
		gm.set_shader_parameter("width", 0.03)
		gm.set_shader_parameter("rot", 0.0)
		if host:
			host.request_hit_stop(num("hitstop_ms") / 1000.0)
			host.request_shake(num("shake"))
	_sparks(s)


func _sparks(s: float) -> void:
	var n := int(num("sparks") * (1.6 if p["crit"] else 1.0))
	if n <= 0:
		return
	var cfg := {
		"amount": n,
		"lifetime": 0.38,
		"velocity": Vector2(3.0, 7.5) * s,
		"damping": 9.0,
		"size": 0.07 * s,
		"shape": Shape.STREAK,
		"face": Face.AXIAL,
		"gravity": Vector3(0, -6.0, 0),
	}
	match element():
		"fire", "ash":
			cfg["gravity"] = Vector3(0, 3.0, 0)
			cfg["shape"] = Shape.MOTE
			cfg["face"] = Face.CAMERA
			cfg["lifetime"] = 0.6
			cfg["velocity"] = Vector2(1.5, 4.5) * s
		"frost":
			cfg["shape"] = Shape.MOTE
			cfg["face"] = Face.CAMERA
			cfg["size"] = 0.1 * s
			cfg["velocity"] = Vector2(2.0, 5.0) * s
		"lightning":
			cfg["lifetime"] = 0.22
			cfg["velocity"] = Vector2(5.0, 10.0) * s
			for i in 2:
				var arc := mesh_layer(quad_mesh(), material(ARC_SHADER))
				arc.top_level = true
				var a := global_position
				var dir := Vector3(cos(i * 2.6 + index), 0.3, sin(i * 2.6 + index)).normalized()
				orient_between(arc, a, a + dir * s * 1.4, 0.5 * s)
				(arc.material_override as ShaderMaterial).set_shader_parameter("seed", i + index)
				_arcs.append(arc)
	var sp := particles(cfg)
	var sm := sp.material_override as ShaderMaterial
	sm.set_shader_parameter("stretch", 4.0)
	sm.set_shader_parameter("core", 0.35)


func _tick(t: float) -> void:
	var s := _size()
	var f := span(t, 0.0, 0.06)
	var out := span(t, 0.06, life * 0.7)
	_flash.scale = Vector3.ONE * s * 1.5 * (0.6 + 0.9 * ease_out(f)) * (1.0 - 0.3 * out)
	setp(_flash, "alpha", 1.0 - ease_in(out))
	if _glint:
		_glint.scale = Vector3.ONE * s * 1.7 * (0.5 + 0.7 * ease_out(span(t, 0.0, 0.1)))
		setp(_glint, "alpha", 1.0 - span(t, 0.05, life * 0.6))
	if _gold:
		_gold.scale = Vector3.ONE * s * 2.4 * (0.6 + 0.6 * ease_out(span(t, 0.0, 0.1)))
		setp(_gold, "alpha", 1.0 - span(t, 0.08, life))
	if _ring:
		var k := ease_out(span(t, 0.0, life * 0.8))
		_ring.scale = Vector3.ONE * s * (1.4 if reduced() else 0.6 + 1.6 * k)
		setp(_ring, "alpha", (1.0 - k) * 0.9)
	for arc in _arcs:
		var am := arc.material_override as ShaderMaterial
		am.set_shader_parameter("t", t)
		am.set_shader_parameter("alpha", 1.0 - span(t, 0.05, life * 0.6))
