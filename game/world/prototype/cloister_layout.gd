extends "res://game/world/prototype/ruins_layout.gd"
## Silent Dial Cloister layout for the offline builder (build_locations.gd extends this chain).
## One scene with seven rooms laid out as docs/content/dungeon.md §2.4 (centres in metres, -Z north,
## 4 m corridors): vestibule, bell gallery, fountain, courtyard, kennel, campfire, dial (+6 m).
## Roofless ruined rooms (the 50° camera looks down into them); night light: moon, cold ambient,
## warm point sources per room, shadow-only roofs that keep the covered rooms dark.
##
## Beyond the location contract (docs/ARCHITECTURE.md) the scene carries:
##   Rooms/<room id>    Area3D (no layer, mask 2) over each room; meta room, kind, index, intensity
##   Gates/<name>       StaticBody3D on layer 5 (not blocking by default) with the grille visual;
##                      meta room, opens_on (encounter id). The app closes / opens them from state
##   Environment/Rooms/<room id>  the room's lights; Environment/Rooms/dial/AfterLight is off
##                      (the warm "lumière d'après" after Morvaine, milestone 7)

const CLOISTER_ROOMS := {
	"vestibule": {"centre": Vector2(0, 0), "size": Vector2(36, 36), "kind": "encounter"},
	"gallery": {"centre": Vector2(0, -50), "size": Vector2(36, 44), "kind": "encounter"},
	"fountain": {"centre": Vector2(30, -66), "size": Vector2(14, 14), "kind": "rest"},
	"courtyard": {"centre": Vector2(30, -104), "size": Vector2(40, 40), "kind": "encounter"},
	"kennel": {"centre": Vector2(-18, -104), "size": Vector2(36, 36), "kind": "elite"},
	"campfire": {"centre": Vector2(-18, -137), "size": Vector2(12, 14), "kind": "checkpoint"},
	"dial": {"centre": Vector2(-18, -176), "size": Vector2(40, 40), "kind": "boss"},
}
## Tension curve of dungeon.md §2.5, stored on Rooms/<id> for the app.
const CLOISTER_INTENSITY := {
	"vestibule": 0.4,
	"gallery": 0.6,
	"fountain": 0.1,
	"courtyard": 0.7,
	"kennel": 0.8,
	"campfire": 0.1,
	"dial": 1.0,
}
const DIAL_Y := 6.0
const DIAL_R := 20.0
const WALL_T := 0.8
const WALL_H := 4.5
## Moon (DESIGN.md night): high and cold, from the south-east so the north walls catch it.
const MOON_PITCH := -58.0
const MOON_YAW := 150.0
const MOON := Color("#bcd0ff")
const NIGHT_AMBIENT := Color("#1a2433")
const WARM := Color("#ffb066")

var _floors: Array = []  # Rect2 of every room and corridor floor (splat, outside dressing)


func _cloister_height(x: float, z: float) -> float:
	# floors at 0; the postern stair climbs 3 m to the Ruins; the dial room and everything north of
	# the campfire stair sits 6 m up
	var h := 0.0
	if z > 28.0 and absf(x) < 12.0:
		h = 3.0 * clampf((z - 28.0) / 6.0, 0.0, 1.0)
	if z < -144.0:
		h = DIAL_Y * clampf((-144.0 - z) / 12.0, 0.0, 1.0)
	if z < -200.0 and absf(x + 18.0) < 8.0:
		h -= 3.0 * clampf((-200.0 - z) / 6.0, 0.0, 1.0)  # outer stair, down the cliff
	if not _on_floor(Vector2(x, z), 0.6):
		h += 0.15 + noise.get_noise_2d(x * 0.6, z * 0.6) * 0.35
	return h


