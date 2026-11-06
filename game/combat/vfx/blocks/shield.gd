extends VfxBlock
## Runic dome (Barrière défensive): grows from the ground, ripples where it is hit, shatters
## when broken, fades when it expires. Small rune ring on the ground under it.
## Params: position, follow, radius (m), duration (s, < 0 = until stop()), appear_s.
## Methods: hit(from_position) for absorbed hits, break_shield() when it is destroyed.

static var _sphere: SphereMesh

var _dome: MeshInstance3D
var _base: MeshInstance3D
var _hit_age := -10.0
var _break_age := -1.0


func defaults() -> Dictionary:
	return {"radius": 1.0, "duration": 4.0, "appear_s": 0.2}


func outro_s() -> float:
	return 0.35 if _break_age >= 0.0 else 0.25


static func sphere_mesh() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 32
		_sphere.rings = 12
		_sphere.is_hemisphere = true
	return _sphere


func _build() -> void:
	var dur := num("duration")
	life = -1.0 if dur < 0.0 else dur + outro_s()
	var m := material(SHIELD_SHADER, ["core", "spark"])
	_dome = mesh_layer(sphere_mesh(), m)
	var bm := material(RUNE_SHADER, ["core", "spark"])
	bm.set_shader_parameter("detail", 0.0)
	bm.set_shader_parameter("glyph_count", 18.0)
	_base = mesh_layer(ground_mesh(), bm)
	_base.position.y = 0.03


func hit(from_position: Vector3) -> void:
	_hit_age = age
	var local := global_transform.affine_inverse() * from_position
	local.y = maxf(local.y, 0.3)
	mat_of(_dome).set_shader_parameter("hit_dir", local.normalized())


func break_shield() -> void:
	if _break_age >= 0.0:
		return
	_break_age = age
	particles(
		{
			"amount": 24,
			"lifetime": 0.5,
			"radius": num("radius") * size_scale() * 0.9,
			"surface": true,
			"velocity": Vector2(1.5, 3.5),
			"gravity": Vector3(0, -5, 0),
			"size": 0.09,
			"shape": Shape.MOTE,
			"roles": ["core", "spark"],
		}
	)
	stop()


func _tick(t: float) -> void:
	global_position = where(p.get("follow"), where(p.get("position")))
	var dur := num("duration")
	if dur >= 0.0 and t >= dur and not is_stopping():
		stop()
	var r := num("radius") * size_scale()
	_dome.scale = Vector3.ONE * r
	_base.scale = Vector3.ONE * r * 2.3
	var appear := 1.0 if reduced() else ease_out(span(t, 0.0, num("appear_s")))
	var m := mat_of(_dome)
	m.set_shader_parameter("appear", appear)
	m.set_shader_parameter("t", t)
	var ht := (t - _hit_age) / 0.4
	m.set_shader_parameter("hit_t", ht if ht >= 0.0 and ht <= 1.0 else -1.0)
	var out := stop_t()
	if _break_age >= 0.0:
		m.set_shader_parameter("shatter", ease_out(out))
		m.set_shader_parameter("alpha", 1.0 + 0.5 * (1.0 - out))
	else:
		m.set_shader_parameter("alpha", 1.0 - out)
	var bm := mat_of(_base)
	bm.set_shader_parameter("appear", appear)
	bm.set_shader_parameter("spin", 0.0 if reduced() else -t * 0.4)
	bm.set_shader_parameter("alpha", 0.8 * (1.0 - out))
