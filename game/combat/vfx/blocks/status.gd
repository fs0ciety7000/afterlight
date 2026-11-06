extends VfxBlock
## Looping status visual on a target until stop() (status_expired). Each status has a shape
## of its own, never colour alone (GDD §8):
## burn = rising embers, chill = falling frost motes + ground ring, frozen = crystal shards,
## shock = flickering arcs, stun = small runic halo over the head (no stars),
## weaken = dim violet motes sinking, haste = short ember streaks rising.
## Params: follow (Node3D) or position, kind, height (target height, m; measured from the
## followed node's meshes unless height_fixed is set), radius (m),
## stacks (1..3, more particles), duration (< 0 = until stop()).

const KIND_ELEMENT := {
	"burn": "fire",
	"chill": "frost",
	"frozen": "frost",
	"shock": "lightning",
	"stun": "arcane",
	"weaken": "arcane",
	"haste": "danger",
}

static var _shard: CylinderMesh

var _layers: Array[GeometryInstance3D] = []
var _arcs: Array[MeshInstance3D] = []
var _halo: MeshInstance3D
var _next_arc := 0.0
var _rng := RandomNumberGenerator.new()


func defaults() -> Dictionary:
	return {"kind": "burn", "height": 1.4, "radius": 0.4, "stacks": 1, "duration": -1.0}


func outro_s() -> float:
	return 0.35


static func shard_mesh() -> CylinderMesh:
	if _shard == null:
		_shard = CylinderMesh.new()
		_shard.top_radius = 0.0
		_shard.bottom_radius = 0.2
		_shard.height = 1.0
		_shard.radial_segments = 5
		_shard.rings = 1
	return _shard


func _build() -> void:
	var kind := String(p["kind"])
	if not p.has("element_fixed"):
		p["element"] = KIND_ELEMENT.get(kind, element())
	_rng.seed = hash(kind) + index
	var dur := num("duration")
	life = -1.0 if dur < 0.0 else dur + outro_s()
	if not p.has("height_fixed"):
		p["height"] = height_of(p.get("follow"), num("height"))
	var h := num("height") * size_scale()
	var r := num("radius") * size_scale()
	var stacks := clampi(int(num("stacks")), 1, 3)
	match kind:
		"burn":
			var embers := particles(
				{
					"amount": 10 + 6 * stacks,
					"lifetime": 0.9,
					"one_shot": false,
					"radius": r * 1.5,
					"velocity": Vector2(0.2, 0.6),
					"gravity": Vector3(0, 1.8, 0),
					"size": 0.14,
					"roles": ["spark", "fringe"],
					"scale_curve": "pop",
					"local": false,
				}
			)
			embers.position.y = h * 0.6
			_layers.append(embers)
			var heat := sprite(Shape.ORB, r * 3.0)
			heat.position.y = h * 0.4
			setp(heat, "core", 0.0)
			heat.set_meta("flicker", true)
			_layers.append(heat)
		"chill", "weaken":
			var motes := particles(
				{
					"amount": 10,
					"lifetime": 1.2,
					"one_shot": false,
					"radius": r * 1.1,
					"velocity": Vector2(0.0, 0.2),
					"gravity": Vector3(0, -0.8, 0),
					"size": 0.12,
					"local": true,
				}
			)
			motes.position.y = h * 0.7
			_layers.append(motes)
			if kind == "chill":
				var ring := sprite(Shape.RING, r * 2.6, Face.FLAT)
				ring.position.y = 0.04
				setp(ring, "width", 0.04)
				_layers.append(ring)
		"frozen":
			for i in 6:
				var m := ShaderMaterial.new()
				m.shader = ICE_SHADER
				var s := mesh_layer(shard_mesh(), m)
				var a := TAU * i / 6.0 + _rng.randf() * 0.5
				var tall := h * _rng.randf_range(0.6, 1.0)
				s.position = Vector3(cos(a) * r * 0.7, tall * 0.4, sin(a) * r * 0.7)
				s.rotation = Vector3(_rng.randf_range(-0.5, 0.5), a, _rng.randf_range(-0.5, 0.5))
				s.set_meta("tall", tall)
				_layers.append(s)
		"shock":
			for i in 2:
				var arc := mesh_layer(quad_mesh(), material(ARC_SHADER))
				arc.top_level = true
				setp(arc, "seed", float(i) * 7.0 + index)
				_arcs.append(arc)
		"stun":
			var m := material(RUNE_SHADER)
			m.set_shader_parameter("detail", 0.0)
			m.set_shader_parameter("glyph_count", 9.0)
			m.set_shader_parameter("line", 0.03)
			_halo = mesh_layer(ground_mesh(), m)
			_halo.position.y = h + 0.25
			_halo.scale = Vector3.ONE * 0.75 * size_scale()
		"haste":
			var streaks := particles(
				{
					"amount": 8,
					"lifetime": 0.5,
					"one_shot": false,
					"radius": r,
					"velocity": Vector2(1.5, 2.5),
					"direction": Vector3.UP,
					"spread": 5.0,
					"size": 0.1,
					"shape": Shape.STREAK,
					"face": Face.AXIAL,
					"local": true,
				}
			)
			(streaks.material_override as ShaderMaterial).set_shader_parameter("stretch", 4.0)
			streaks.position.y = h * 0.3
			_layers.append(streaks)