func _cloister_splat(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	if _on_floor(p, 0.0):
		var c: Vector2 = CLOISTER_ROOMS["courtyard"]["centre"]
		if absf(x - c.x) < 15.0 and absf(z - c.y) < 15.0:
			# the garth: grass, worn earth where the walk crosses it
			var walk := 1.0 - smoothstep(1.2, 2.2, minf(absf(x - c.x), absf(z - c.y)))
			return Color(walk * 0.7, 0.0, 0.0, 1.0)
		# paving broken by patches of bare earth and moss, so the big rooms are not one flat tile
		var earth := smoothstep(0.3, 0.55, noise.get_noise_2d(x * 0.7 + 40.0, z * 0.7))
		var moss := smoothstep(0.15, 0.45, noise2.get_noise_2d(x * 1.3, z * 1.3 + 70.0))
		var cob := clampf(1.0 - earth * 0.85 - moss * 0.6, 0.0, 1.0)
		return Color(earth, cob, moss * 0.9, 1.0)
	var forest := 0.6 + 0.4 * noise2.get_noise_2d(x * 3.0, z * 3.0)
	return Color(0.3, 0.0, forest, 1.0)


func _on_floor(p: Vector2, margin: float) -> bool:
	for r: Rect2 in _floors:
		if r.grow(margin).has_point(p):
			return true
	var dial: Vector2 = CLOISTER_ROOMS["dial"]["centre"]
	return p.distance_to(dial) < DIAL_R + 4.0 + margin  # with the lantern alcoves


func _build_cloister() -> void:
	_begin("SilentDialCloister")
	rng.seed = 3003
	_height_fn = _cloister_height
	_splat_fn = _cloister_splat
	tint_bias = -0.15
	bright_scale = 0.8  # moonlit stone: the shared kit is painted for daylight
	for n in ["Rooms", "Gates"]:
		_add(scene_root, Node3D.new(), n)
	_floors.clear()
	for id: String in CLOISTER_ROOMS:
		if id == "dial":
			continue
		var r: Dictionary = CLOISTER_ROOMS[id]
		_floors.append(Rect2(r["centre"] - r["size"] * 0.5, r["size"]))
	# corridors (4 m) and alcoves: [from, to] along x or z, floor rect between the room walls
	var corridors := [
		[Vector2(0, 18.4), Vector2(0, 38.0)],  # postern stair, up to the Ruins
		[Vector2(0, -18.4), Vector2(0, -27.6)],  # vestibule -> gallery
		[Vector2(18.4, -66), Vector2(22.6, -66)],  # gallery east door -> fountain
		[Vector2(30, -73.4), Vector2(30, -83.6)],  # fountain -> courtyard
		[Vector2(9.6, -104), Vector2(0.4, -104)],  # courtyard west door -> kennel
		[Vector2(-18, -122.4), Vector2(-18, -129.6)],  # kennel -> campfire
		[Vector2(-18, -144.4), Vector2(-18, -155.7)],  # campfire stair -> dial
		[Vector2(-18, -196.3), Vector2(-18, -208.0)],  # dial north door -> outer stair
		[Vector2(-18.4, 0), Vector2(-23.5, 0)],  # bell-ringer's stair (vestibule end)
		[Vector2(-24.4, -137), Vector2(-29.5, -137)],  # bell-ringer's stair (campfire end)
	]
	for c in corridors:
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		var r := Rect2(a, Vector2.ZERO).expand(b).grow(2.0)
		_floors.append(r)
	_terrain_rect("silent_dial_cloister", Rect2i(-56, -226, 120, 276), 2)
	_night_environment()
	# rooms: walls on their four sides with 4 m doors (offset along the side from its middle)
	_room_walls("vestibule", {"n": [0.0], "s": [0.0], "w": [0.0]}, ["s"])
	_room_walls("gallery", {"n": [0.0], "s": [0.0], "e": [-16.0]}, ["s"])
	_room_walls("fountain", {"w": [0.0], "n": [0.0]}, ["s"])
	_room_walls("courtyard", {"s": [0.0], "w": [0.0]}, ["s"])
	_room_walls("kennel", {"e": [0.0], "n": [0.0]}, ["s"])
	_room_walls("campfire", {"s": [0.0], "n": [0.0], "w": [0.0]}, ["s"])
	_dial_walls()
	for c in corridors:
		_corridor(c[0], c[1])
	_dress_vestibule()
	_dress_gallery()
	_dress_fountain()
	_dress_courtyard()
	_dress_kennel()
	_dress_campfire()
	_dress_dial()
	_cloister_outside()
	for id in ["vestibule", "gallery", "courtyard", "kennel", "dial"]:
		_floor_debris(id)
	_floor_tufts()
	_flush()
	_cloister_markers()
	_save_to("res://game/world/dungeons/", "silent_dial_cloister.tscn")


# --- walls -------------------------------------------------------------------------------------


func _room_walls(id: String, doors: Dictionary, low_sides: Array) -> void:
	# low_sides: the south walls, between the camera and Fern, are broken lower
	var r: Dictionary = CLOISTER_ROOMS[id]
	var c: Vector2 = r["centre"]
	var h: Vector2 = r["size"] * 0.5 + Vector2(WALL_T, WALL_T) * 0.5
	var sides := {
		"n": [c + Vector2(-h.x - WALL_T * 0.5, -h.y), c + Vector2(h.x + WALL_T * 0.5, -h.y)],
		"s": [c + Vector2(-h.x - WALL_T * 0.5, h.y), c + Vector2(h.x + WALL_T * 0.5, h.y)],
		"w": [c + Vector2(-h.x, -h.y + WALL_T * 0.5), c + Vector2(-h.x, h.y - WALL_T * 0.5)],
		"e": [c + Vector2(h.x, -h.y + WALL_T * 0.5), c + Vector2(h.x, h.y - WALL_T * 0.5)],
	}
	for side: String in sides:
		var a: Vector2 = sides[side][0]
		var b: Vector2 = sides[side][1]
		var mid := (a + b) * 0.5
		var along := (b - a).normalized()
		var gaps := []
		for off in doors.get(side, []):
			gaps.append(mid + along * float(off))
		_wall_run(a, b, gaps, side in low_sides)


func _wall_run(a: Vector2, b: Vector2, doors: Array, low: bool) -> void:
	# wall pieces stretched to fill each solid stretch, one collision box per stretch; an arch
	# over each 4 m door
	var d := b - a
	var length := d.length()
	var dir := d / length
	var yaw := atan2(-dir.y, dir.x)
	var cuts := []
	for p: Vector2 in doors:
		var t := (p - a).dot(dir)
		cuts.append(t)
		if low:
			continue  # no arch over a door in a low (south) wall: it would hide the room
		var y := minf(_height(p.x, p.y), _height(p.x + dir.x, p.y + dir.y))
		_put_at("arch", Vector3(p.x, y - 0.05, p.y), yaw)
	cuts.sort()
	var t0 := 0.0
	var stretches := []
	for t in cuts:
		stretches.append([t0, t - 2.0])
		t0 = t + 2.0
	stretches.append([t0, length])
	for s in stretches:
		var s0: float = s[0]
		var s1: float = s[1]
		if s1 - s0 < 0.3:
			continue
		var n := maxi(1, roundi((s1 - s0) / 4.0))
		var piece := (s1 - s0) / n
		var base := 1e9
		var top := -1e9
		for k in n:
			var p := a + dir * (s0 + piece * (k + 0.5))
			var y0 := _height(p.x - dir.x * piece * 0.5, p.y - dir.y * piece * 0.5)
			var y1 := _height(p.x + dir.x * piece * 0.5, p.y + dir.y * piece * 0.5)
			var y := minf(y0, y1) - 0.1
			# taller pieces where the floor climbs under them (ramps)
			var sy := 1.0 + absf(y1 - y0) / WALL_H
			base = minf(base, y)
			top = maxf(top, y + WALL_H * sy)
			var kit := "wall"
			if low and rng.randf() < 0.65:
				kit = "wall_broken"
			# odd pieces 1.5 % deeper: neighbouring plinths never share a face plane
			var sc := Vector3(piece / 4.0, sy, 1.0 + 0.015 * (k % 2))
			_put_at(kit, Vector3(p.x, y, p.y), yaw, sc)
		var cm := a + dir * (s0 + s1) * 0.5
		_box_collider(
			Vector3(cm.x, (base + top) * 0.5, cm.y), Vector3(s1 - s0, top - base + 2.0, WALL_T), yaw
		)


func _corridor(a: Vector2, b: Vector2) -> void:
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x) * (2.0 + WALL_T * 0.5)
	# start / end on the room walls' outer faces
	var a2 := a + dir * WALL_T * 0.5
	var b2 := b - dir * WALL_T * 0.5
	var low := absf(dir.x) > 0.5  # east-west corridors: the south wall is lower
	_wall_run(a2 + side, b2 + side, [], low and side.y > 0)
	_wall_run(a2 - side, b2 - side, [], low and side.y < 0)


