extends VfxBlock
## Expanding ground ring (impact under the caster or the target).
## Params: position, follow, radius (end radius, m), duration, width (share of the quad).

var _ring: MeshInstance3D


func defaults() -> Dictionary:
	return {"radius": 2.4, "duration": 0.45, "width": 0.02, "height": 0.04}


func _build() -> void:
	life = num("duration")
	global_position = where(p.get("follow"), where(p.get("position"))) + Vector3.UP * num("height")
	_ring = sprite(Shape.RING, 1.0, Face.FLAT)
	setp(_ring, "width", num("width"))
	setp(_ring, "radius", 0.45)


func _tick(t: float) -> void:
	var k := ease_out(span(t, 0.0, life))
	var r := num("radius") * size_scale()
	var grow := 0.75 if reduced() else 0.2 + 0.8 * k
	_ring.scale = Vector3.ONE * r * 2.0 * grow
	setp(_ring, "alpha", (1.0 - k) * (1.0 - stop_t()))
