extends VfxBlock
## Travelling bolt: hot head, velocity-stretched streak, short mote trail. Follows a quadratic
## curve (arc up, bend sideways) and homes on a moving target node. Emits `arrived` on contact.
## Params: from, to (Node3D or Vector3), to_offset (Vector3), speed (m/s), size, trail (m),
## arc (m up at mid-flight), curve (m sideways at mid-flight), curve_spread (m per index
## around the middle one, fans out volleys), trail_motes (count).

var _head: MeshInstance3D
var _streak: MeshInstance3D
var _trail: CPUParticles3D
var _start := Vector3.ZERO
var _travel := 0.5
var _hit := false
var _last := Vector3.ZERO


func defaults() -> Dictionary:
	return {
		"speed": 25.0,
		"size": 0.26,
		"trail": 0.9,
		"arc": 0.0,
		"curve": 0.0,
		"trail_motes": 10,
		"curve_spread": 0.0,
		"to_offset": Vector3.ZERO,
	}


func travel_time() -> float:
	var a := where(p.get("from"))
	var b := where(p.get("to")) + (p["to_offset"] as Vector3)
	return maxf(a.distance_to(b) / maxf(num("speed"), 0.1), 0.05)


func _build() -> void:
	_start = where(p.get("from"))
	_travel = travel_time()
	life = _travel + 0.35
	global_position = _start
	_last = _start
	var s := num("size") * size_scale()
	_streak = sprite(Shape.STREAK, s, Face.AXIAL)
	setp(_streak, "core", 0.28)
	_head = sprite(Shape.ORB, s * 1.8)
	if int(p["trail_motes"]) > 0:
		_trail = particles(
			{
				"amount": int(p["trail_motes"]),
				"lifetime": 0.3,
				"one_shot": false,
				"velocity": Vector2(0.0, 0.4),
				"size": s * 0.35,
			}
		)


func _target() -> Vector3:
	return where(p.get("to"), _start) + (p["to_offset"] as Vector3)


func _pos(k: float) -> Vector3:
	var b := _target()
	var mid := (_start + b) * 0.5
	var side := (b - _start).cross(Vector3.UP).normalized()
	var spread := (float(index) - (num("count", 1.0) - 1.0) * 0.5) * num("curve_spread")
	var ctrl := mid + Vector3.UP * num("arc") * 2.0 + side * (num("curve") + spread) * 2.0
	var u := 1.0 - k
	return _start * u * u + ctrl * 2.0 * u * k + b * k * k


func _tick(t: float) -> void:
	var k := clampf(t / _travel, 0.0, 1.0)
	if not _hit:
		var pos := _pos(k)
		global_position = pos
		var vel := pos - _last
		if vel.length() > 0.0001:
			var s := num("size") * size_scale()
			var len := clampf(vel.length() * 6.0, s, num("trail") * size_scale())
			_streak.global_transform = Transform3D(
				Basis(Vector3.RIGHT * s * 0.7, vel.normalized() * len, Vector3.BACK),
				pos - vel.normalized() * len * 0.4
			)
		_last = pos
		if k >= 1.0:
			_hit = true
			_head.visible = false
			_streak.visible = false
			if _trail:
				_trail.emitting = false
			arrived.emit(index, pos)
	if is_stopping() and not _hit:
		_head.visible = false
		_streak.visible = false
