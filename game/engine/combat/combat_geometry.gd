class_name CombatGeometry
extends RefCounted
## Ground-plane helpers for the combat simulation. Positions are metres on
## the (x, z) plane, local to the encounter anchor; units store them as plain
## floats "x" and "z" and their facing as a unit vector "fx", "fz".


static func pos(u: Dictionary) -> Vector2:
	return Vector2(u["x"], u["z"])


static func set_pos(u: Dictionary, p: Vector2) -> void:
	var c := clamp_arena(p)
	u["x"] = c.x
	u["z"] = c.y


static func face(u: Dictionary, toward: Vector2) -> void:
	var d := toward - pos(u)
	if d.length_squared() > 0.000001:
		d = d.normalized()
		u["fx"] = d.x
		u["fz"] = d.y


static func dist(a: Dictionary, b: Dictionary) -> float:
	return pos(a).distance_to(pos(b))


static func clamp_arena(p: Vector2) -> Vector2:
	var r := BalanceCombat.ARENA_RADIUS_M
	if p.length() > r:
		return p.normalized() * r
	return p


## Moves `u` toward `target` by at most `step` metres. Returns true on arrival.
static func step_towards(u: Dictionary, target: Vector2, step: float) -> bool:
	var p := pos(u)
	var d := clamp_arena(target) - p
	var length := d.length()
	if length <= step or length < 0.0001:
		set_pos(u, target)
		return true
	face(u, target)
	set_pos(u, p + d / length * step)
	return false


## Point at `distance` from `anchor` on the segment toward `from`.
static func point_at_distance(anchor: Vector2, from: Vector2, distance: float) -> Vector2:
	var d := from - anchor
	if d.length_squared() < 0.000001:
		d = Vector2(0.0, 1.0)
	return anchor + d.normalized() * distance


## True when point `p` (a unit of radius UNIT_RADIUS_M) is inside a shape
## {shape, size_m, width_m, x, z, dx, dz}.
static func shape_contains(shape: Dictionary, p: Vector2) -> bool:
	var r := BalanceCombat.UNIT_RADIUS_M
	var origin := Vector2(shape["x"], shape["z"])
	var rel := p - origin
	var size := float(shape["size_m"])
	match str(shape["shape"]):
		"line":
			var d := Vector2(shape["dx"], shape["dz"])
			var along := rel.dot(d)
			var across := absf(d.cross(rel))
			return along >= -r and along <= size + r and across <= float(shape["width_m"]) * 0.5 + r
		"cone":
			if rel.length() > size + r:
				return false
			var facing := Vector2(shape["dx"], shape["dz"])
			if rel.length() < r:
				return true
			var half := deg_to_rad(BalanceCombat.TELEGRAPH_CONE_DEG) * 0.5
			return absf(facing.angle_to(rel)) <= half
	return rel.length() <= size + r


## Closest point outside the shape (with DODGE_MARGIN_M), for an escape.
static func escape_point(shape: Dictionary, p: Vector2) -> Vector2:
	var r := BalanceCombat.UNIT_RADIUS_M + BalanceCombat.DODGE_MARGIN_M
	var origin := Vector2(shape["x"], shape["z"])
	var rel := p - origin
	if str(shape["shape"]) == "line":
		var d := Vector2(shape["dx"], shape["dz"])
		var perp := Vector2(-d.y, d.x)
		var side := 1.0 if perp.dot(rel) >= 0.0 else -1.0
		var across := absf(perp.dot(rel))
		return clamp_arena(p + perp * side * (float(shape["width_m"]) * 0.5 + r - across))
	if rel.length_squared() < 0.000001:
		rel = Vector2(shape.get("dx", 0.0), shape.get("dz", 1.0))
		if rel.length_squared() < 0.000001:
			rel = Vector2(0.0, 1.0)
	var out := origin + rel.normalized() * (float(shape["size_m"]) + r)
	if out.length() > BalanceCombat.ARENA_RADIUS_M:
		# Cornered against the mist ring: slide along it instead.
		var tangent := Vector2(-rel.y, rel.x).normalized()
		out = origin + tangent * (float(shape["size_m"]) + r)
	return clamp_arena(out)