func _tick(t: float) -> void:
	global_position = where(p.get("follow"), where(p.get("position")))
	var a := ease_out(span(t, 0.0, 0.15)) * (1.0 - stop_t())
	var dur := num("duration")
	if dur >= 0.0 and t >= dur and not is_stopping():
		stop()
	if is_stopping():
		for l in _layers:
			if l is CPUParticles3D:
				(l as CPUParticles3D).emitting = false
	match String(p["kind"]):
		"burn":
			for l in _layers:
				if l.has_meta("flicker"):
					var f := 0.0 if reduced() else 0.12 * sin(t * 17.0) + 0.08 * sin(t * 29.0)
					setp(l, "alpha", a * (0.55 + f))
		"chill":
			for l in _layers:
				if l is MeshInstance3D:
					var pulse := 0.0 if reduced() else 0.15 * sin(t * 3.0)
					setp(l, "alpha", a * (0.55 + pulse))
		"frozen":
			_tick_frozen(t)
		"shock":
			_tick_shock(t, a)
		"stun":
			var m := mat_of(_halo)
			m.set_shader_parameter("alpha", a)
			m.set_shader_parameter("appear", ease_out(span(t, 0.0, 0.25)))
			m.set_shader_parameter("spin", 0.0 if reduced() else t * 2.2)


func _tick_frozen(t: float) -> void:
	var grow := 1.0 if reduced() else ease_out(span(t, 0.0, 0.18))
	var out := stop_t()
	for l in _layers:
		var tall := float(l.get_meta("tall", 1.0))
		l.scale = Vector3(1.0, tall * grow, 1.0) * (1.0 - out * 0.3)
		setp(l, "alpha", 1.0 - out)
	if is_stopping() and get_meta("shattered", false) == false:
		set_meta("shattered", true)
		var shards := particles(
			{
				"amount": 16,
				"lifetime": 0.45,
				"radius": num("radius") * size_scale() * 0.6,
				"velocity": Vector2(1.5, 3.5),
				"gravity": Vector3(0, -7, 0),
				"size": 0.1,
				"shape": Shape.MOTE,
			}
		)
		shards.position.y = num("height") * 0.4


func _tick_shock(t: float, a: float) -> void:
	var h := num("height") * size_scale()
	var r := num("radius") * size_scale() * 1.3
	if t >= _next_arc:
		_next_arc = t + 0.16
		var c := global_position + Vector3.UP * h * 0.5
		for arc in _arcs:
			var u := _rng.randf_range(0.0, TAU)
			var v := _rng.randf_range(-0.8, 0.8)
			var p1 := c + Vector3(cos(u) * r, v * h * 0.5, sin(u) * r)
			var p2 := c + Vector3(cos(u + 2.0) * r, -v * h * 0.4, sin(u + 2.0) * r)
			orient_between(arc, p1, p2, 0.6)
	for arc in _arcs:
		var m := mat_of(arc)
		m.set_shader_parameter("t", t)
		var flick := fmod(t * 6.25, 1.0)
		m.set_shader_parameter("alpha", a * (1.0 if flick < 0.55 else 0.0))
