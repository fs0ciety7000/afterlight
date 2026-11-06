extends VfxBlock
## Charge gathered at the staff tip during the anticipation beat: hot orb that grows, a thin
## 4-ray glint, motes pulled inward. Pops at the end (release).
## Params: position, follow (Node3D), size, duration, gather (mote count).

var _orb: MeshInstance3D
var _glint: MeshInstance3D
var _gather: CPUParticles3D


func defaults() -> Dictionary:
	return {"size": 0.34, "duration": 0.3, "gather": 14}


func _build() -> void:
	life = num("duration") + 0.12
	global_position = where(p.get("follow"), where(p.get("position")))
	_orb = sprite(Shape.ORB, 0.1)
	_glint = sprite(Shape.GLINT, 0.1)
	setp(_glint, "width", 0.05)
	setp(_glint, "core", 0.08)
	if int(p["gather"]) > 0:
		_gather = particles(
			{
				"amount": int(p["gather"]),
				"lifetime": 0.28,
				"one_shot": false,
				"radius": 0.55 * size_scale(),
				"surface": true,
				"velocity": Vector2(0.0, 0.2),
				"radial_accel": -14.0,
				"size": 0.05,
				"scale_curve": "grow",
				"local": true,
			}
		)


func _tick(t: float) -> void:
	if is_instance_valid(p.get("follow")) and p.get("follow") is Node3D:
		global_position = (p["follow"] as Node3D).global_position
	var dur := num("duration")
	var k := ease_in(span(t, 0.0, dur)) * 0.7 + span(t, 0.0, dur) * 0.3
	var s := num("size") * size_scale()
	var pulse := 1.0 + (0.0 if reduced() else 0.08 * sin(t * 38.0))
	var pop := span(t, dur, life)
	var size := s * (0.25 + 0.75 * k) * pulse * (1.0 + 0.8 * pop)
	_orb.scale = Vector3.ONE * size * 1.6
	_glint.scale = Vector3.ONE * size * 3.0
	setp(_glint, "rot", 0.0 if reduced() else t * 2.0)
	var a := (1.0 - pop) * (1.0 - stop_t())
	setp(_orb, "alpha", a)
	setp(_glint, "alpha", a * (0.4 + 0.6 * k))
	if _gather and t > dur - 0.1:
		_gather.emitting = false