func _cap(at: Vector2, yaw: float) -> void:
	# closes a corridor end (stair head, alcove back)
	_wall_run(
		at + Vector2(cos(yaw), -sin(yaw)) * 2.8, at - Vector2(cos(yaw), -sin(yaw)) * 2.8, [], false
	)


func _dial_walls() -> void:
	# 32 pieces on a 20.4 m circle; doors south (from the campfire stair) and north (after the
	# boss); four lantern alcoves on the diagonals
	var c: Vector2 = CLOISTER_ROOMS["dial"]["centre"]
	var r := DIAL_R + WALL_T * 0.5
	for k in 32:
		var ang := (k + 0.5) * TAU / 32.0  # 0 = east, counter-clockwise seen from above (-z)
		var p := c + Vector2(cos(ang), -sin(ang)) * r
		var yaw := ang + PI * 0.5  # tangent
		if k == 7 or k == 8 or k == 23 or k == 24:
			if k == 8 or k == 24:
				var mid := ang - TAU / 64.0
				var q := c + Vector2(cos(mid), -sin(mid)) * r
				_put_at("arch", Vector3(q.x, DIAL_Y - 0.05, q.y), mid + PI * 0.5)
			continue  # doors at north (k 7-8) and south (k 23-24): 8 m gap framed by one arch
		if k % 8 == 3:
			_alcove(c, ang)
			continue
		var chord := 2.0 * r * sin(PI / 32.0)
		_put_at(
			"wall",
			Vector3(p.x, DIAL_Y - 0.1, p.y),
			yaw,
			Vector3(chord / 4.0 + 0.02, 1.0, 1.0 + 0.015 * (k % 2))
		)
		_box_collider(Vector3(p.x, DIAL_Y + 2.0, p.y), Vector3(chord + 0.1, 8.0, WALL_T), yaw)
	# door jambs: the 8 m gaps are narrowed to 4 m doors by two short walls each
	for ang: float in [PI * 0.5, PI * 1.5]:
		for s: float in [-1.0, 1.0]:
			var t := Vector2(-sin(ang), -cos(ang)) * s * 3.0
			var p := c + Vector2(cos(ang), -sin(ang)) * r + t
			var yaw := ang + PI * 0.5
			_put_at("wall", Vector3(p.x, DIAL_Y - 0.1, p.y), yaw, Vector3(0.5, 1.0, 1.03))
			_box_collider(Vector3(p.x, DIAL_Y + 2.0, p.y), Vector3(2.0, 8.0, WALL_T), yaw)


func _alcove(c: Vector2, ang: float) -> void:
	var out := Vector2(cos(ang), -sin(ang))
	var tan := Vector2(-out.y, out.x)
	var r := DIAL_R + WALL_T * 0.5
	var mouth := c + out * r
	_put_at("arch", Vector3(mouth.x, DIAL_Y - 0.05, mouth.y), ang + PI * 0.5)
	var back := c + out * (r + 3.0)
	_put_at("wall", Vector3(back.x, DIAL_Y - 0.1, back.y), ang + PI * 0.5, Vector3(1.4, 1.0, 1.0))
	_box_collider(Vector3(back.x, DIAL_Y + 2.0, back.y), Vector3(5.6, 8.0, WALL_T), ang + PI * 0.5)
	for s: float in [-1.0, 1.0]:
		var p := mouth + out * 1.5 + tan * s * 2.6
		_put_at("wall", Vector3(p.x, DIAL_Y - 0.1, p.y), ang, Vector3(0.8, 1.0, 1.0 + 0.015 * s))
		_box_collider(Vector3(p.x, DIAL_Y + 2.0, p.y), Vector3(3.4, 8.0, WALL_T), ang)


func _gate(gate_name: String, at: Vector2, yaw: float, room: String, opens_on: String) -> void:
	# a grille the app closes until the room is won: own body on layer 5 so it never blocks on
	# its own (docs/content/dungeon.md 2.3 "Portes"), visual as a separate node it can hide
	var body := StaticBody3D.new()
	_add(scene_root.get_node("Gates"), body, gate_name)
	var y := _height(at.x, at.y)
	body.position = Vector3(at.x, y, at.y)
	body.rotation.y = yaw
	body.collision_layer = 16
	body.collision_mask = 0
	body.set_meta("room", room)
	body.set_meta("opens_on", opens_on)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.4)
	shape.shape = box
	shape.position.y = 2.0
	_add(body, shape, "Shape")
	# one-instance MultiMesh: the kit material reads its tint from the instance custom data
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = meshes["grille"]
	mm.instance_count = 1
	mm.set_instance_custom_data(0, Color(tint_bias, 0.95, 0.5, 0.0))
	var mi := MultiMeshInstance3D.new()
	_add(body, mi, "Grille")
	mi.multimesh = mm


# --- rooms -------------------------------------------------------------------------------------


func _room_area(id: String, index: int) -> void:
	var r: Dictionary = CLOISTER_ROOMS[id]
	var c: Vector2 = r["centre"]
	var area := Area3D.new()
	_add(scene_root.get_node("Rooms"), area, id)
	var y := DIAL_Y if id == "dial" else 0.0
	area.position = Vector3(c.x, y + 3.0, c.y)
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	area.set_meta("room", id)
	area.set_meta("index", index)
	area.set_meta("kind", r["kind"])
	area.set_meta("intensity", CLOISTER_INTENSITY[id])
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(r["size"].x, 6.0, r["size"].y)
	shape.shape = box
	_add(area, shape, "Shape")


