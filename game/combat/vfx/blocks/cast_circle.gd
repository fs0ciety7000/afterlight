extends VfxBlock
## Runic circle (original procedural design) under a caster or in the sky. Draws itself in,
## shows the cast / channel progress as a bright sweep on its outer ring, then fades.
## Params: position, follow (Node3D), radius, duration (fill time), appear_s, fade_s, spin
## (rad/s), sky (bool, faces down from above), height (m above position), detail (0..1),
## glyphs, motes (count), progress (bool), dark (bool: non-interruptible enemy cast).

var _circle: MeshInstance3D
var _floor_glow: MeshInstance3D
var _motes: CPUParticles3D


func defaults() -> Dictionary:
	return {
		"radius": 1.1,
		"duration": 0.3,
		"appear_s": 0.15,
		"fade_s": 0.25,
		"spin": 0.5,
		"sky": false,
		"height": 0.03,
		"detail": 1.0,
		"glyphs": 24.0,
		"motes": 10,
		"progress": true,
		"dark": false,
	}


func _build() -> void:
	life = num("appear_s") + maxf(num("duration"), 0.0) + num("fade_s")
	global_position = where(p.get("follow"), where(p.get("position"))) + Vector3.UP * num("height")
	var r := num("radius") * size_scale()
	var roles := ["dark", "dark"] if p["dark"] else ["core", "fringe"]
	var m := material(RUNE_SHADER, roles)
	m.set_shader_parameter("detail", num("detail"))
	m.set_shader_parameter("glyph_count", num("glyphs"))
	m.set_shader_parameter("seed", float(p.get("seed", 3.0)))
	# Keep the line about 2.5 cm wide whatever the radius.
	m.set_shader_parameter("line", clampf(0.012 / r, 0.003, 0.02))
	if p["dark"]:
		# A dark solid ring reads on both grounds: let it cover the background.
		m.set_shader_parameter("cover", 0.85)
	_circle = mesh_layer(ground_mesh(), m)
	_circle.scale = Vector3.ONE * r * 2.0
	if not p["dark"]:
		_floor_glow = sprite(Shape.ORB, r * 2.6, Face.FLAT)
		_floor_glow.position.y = -0.005
		setp(_floor_glow, "alpha", 0.0)
	if int(p["motes"]) > 0 and not p["sky"]:
		_motes = particles(
			{
				"amount": int(p["motes"]),
				"lifetime": 0.7,
				"one_shot": false,
				"ring": Vector2(r * 0.8, r * 0.95),
				"direction": Vector3.UP,
				"spread": 8.0,
				"velocity": Vector2(0.6, 1.4),
				"size": 0.06,
				"local": true,
			}
		)


func _tick(t: float) -> void:
	if is_instance_valid(p.get("follow")) and p.get("follow") is Node3D:
		global_position = (p["follow"] as Node3D).global_position + Vector3.UP * num("height")
	var appear_s := num("appear_s")
	var dur := maxf(num("duration"), 0.0)
	var appear := 1.0 if reduced() else ease_out(span(t, 0.0, appear_s))
	var fade := 1.0 - span(t, appear_s + dur, life)
	fade *= 1.0 - stop_t()
	var m := mat_of(_circle)
	m.set_shader_parameter("appear", appear)
	var prog := span(t, 0.0, appear_s + dur) if p["progress"] and dur > 0.0 else -1.0
	m.set_shader_parameter("progress", prog)
	m.set_shader_parameter("spin", 0.0 if reduced() else t * num("spin"))
	# Small flare when the cast completes.
	var done_pulse := 1.0 + 0.6 * (1.0 - span(t, appear_s + dur, appear_s + dur + 0.15))
	if t < appear_s + dur:
		done_pulse = 1.0
	m.set_shader_parameter("alpha", fade * minf(done_pulse, 1.6))
	if _floor_glow:
		setp(_floor_glow, "alpha", 0.25 * appear * fade)
	if _motes and t > appear_s + dur:
		_motes.emitting = false


func outro_s() -> float:
	return 0.15
