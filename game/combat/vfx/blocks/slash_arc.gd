extends VfxBlock
## Crescent slash (follow-through beat): a thin arc that opens fast then fades.
## Params: position, size (m), sweep (0..1 of the circle), yaw (deg), tilt (deg), duration.

var _arc: MeshInstance3D


func defaults() -> Dictionary:
	return {"size": 1.6, "sweep": 0.42, "yaw": 0.0, "tilt": 60.0, "duration": 0.3}


func _build() -> void:
	life = num("duration")
	global_position = where(p.get("position"))
	rotation_degrees = Vector3(num("tilt"), num("yaw"), 0.0)
	_arc = sprite(Shape.CRESCENT, num("size") * size_scale(), Face.FLAT)
	setp(_arc, "radius", 0.4)
	setp(_arc, "width", 0.07)


func _tick(t: float) -> void:
	var open := ease_out(span(t, 0.0, life * 0.35))
	setp(_arc, "sweep", num("sweep") * open)
	setp(_arc, "alpha", 1.0 - ease_in(span(t, life * 0.35, life)))