func _room_lights(id: String) -> Node3D:
	var env := scene_root.get_node("Environment")
	if not env.has_node("Rooms"):
		_add(env, Node3D.new(), "Rooms")
	var holder := Node3D.new()
	_add(env.get_node("Rooms"), holder, id)
	return holder


func _omni(
	id: String, light_name: String, at: Vector3, color: Color, energy: float, rng_m: float
) -> OmniLight3D:
	var l := OmniLight3D.new()
	_add(_room_lights_of(id), l, light_name)
	l.position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.light_bake_mode = Light3D.BAKE_DISABLED
	return l


func _room_lights_of(id: String) -> Node3D:
	var env := scene_root.get_node("Environment")
	if env.has_node("Rooms/" + id):
		return env.get_node("Rooms/" + id)
	return _room_lights(id)


func _spot_down(id: String, at: Vector3, color: Color, energy: float, angle: float) -> void:
	var l := SpotLight3D.new()
	_add(_room_lights_of(id), l, "MoonShaft")
	l.position = at
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.light_color = color
	l.light_energy = energy
	l.spot_range = at.y + 4.0
	l.spot_angle = angle
	l.spot_attenuation = 0.6
	l.shadow_enabled = false


func _shaft(at: Vector3, height: float, width: float, color: Color, intensity: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var mat := ShaderMaterial.new()
	mat.shader = ENV_SHAFT
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("near_fade", 8.0)
	quad.material = mat
	var mi := MeshInstance3D.new()
	var g := _group("LightShafts")
	_add(g, mi, "Shaft_%d" % g.get_child_count())
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at + Vector3(0, height * 0.5, 0)
	mi.rotation = Vector3(-0.25, rng.randf_range(-0.2, 0.2), deg_to_rad(-14))


func _roof(rect: Rect2, y: float, holes: Array) -> void:
	# shadow-only roof over a covered room: the moon only reaches the floor through the holes
	# (Rect2 in floor space; shifted along the moon so the lit patch lands where it is drawn)
	var dir := (
		Basis.from_euler(Vector3(deg_to_rad(MOON_PITCH), deg_to_rad(MOON_YAW), 0)) * Vector3.FORWARD
	)
	var shift := Vector2(dir.x, dir.z) * (y / -dir.y)
	var parts := [rect.grow(2.0)]
	for hole: Rect2 in holes:
		var hr := Rect2(hole.position - shift, hole.size)
		var next := []
		for p: Rect2 in parts:
			if not p.intersects(hr):
				next.append(p)
				continue
			var cut := p.intersection(hr)
			# split p around cut: north, south, west, east strips
			next.append(Rect2(p.position, Vector2(p.size.x, cut.position.y - p.position.y)))
			next.append(
				Rect2(Vector2(p.position.x, cut.end.y), Vector2(p.size.x, p.end.y - cut.end.y))
			)
			next.append(
				Rect2(
					Vector2(p.position.x, cut.position.y),
					Vector2(cut.position.x - p.position.x, cut.size.y)
				)
			)
			next.append(
				Rect2(Vector2(cut.end.x, cut.position.y), Vector2(p.end.x - cut.end.x, cut.size.y))
			)
		parts = next.filter(func(q: Rect2) -> bool: return q.size.x > 0.05 and q.size.y > 0.05)
	var g := _group("Roofs")
	for p: Rect2 in parts:
		var mi := MeshInstance3D.new()
		_add(g, mi, "Roof_%d" % g.get_child_count())
		var bm := BoxMesh.new()
		bm.size = Vector3(p.size.x, 0.3, p.size.y)
		mi.mesh = bm
		mi.position = Vector3(p.get_center().x, y, p.get_center().y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


func _room_rect(id: String) -> Rect2:
	var r: Dictionary = CLOISTER_ROOMS[id]
	return Rect2(r["centre"] - r["size"] * 0.5, r["size"])


func _dress_vestibule() -> void:
	# recall of the enemy barrier: sentinel cut out against a moon shaft through the fallen roof
	var c: Vector2 = CLOISTER_ROOMS["vestibule"]["centre"]
	_room_area("vestibule", 1)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_place("brazier", c + s * 12.6, rng.randf() * TAU)  # cold braziers
		_put_at("pillar", Vector3(c.x + s.x * 17.4, -0.05, c.y + s.y * 17.4), 0.0)
	for p: Vector2 in [Vector2(-14, -9), Vector2(13, 6), Vector2(-6, 15.5), Vector2(15.5, -14)]:
		_put_at("rubble", Vector3(p.x, -0.05, p.y), rng.randf() * TAU)
	_roof(_room_rect("vestibule"), 10.0, [Rect2(c - Vector2(5, 5), Vector2(10, 10))])
	_spot_down("vestibule", Vector3(c.x, 12.0, c.y), MOON, 1.4, 22.0)
	_shaft(Vector3(c.x - 1.0, 0.0, c.y), 11.0, 6.0, MOON, 0.16)
	# the postern stair (3 m up to the Ruins) and its head
	_put_at("stairs", Vector3(0, -0.02, 31.0), 0.0)
	_cap(Vector2(0, 38.4), 0.0)
	_omni("vestibule", "PosternLamp", Vector3(0, 4.2, 35.5), WARM, 0.9, 6.0)
	_gate("vestibule", Vector2(0, -18.4), 0.0, "vestibule", "encounter.cloister_vestibule")
	# bell-ringer's stair (shortcut to the campfire), closed until Morvaine is beaten
	_cap(Vector2(-23.9, 0), PI * 0.5)
	_put_at("stairs", Vector3(-22.4, -0.02, 0), -PI * 0.5, Vector3(0.9, 0.6, 0.45))
	_gate("shortcut_vestibule", Vector2(-18.4, 0), PI * 0.5, "vestibule", "encounter.cloister_boss")


func _dress_gallery() -> void:
	# interruption under pressure: three mute bells in the axis, moon rays from the east windows
	var c: Vector2 = CLOISTER_ROOMS["gallery"]["centre"]
	_room_area("gallery", 2)
	for k in 8:
		var z := c.y - 19.0 + k * 5.4
		for sx: float in [-1.0, 1.0]:
			if sx > 0 and absf(z + 66.0) < 3.5:
				continue  # keep the east door clear
			_place("pillar", Vector2(c.x + sx * 17.6, z), 0.0)
	var slots := []
	for k in 3:
		var z := c.y - 12.0 + k * 12.0
		_put_at("bell", Vector3(c.x, 3.9, z), rng.randf_range(-0.2, 0.2))
		slots.append(Rect2(Vector2(c.x - 8, z - 1.6), Vector2(16, 3.2)))
		_shaft(Vector3(c.x + 9.0, 0.0, z), 12.0, 3.2, MOON, 0.12)
	_roof(_room_rect("gallery"), 9.0, slots)
	# the north door is walled up: a corridor to nowhere
	var n := c + Vector2(0, -22.4)
	_put_at("wall_broken", Vector3(n.x, -0.05, n.y - 0.1), 0.0)
	_put_at("rubble", Vector3(n.x + 1.0, -0.05, n.y + 1.4), 0.3)
	_box_collider(Vector3(n.x, 2.0, n.y), Vector3(4.2, 6.0, WALL_T), 0.0)
	_gate("gallery", Vector2(18.4, -66), PI * 0.5, "gallery", "encounter.cloister_gallery")


func _dress_fountain() -> void:
	# rest: pale glowing water, a candle in a niche
	var c: Vector2 = CLOISTER_ROOMS["fountain"]["centre"]
	_room_area("fountain", 3)
	_place("fountain", c, 0.0)
	var water := MeshInstance3D.new()
	_add(_group("Water"), water, "FountainWater")
	var disc := CylinderMesh.new()
	disc.top_radius = 1.45
	disc.bottom_radius = 1.45
	disc.height = 0.04
	disc.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.72, 0.8, 0.92)
	disc.material = mat
	water.mesh = disc
	water.position = Vector3(c.x, 0.5, c.y)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_omni("fountain", "Water", Vector3(c.x, 1.6, c.y), Color("#dfe8ff"), 0.6, 5.5)
	var niche := c + Vector2(5.6, -5.6)
	_place("brazier", niche, 0.4, 0.55)
	_omni("fountain", "Candle", Vector3(niche.x, 1.1, niche.y), WARM, 0.9, 5.0)
	_roof(_room_rect("fountain"), 7.0, [])
	for s: Vector2 in [Vector2(-1, 1), Vector2(1, 1)]:
		_put_at(
			"pillar", Vector3(c.x + s.x * 6.4, -0.05, c.y + s.y * 6.4), 0.0, Vector3(0.8, 0.8, 0.8)
		)


func _dress_courtyard() -> void:
	# combine: open sky, full moon, arcades beyond the arena disc, the stopped bell tower to the north
	var c: Vector2 = CLOISTER_ROOMS["courtyard"]["centre"]
	_room_area("courtyard", 4)
	var inset := 17.65
	for side in 4:
		var yaw := side * PI * 0.5
		var along := Vector2(cos(yaw), -sin(yaw))
		var normal := Vector2(-along.y, along.x)
		for k in 5:
			var t := -14.4 + k * 7.2  # the middle arch frames the door of the side
			var p := c + normal * inset + along * t
			_put_at("arch", Vector3(p.x, -0.05, p.y), yaw, Vector3(1.0, 0.8, 0.9))
			for s: float in [-1.0, 1.0]:
				var q := p + along * s * 2.4
				var cyl := CollisionShape3D.new()
				var shape := CylinderShape3D.new()
				shape.radius = 0.45
				shape.height = 4.0
				cyl.shape = shape
				cyl.position = Vector3(q.x, 2.0, q.y)
				_add(obstacles, cyl, "arcade_%d" % obstacles.get_child_count())
	for k in 2600:
		var p := c + Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15))
		var s: Color = _cloister_splat(p.x, p.y)
		if s.r > 0.25:
			continue
		var cell := CARD_SHORT if rng.randf() < 0.6 else CARD_GREEN
		if rng.randf() < 0.05:
			cell = CARD_DAISY
		_card(p, cell, rng.randf_range(0.4, 0.65), 1.0, -0.2)
	# the bell tower over the north arcades, its dial stopped at three o'clock: the boss landmark
	var t := c + Vector2(0, -30)
	for level in 4:
		for side in 4:
			var yaw := side * PI * 0.5
			var o := Vector2(cos(yaw + PI * 0.5), -sin(yaw + PI * 0.5)) * 2.4
			_put_at(
				"wall" if level < 3 else "wall_broken",
				Vector3(t.x + o.x, level * 4.4 - 0.05, t.y + o.y),
				yaw,
				Vector3(1.2, 1.0, 1.0 + 0.015 * side)
			)
	# the floor dial piece stood up on the south face, 2.9 m across
	var face := Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * 0.12)
	_instances.get_or_add("dial", []).append(
		[Transform3D(face, Vector3(t.x, 14.0, t.y + 2.95)), Color(tint_bias, 1.0, 0.5, 0.0)]
	)
	_gate("courtyard", Vector2(9.6, -104), PI * 0.5, "courtyard", "encounter.cloister_courtyard")


