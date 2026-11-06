extends VfxBlock
## Ground scorch left by a strong hit: dark burnt mark with a few element embers, fades out.
## Params: position, size (m), duration.

var _mark: MeshInstance3D


func defaults() -> Dictionary:
	return {"size": 1.3, "duration": 2.4, "height": 0.02}


func _build() -> void:
	life = num("duration")
	global_position = where(p.get("position")) + Vector3.UP * num("height")
	_mark = sprite(Shape.SCORCH, num("size") * size_scale(), Face.FLAT)
	setp(_mark, "seed", float(index) * 3.7 + 1.0)
	rotation.y = float(index) * 1.3


func _tick(t: float) -> void:
	var a := ease_out(span(t, 0.0, 0.08)) * (1.0 - span(t, life * 0.5, life))
	setp(_mark, "alpha", a * (1.0 - stop_t()))