func _dress_kennel() -> void:
	# elite: the darkest room, two torches at the kennel grilles, straw
	var c: Vector2 = CLOISTER_ROOMS["kennel"]["centre"]
	_room_area("kennel", 5)
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			var z := c.y - 5.0 + k * 10.0
			_put_at("grille", Vector3(c.x + sx * 17.75, -0.05, z), PI * 0.5)
		var torch := c + Vector2(sx * 16.9, 0)
		_put_at("torch_post", Vector3(torch.x + sx * 0.8, -0.05, torch.y), 0.0)
		_omni(
			"kennel",
			"Torch_%s" % ("w" if sx < 0 else "e"),
			Vector3(torch.x, 2.3, torch.y),
			WARM,
			1.0,
			8.0
		)
	for k in 500:
		var p := c + Vector2(rng.randf_range(-17, 17), rng.randf_range(-17, 17))
		if absf(p.x - c.x) < 9.0 and rng.randf() < 0.6:
			continue
		_card(p, CARD_DRY, rng.randf_range(0.4, 0.7), 0.6, 0.2)
	for p: Vector2 in [Vector2(-34, -88), Vector2(-2.5, -120), Vector2(-33.5, -119)]:
		_put_at("rubble", Vector3(p.x, -0.05, p.y), rng.randf() * TAU)
	_roof(_room_rect("kennel"), 9.0, [])
	_gate("kennel", Vector2(-18, -122.4), 0.0, "kennel", "encounter.cloister_alpha")


func _dress_campfire() -> void:
	# checkpoint: an orange fire, radius 6 m, the safety signal before the boss
	var c: Vector2 = CLOISTER_ROOMS["campfire"]["centre"]
	_room_area("campfire", 6)
	_place("campfire", c, 0.3)
	_omni("campfire", "Fire", Vector3(c.x, 1.0, c.y), Color("#ff9a4a"), 1.5, 6.5)
	_place("barrels", c + Vector2(4.4, -5.2), 0.5, 0.8)
	_put_at("rubble", Vector3(c.x - 4.6, -0.05, c.y + 5.0), 1.0, Vector3(0.6, 0.6, 0.6))
	_roof(_room_rect("campfire"), 6.5, [])
	# the stair up to the dial (12 m, +6 m)
	_put_at("stairs", Vector3(c.x, -0.02, -147.0), PI)
	_put_at("stairs", Vector3(c.x, 2.98, -153.0), PI)
	# bell-ringer's stair arrival, closed until Morvaine is beaten
	_cap(Vector2(-29.9, -137), PI * 0.5)
	_put_at("stairs", Vector3(-28.4, -0.02, -137), -PI * 0.5, Vector3(0.9, 0.6, 0.45))
	_gate(
		"shortcut_campfire", Vector2(-24.4, -137), PI * 0.5, "campfire", "encounter.cloister_boss"
	)


func _dress_dial() -> void:
	# boss: 24 m floor dial, the bell 20 m up in an open shaft, four lantern alcoves, ember threads
	var c: Vector2 = CLOISTER_ROOMS["dial"]["centre"]
	_room_area("dial", 7)
	_put_at("dial", Vector3(c.x, DIAL_Y + 0.01, c.y), 0.0)
	_put_at("bell", Vector3(c.x, DIAL_Y + 20.0, c.y), 0.3, Vector3(1.6, 1.6, 1.6))
	for k in 8:
		var a := (k + 0.5) * TAU / 8.0 + TAU / 32.0
		var p := c + Vector2(cos(a), -sin(a)) * 18.7
		_place("pillar", p, 0.0)
	_spot_down("dial", Vector3(c.x, DIAL_Y + 16.0, c.y), MOON, 1.3, 24.0)
	_shaft(Vector3(c.x, DIAL_Y, c.y), 18.0, 7.0, MOON, 0.14)
	var after := _omni(
		"dial", "AfterLight", Vector3(c.x, DIAL_Y + 8.0, c.y), Color("#ffd8a0"), 3.0, 22.0
	)
	after.visible = false
	# ember threads between Morvaine and her lanterns (GDD 9.3): red glows along four lines
	var embers := []
	for k in 4:
		var a := (k * 8 + 3 + 0.5) * TAU / 32.0
		var tip := c + Vector2(cos(a), -sin(a)) * 21.5
		_omni(
			"dial",
			"Alcove_%s" % ["a", "b", "c", "d"][k],
			Vector3(tip.x, DIAL_Y + 1.8, tip.y),
			WARM,
			0.6,
			4.0
		)
		for j in range(3, 20):
			var q := c.lerp(tip, j / 20.0)
			embers.append([Vector3(q.x, DIAL_Y + 0.8 + j * 0.06, q.y), 0.45])
		embers.append([Vector3(tip.x, DIAL_Y + 1.8, tip.y), 0.7])
	_glow("Embers", embers, Color("#ff5a3a"), 0.6)
	var ring := Rect2(c - Vector2(24, 24), Vector2(48, 48))
	_roof(ring, DIAL_Y + 12.0, [Rect2(c - Vector2(6, 6), Vector2(12, 12))])
	# outer stair after the boss, down the cliff to the Ruins
	_put_at("stairs", Vector3(c.x, DIAL_Y - 3.02, -203.0), 0.0)
	_cap(Vector2(c.x, -208.4), 0.0)
	_gate("dial", Vector2(c.x, -196.3), 0.0, "dial", "encounter.cloister_boss")


func _floor_debris(id: String) -> void:
	# fallen pillar drums and flat rubble on the rim of a combat room (no collider: the arena disc
	# stays free, docs/content/dungeon.md 1)
	var r: Dictionary = CLOISTER_ROOMS[id]
	var c: Vector2 = r["centre"]
	var y := DIAL_Y if id == "dial" else 0.0
	for k in 7:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(12.5, 15.5)
		if k < 2:
			var lying := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5)
			var xf := Transform3D(
				lying.scaled(Vector3(0.8, 0.45, 0.8)), Vector3(p.x, y + 0.35, p.y)
			)
			_instances.get_or_add("pillar", []).append([xf, Color(tint_bias, 0.95, 0.5, 0.0)])
		else:
			_put_at("rubble", Vector3(p.x, y - 0.1, p.y), rng.randf() * TAU, Vector3(1, 0.7, 1))


func _floor_tufts() -> void:
	# grass and dry tufts in the cracks of the paving, thicker along the walls; a few flagstones
	# lifted by roots (rubble) in the corners
	for id: String in CLOISTER_ROOMS:
		var r: Dictionary = CLOISTER_ROOMS[id]
		var c: Vector2 = r["centre"]
		var half: Vector2 = r["size"] * 0.5 - Vector2(0.6, 0.6)
		var count := int(r["size"].x * r["size"].y * 0.12)
		for k in count:
			var p := c + Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
			if id == "dial" and p.distance_to(c) > DIAL_R - 0.6:
				continue
			if id == "dial" and p.distance_to(c) < 12.2:
				continue  # keep the floor dial readable
			var edge := minf(half.x - absf(p.x - c.x), half.y - absf(p.y - c.y))
			if id == "dial":
				edge = DIAL_R - 0.6 - p.distance_to(c)
			if rng.randf() > 0.3 + 0.7 * (1.0 - smoothstep(0.5, 4.0, edge)):
				continue
			var cell := CARD_DRY if rng.randf() < 0.5 else CARD_SHORT
			if rng.randf() < 0.15:
				cell = CARD_FERN
			_card(p, cell, rng.randf_range(0.35, 0.6), 1.0, -0.25)


func _glow(glow_name: String, lamps: Array, color: Color, intensity: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 1.7)
	var mat := ShaderMaterial.new()
	mat.shader = ENV_GLOW
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("intensity", intensity)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = lamps.size()
	for i in lamps.size():
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * lamps[i][1]), lamps[i][0])
		)
	var mmi := MultiMeshInstance3D.new()
	_add(_group("Glow"), mmi, glow_name)
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _cloister_outside() -> void:
	# the hilltop around the ruined cloister: night birches and rocks between the buildings
	for i in 3000:
		var p := Vector2(rng.randf_range(-54, 62), rng.randf_range(-224, 48))
		if _on_floor(p, 5.0) or not _free_at(p, 3.0) or rng.randf() < 0.6:
			continue
		var kit := "birch_a_lo" if rng.randf() < 0.5 else "birch_b_lo"
		if rng.randf() < 0.2:
			kit = "rock_a"
		_place(kit, p, rng.randf() * TAU, rng.randf_range(0.7, 1.05), false)
	for i in 6000:
		var p := Vector2(rng.randf_range(-54, 62), rng.randf_range(-224, 48))
		if _on_floor(p, 1.2):
			continue
		var cell := CARD_DRY if rng.randf() < 0.5 else CARD_GREEN
		_card(p, cell, rng.randf_range(0.5, 0.8), 1.0, -0.3)
	# warm lights: the campfire glow and the alcove lanterns are in their rooms; halos for the
	# postern lamp, the candle, the torches and the fire
	var halos := [
		[Vector3(0, 4.2, 35.5), 1.4],
		[Vector3(35.6, 1.1, -71.6), 0.8],
		[Vector3(-34.9, 2.15, -104), 1.0],
		[Vector3(-1.1, 2.15, -104), 1.0],
		[Vector3(-18, 0.9, -137), 2.2],
	]
	_glow("WarmHalos", halos, Color(1.0, 0.74, 0.4), 0.55)


func _night_environment() -> void:
	# DESIGN.md night: cold moon #bcd0ff, ambient #1a2433, warm point sources (dungeon.md 2.6)
	var holder := Node3D.new()
	_add(scene_root, holder, "Environment")
	var we := WorldEnvironment.new()
	_add(holder, we, "WorldEnvironment")
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#0c1322")
	sky_mat.sky_horizon_color = Color("#2a3550")
	sky_mat.ground_horizon_color = Color("#2a3550")
	sky_mat.ground_bottom_color = Color("#0b0f18")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = NIGHT_AMBIENT.lightened(0.15)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color("#1e2a40")
	env.fog_density = 0.008
	env.fog_sky_affect = 0.0
	we.environment = env
	var moon := DirectionalLight3D.new()
	_add(holder, moon, "Sun")
	moon.rotation_degrees = Vector3(MOON_PITCH, MOON_YAW, 0)
	moon.light_color = MOON
	moon.light_energy = 0.4
	moon.shadow_enabled = true
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.2
	moon.shadow_blur = 0.6
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 36.0
	moon.light_bake_mode = Light3D.BAKE_STATIC
	moon.set_meta("night", true)


func _cloister_markers() -> void:
	# names from docs/content/dungeon.md 2.3 / 2.4
	_marker("Spawns", "default", Vector3(0, 0, 24), Vector3.FORWARD)
	_marker("Spawns", "from_watch_ruins", Vector3(0, 0, 24), Vector3.FORWARD)
	_marker("Spawns", "checkpoint_campfire", Vector3(-18, 0, -132.5), Vector3.FORWARD)
	_marker("Spawns", "shortcut_vestibule", Vector3(-14, 0, 0), Vector3.RIGHT)
	_marker("Spawns", "shortcut_campfire", Vector3(-21, 0, -137), Vector3.RIGHT)
	_exit(
		"to_watch_ruins",
		Vector3(0, 0, 35.5),
		Vector3(4, 3, 2),
		"location.watch_ruins",
		"from_cloister"
	)
	_exit(
		"to_watch_ruins_back",
		Vector3(-18, 0, -205.5),
		Vector3(4, 3, 2),
		"location.watch_ruins",
		"from_cloister"
	)
	(scene_root.get_node("Exits/to_watch_ruins_back") as Node3D).set_meta(
		"requires_cleared", "encounter.cloister_boss"
	)
	# the bell-ringer's stair: the post-boss shortcut, gated by state (requires_cleared), not here
	for s in [
		["shortcut_to_campfire", Vector3(-22.3, 0, 0), "shortcut_campfire"],
		["shortcut_to_vestibule", Vector3(-28.3, 0, -137), "shortcut_vestibule"],
	]:
		_exit(s[0], s[1], Vector3(2, 3, 3.6), "dungeon.silent_dial_cloister", s[2])
		var area := scene_root.get_node("Exits/" + s[0]) as Node3D
		area.set_meta("shortcut", true)
		area.set_meta("requires_cleared", "encounter.cloister_boss")
	var rooms := {
		"room1_encounter": ["vestibule", Vector3(0, 0, 0)],
		"room2_encounter": ["gallery", Vector3(0, 0, -50)],
		"room3_fountain": ["fountain", Vector3(30, 0, -66)],
		"room4_encounter": ["courtyard", Vector3(30, 0, -104)],
		"room4_chest": ["courtyard", Vector3(48.6, 0, -86.6)],
		"room5_encounter": ["kennel", Vector3(-18, 0, -104)],
		"room6_campfire": ["campfire", Vector3(-18, 0, -137)],
		"room7_encounter": ["dial", Vector3(-18, 0, -176)],
	}
	for id: String in rooms:
		_marker("Anchors", id, rooms[id][1], Vector3.BACK)
		var m := scene_root.get_node("Anchors/" + id) as Node3D
		m.set_meta("room", rooms[id][0])
		if id.ends_with("_encounter"):
			m.set_meta("arena_center", "anchor")
			m.set_meta("arena_radius", 16.0)
	var fountain := scene_root.get_node("Anchors/room3_fountain") as Node3D
	fountain.set_meta("interact", "fountain")
	fountain.set_meta("heal_pct", 0.3)
	fountain.set_meta("once_per_run", true)
	var fire := scene_root.get_node("Anchors/room6_campfire") as Node3D
	fire.set_meta("interact", "campfire")
	fire.set_meta("heal_pct", 1.0)
	fire.set_meta("checkpoint", "campfire")
	fire.set_meta("spawn", "checkpoint_campfire")
	var boss := scene_root.get_node("Anchors/room7_encounter") as Node3D
	boss.set_meta("trigger_radius", 12.0)
	boss.set_meta("intro_dialogue", "dialogue.morvaine_intro")
	var c: Vector2 = CLOISTER_ROOMS["dial"]["centre"]
	for k in 4:
		var a := (k * 8 + 3 + 0.5) * TAU / 32.0
		var p := c + Vector2(cos(a), -sin(a)) * 21.5
		_marker(
			"Anchors",
			"room7_lantern_%s" % ["a", "b", "c", "d"][k],
			Vector3(p.x, 0, p.y),
			Vector3(-cos(a), 0, sin(a))
		)
		(
			(scene_root.get_node("Anchors/room7_lantern_%s" % ["a", "b", "c", "d"][k]) as Node3D)
			. set_meta("room", "dial")
		)


# --- terrain over any rectangle ------------------------------------------------------------------


func _terrain_rect(label: String, rect: Rect2i, px_per_m: int) -> void:
	# same as _terrain (location_builder.gd) on a rectangle that is not centred on the origin
	var dir := "%sterrain/%s/" % [ENV, label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var w := rect.size.x * px_per_m
	var hpx := rect.size.y * px_per_m
	var img := Image.create(w, hpx, false, Image.FORMAT_RGBA8)
	for j in hpx:
		for i in w:
			var x := rect.position.x + (i + 0.5) / px_per_m
			var z := rect.position.y + (j + 0.5) / px_per_m
			img.set_pixel(i, j, _splat_fn.call(x, z))
	var splat := ImageTexture.create_from_image(img)
	ResourceSaver.save(splat, dir + "splat.res", ResourceSaver.FLAG_COMPRESS)
	img.save_png(ProjectSettings.globalize_path("res://art/source/env/%s_splat.png" % label))
	var mat := ShaderMaterial.new()
	mat.shader = ENV_TERRAIN
	mat.set_shader_parameter("splat_tex", load(dir + "splat.res"))
	for t in ["grass", "dirt", "cobble", "forest"]:
		mat.set_shader_parameter(t + "_tex", load("%stextures/ground_%s.jpg" % [ENV, t]))
	mat.set_shader_parameter(
		"splat_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	)
	mat.set_shader_parameter("shadow_tint", Color("#4a5a80"))
	mat.set_shader_parameter("grass_tint", Color(0.7, 0.8, 0.72))
	ResourceSaver.save(mat, dir + "ground.tres")
	mat = load(dir + "ground.tres")
	var nx := rect.size.x
	var nz := rect.size.y
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			hs[j * (nx + 1) + i] = _height(rect.position.x + i, rect.position.y + j)
	var ground := _group("Ground")
	var chunk := 30
	for cj in range(0, nz, chunk):
		for ci in range(0, nx, chunk):
			var mesh := _rect_chunk(hs, rect, ci, cj, mini(chunk, nx - ci), mini(chunk, nz - cj))
			mesh.surface_set_material(0, mat)
			var path := "%sground_%d_%d.res" % [dir, ci / chunk, cj / chunk]
			ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
			var mi := MeshInstance3D.new()
			_add(ground, mi, "Ground_%d_%d" % [ci / chunk, cj / chunk])
			mi.mesh = load(path)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hm := HeightMapShape3D.new()
	hm.map_width = nx + 1
	hm.map_depth = nz + 1
	hm.map_data = hs
	var shape := CollisionShape3D.new()
	shape.shape = hm
	shape.position = Vector3(rect.position.x + nx * 0.5, 0, rect.position.y + nz * 0.5)
	_add(scene_root.get_node("Walkable"), shape, "Ground")


func _rect_chunk(
	hs: PackedFloat32Array, rect: Rect2i, ci: int, cj: int, cw: int, ch: int
) -> ArrayMesh:
	var nx := rect.size.x
	var nz := rect.size.y
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in ch + 1:
		for i in cw + 1:
			var gi := ci + i
			var gj := cj + j
			verts.append(
				Vector3(rect.position.x + gi, hs[gj * (nx + 1) + gi], rect.position.y + gj)
			)
			var hl := hs[gj * (nx + 1) + maxi(gi - 1, 0)]
			var hr := hs[gj * (nx + 1) + mini(gi + 1, nx)]
			var hd := hs[maxi(gj - 1, 0) * (nx + 1) + gi]
			var hu := hs[mini(gj + 1, nz) * (nx + 1) + gi]
			normals.append(Vector3(hl - hr, 2.0, hd - hu).normalized())
	for j in ch:
		for i in cw:
			var a := j * (cw + 1) + i
			var b := a + 1
			var c := a + cw + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _save_to(dir: String, file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	assert(err == OK)
	ResourceSaver.save(packed, dir + file_name)
	print("saved ", dir + file_name, " nodes=", _count(scene_root))
	scene_root.free()
