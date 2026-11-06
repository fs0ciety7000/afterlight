extends "res://game/world/prototype/mire_layout.gd"
## Watch Ruins layout for the offline builder (build_locations.gd extends this chain).
## Follows docs/content/dungeon.md §3: 80 x 80 m hill climbing to the north, the collapsed tower
## in the north-east (landmark, discovery_01 on top of its stair), the postern of the Silent Dial
## Cloister under it (dungeon_gate), the guard room ruin in the west (discovery_02), five packs.

const RUINS_TOWER := Vector2(36.0, -30.0)
const RUINS_GATE := Vector2(26.0, -37.0)
## Top of the tower stair: discovery_01 (dungeon.md §3, (30, 0, -26)).
const RUINS_LOOKOUT := Vector2(30.0, -26.0)
const RUINS_LOOKOUT_H := 3.0


func _ruins_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	# the hill climbs gently from the mire road (south) to the cliff of the cloister (north)
	var h := 2.4 * smoothstep(30.0, -34.0, z) + noise.get_noise_2d(x, z) * 0.35
	# flatter, worn ground on the paths and around the packs
	var flat := 1.0 - smoothstep(0.0, 3.0, _path_dist(p))
	h = lerpf(h, 2.4 * smoothstep(30.0, -34.0, z), flat * 0.8)
	# the tower stair: a stone ramp along x = 30 up to the lookout, on a rubble mound
	var stair := clampf((-20.0 - z) / 6.0, 0.0, 1.0) * RUINS_LOOKOUT_H
	var mound := 1.0 - smoothstep(2.4, 5.0, p.distance_to(RUINS_LOOKOUT + Vector2(0, -1)))
	var on_stair := 1.0 - smoothstep(2.2, 3.0, absf(x - 30.0))
	if z <= -20.0 and z >= -28.0:
		h = maxf(h, lerpf(h, stair + 2.4 * smoothstep(30.0, -34.0, -20.0), on_stair))
	h = maxf(h, lerpf(h, RUINS_LOOKOUT_H + 2.4 * smoothstep(30.0, -34.0, -20.0), mound))
	# cliff of the cloister along the north edge, behind the postern
	var cliff := smoothstep(-38.6, -41.5, z) * (1.0 - smoothstep(30.0, 38.0, absf(x - 4.0)))
	h += cliff * 9.0
	var r := maxf(absf(x), absf(z))
	var rise := smoothstep(40.0, 66.0, r)
	h += rise * rise * (6.0 + 4.0 * noise2.get_noise_2d(x, z))
	return h


func _ruins_splat(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var dirt := 1.0 - smoothstep(-0.4, 0.9, _path_dist(p))
	# old paving around the tower, the postern and the guard room
	var cob := 0.0
	for c in [[RUINS_TOWER, 8.0], [RUINS_GATE + Vector2(0, 2), 3.5], [Vector2(-24, -10), 6.0]]:
		cob = maxf(cob, 1.0 - smoothstep(c[1] - 1.5, c[1], p.distance_to(c[0])))
	cob *= 0.6 + 0.4 * noise.get_noise_2d(x * 3.0, z * 3.0)
	var forest := (
		smoothstep(30.0, 44.0, p.length()) * (0.5 + 0.5 * noise2.get_noise_2d(x * 3.0, z * 3.0))
	)
	return Color(dirt, clampf(cob, 0.0, 1.0), forest, 1.0)


func _build_ruins() -> void:
	_begin("WatchRuins")
	rng.seed = 7707
	_height_fn = _ruins_height
	_splat_fn = _ruins_splat
	tint_bias = -0.08
	grass_tint = Color(0.84, 0.9, 0.72)
	clearings = [
		[Vector2(0, 36), 4.0],  # arrival from the mire
		[Vector2(0, 21), 8.5],  # encounter_01, the party stands on the anchor's +z side
		[Vector2(-22, 7), 8.5],  # encounter_02
		[Vector2(14, 1), 8.5],  # encounter_03
		[Vector2(-14, -21), 8.5],  # encounter_04
		[Vector2(10, -23), 8.5],  # encounter_05, the tower guardians
		[Vector2(24, -31), 4.5],  # return from the cloister, in front of the postern
		[Vector2(-24, -10), 5.5],  # guard room
		[Vector2(-32, -32), 3.0],  # chest_01
	]
	var main := [
		Vector2(0, 52),
		Vector2(0, 39),
		Vector2(1, 30),
		Vector2(0, 18),
		Vector2(5, 8),
		Vector2(13, -2),
		Vector2(12, -14),
		Vector2(10, -26),
		Vector2(18, -31),
		Vector2(24, -32),
		Vector2(26, -36)
	]
	paths.append([PackedVector2Array(main), 1.2])
	for spur in [
		[[Vector2(0, 18), Vector2(-12, 8), Vector2(-22, 4), Vector2(-24, -10)], 0.9],  # guard room
		[[Vector2(-24, -10), Vector2(-17, -20), Vector2(-14, -24)], 0.8],  # encounter_04
		[[Vector2(-17, -20), Vector2(-26, -28), Vector2(-32, -32)], 0.6],  # chest_01
		[[Vector2(18, -31), Vector2(24, -24), Vector2(30, -20)], 0.8],  # foot of the tower stair
	]:
		paths.append([PackedVector2Array(spur[0]), spur[1]])
	_terrain("watch_ruins", 70, 42, 448)
	occupied.append([RUINS_LOOKOUT + Vector2(0, 2), 4.5])
	# the collapsed watchtower and its stair up to the lookout (discovery_01)
	_place("tower_ruin", RUINS_TOWER, _face(RUINS_TOWER, Vector2(10, -10)))
	_put_at("stairs", Vector3(30, _height(30, -20) - 0.05, -23), PI)
	# the watch yard around the tower: broken walls on its west and south sides
	for w in [
		[Vector2(34, -20.5), 0.05],
		[Vector2(38.5, -21.0), -0.05],
		[Vector2(24.5, -25.0), PI * 0.5],
	]:
		_ruin_wall("wall_broken", w[0], w[1])
	for p: Vector2 in [Vector2(28, -21), Vector2(32.6, -24), Vector2(27.4, -27)]:
		_place("rubble", p, rng.randf() * TAU, rng.randf_range(0.8, 1.1), false)
	# cliff face with the postern: a broken curtain wall along the cliff foot, arch + grille
	for k in range(-3, 4):
		if k == 0:
			continue
		var at := RUINS_GATE + Vector2(k * 4.0, -0.6 - absf(k) * 0.15)
		_place("wall" if absf(k) < 2 else "wall_broken", at, rng.randf_range(-0.04, 0.04), 1.0)
	_put_at(
		"arch",
		Vector3(RUINS_GATE.x, _height(RUINS_GATE.x, RUINS_GATE.y) - 0.1, RUINS_GATE.y - 0.4),
		0
	)
	_put_at(
		"grille",
		Vector3(RUINS_GATE.x, _height(RUINS_GATE.x, RUINS_GATE.y) - 0.1, RUINS_GATE.y - 0.7),
		0
	)
	_box_collider(Vector3(RUINS_GATE.x, 2, RUINS_GATE.y - 1.2), Vector3(28, 6, 1.4), 0.0)
	for at in [RUINS_GATE + Vector2(-3.4, 1.2), RUINS_GATE + Vector2(3.4, 1.2)]:
		_place("brazier", at, 0.0)
	# guard room ruin: four broken walls with a door to the south-east, the lectern inside
	var gr := Vector2(-24, -10)
	for w in [
		[gr + Vector2(0, -4.4), 0.0, 1.0],
		[gr + Vector2(-4.4, 0), PI * 0.5, 1.0],
		[gr + Vector2(4.4, -1.6), PI * 0.5, 0.65],
		[gr + Vector2(-2.0, 4.4), 0.0, 0.75],
	]:
		_ruin_wall("wall_broken", w[0], w[1] + rng.randf_range(-0.03, 0.03))
	_place("lectern", gr + Vector2(0.6, -2.4), 0.2)
	_place("rubble", gr + Vector2(3.6, 3.4), 0.7)
	_place("barrels", gr + Vector2(-3.0, -3.2), 0.4, 0.8)
	# the old outer wall of the watch, in pieces across the hill
	for seg in [
		[Vector2(-38, 14), Vector2(-30, 22)],
		[Vector2(-38, -6), Vector2(-38, 2)],
		[Vector2(-20, 30), Vector2(-12, 34)],
		[Vector2(20, 22), Vector2(30, 14)],
		[Vector2(34, 6), Vector2(36, -6)],
		[Vector2(-6, -36), Vector2(4, -37)],
	]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var n := maxi(1, roundi(a.distance_to(b) / 4.0))
		for k in n:
			if rng.randf() < 0.25:
				continue
			var c := a.lerp(b, (k + 0.5) / n)
			var yaw := atan2(-(b - a).y, (b - a).x)
			_ruin_wall("wall_broken" if rng.randf() < 0.75 else "wall", c, yaw)
	# the ruined gate of the watch on the road (encounter_01 "Porte des ruines")
	_place("pillar", Vector2(-3.2, 29.5), 0.1)
	_place("pillar", Vector2(3.2, 29.5), -0.1)
	_place("rubble", Vector2(5.2, 30.5), 1.2)
	_place("lantern", Vector2(2.6, 36.5), PI * 0.5)
	_place("lantern", Vector2(-2.6, 36.5), PI * 0.5)
	_place("rubble", Vector2(-31, -33.6), 0.4, 0.8)
	_place("barrels", Vector2(-34.2, -30.6), 1.0, 0.8)
	_ruins_vegetation()
	_grass(38.0, 9000, 0.25)
	_flush()
	_backdrop(Vector3(30, 2, -150), 300.0)
	_borders(40.0)
	# late afternoon: the sun lower and warmer than in Aubelin, from the west
	_environment(false, -100.0, -20.0, 0.95, 0.95)
	_ruins_markers()
	_save("watch_ruins.tscn")


func _ruins_vegetation() -> void:
	for c in clearings:
		var centre: Vector2 = c[0]
		for k in 3:
			var a := rng.randf() * TAU
			var p: Vector2 = centre + Vector2(cos(a), sin(a)) * (c[1] + rng.randf_range(0.5, 2.0))
			if _path_dist(p) > 1.6 and _free_at(p, 2.2):
				_place(
					"birch_a" if rng.randf() < 0.5 else "birch_b",
					p,
					rng.randf() * TAU,
					rng.randf_range(0.75, 0.95)
				)
		for k in 3:
			var a := rng.randf() * TAU
			var p: Vector2 = centre + Vector2(cos(a), sin(a)) * (c[1] + rng.randf_range(-0.5, 1.0))
			if _path_dist(p) > 1.0 and _free_at(p, 0.6):
				_place(
					"bush" if k == 0 else ("rock_a" if k == 1 else "rock_b"),
					p,
					rng.randf() * TAU,
					rng.randf_range(0.6, 1.0)
				)
	for i in 900:
		var p := Vector2(rng.randf_range(-38, 38), rng.randf_range(-38, 38))
		if _path_dist(p) < 2.0 or not _free_at(p, 3.2) or rng.randf() < 0.75:
			continue
		if _height(p.x, p.y) > 6.0:
			continue
		_place(
			"birch_a_lo" if rng.randf() < 0.5 else "birch_b_lo",
			p,
			rng.randf() * TAU,
			rng.randf_range(0.65, 0.85)
		)
	for i in 1400:
		var p := Vector2(rng.randf_range(-68, 68), rng.randf_range(-68, 68))
		if maxf(absf(p.x), absf(p.y)) < 40.5 or rng.randf() < 0.3:
			continue
		if _path_dist(p) < 1.6 or not _free_at(p, 2.6):
			continue
		_place(
			"birch_a_lo" if rng.randf() < 0.5 else "birch_b_lo",
			p,
			rng.randf() * TAU,
			rng.randf_range(0.8, 1.15),
			false
		)
	for i in 50:
		var p := Vector2(rng.randf_range(-36, 36), rng.randf_range(-36, 36))
		if _path_dist(p) > 1.0 and _free_at(p, 1.0):
			_place(
				"rock_a" if rng.randf() < 0.5 else "rubble",
				p,
				rng.randf() * TAU,
				rng.randf_range(0.5, 0.9)
			)


func _ruins_markers() -> void:
	_marker("Spawns", "default", Vector3(0, 0, 36), Vector3.FORWARD)
	_marker("Spawns", "from_lantern_mire", Vector3(0, 0, 36), Vector3.FORWARD)
	_marker("Spawns", "from_cloister", Vector3(24, 0, -30), Vector3(-1, 0, 1).normalized())
	_exit(
		"to_lantern_mire",
		Vector3(0, 0, 39.5),
		Vector3(5, 3, 3),
		"location.lantern_mire",
		"from_watch_ruins"
	)
	# the postern: an interactable exit into the dungeon (docs/content/dungeon.md 2.3 "Entrée")
	_exit(
		"to_cloister",
		Vector3(RUINS_GATE.x, 0, RUINS_GATE.y + 0.2),
		Vector3(3.6, 3, 1.4),
		"dungeon.silent_dial_cloister",
		"default"
	)
	var gate_exit := scene_root.get_node("Exits/to_cloister") as Node3D
	gate_exit.set_meta("interact", true)
	gate_exit.set_meta("anchor", "dungeon_gate")
	for a in [
		["encounter_01", Vector3(0, 0, 18)],
		["encounter_02", Vector3(-22, 0, 4)],
		["encounter_03", Vector3(14, 0, -2)],
		["encounter_04", Vector3(-14, 0, -24)],
		["encounter_05", Vector3(10, 0, -26)],
		["dungeon_gate", Vector3(RUINS_GATE.x, 0, RUINS_GATE.y + 1.0)],
		["discovery_01", Vector3(RUINS_LOOKOUT.x, 0, RUINS_LOOKOUT.y)],
		["discovery_02", Vector3(-24, 0, -10)],
		["chest_01", Vector3(-32, 0, -32)],
	]:
		_marker("Anchors", a[0], a[1], Vector3.BACK)
	(scene_root.get_node("Anchors/discovery_01") as Node3D).set_meta("kind", "vista")
	(scene_root.get_node("Anchors/dungeon_gate") as Node3D).set_meta(
		"dungeon", "dungeon.silent_dial_cloister"
	)


# --- shared helpers (ruins and cloister) ------------------------------------------------------


func _put_at(kit_name: String, at: Vector3, yaw: float, scale := Vector3.ONE) -> void:
	# an instance at an explicit height (stairs, gates, kit pieces on ramps), no collider
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	var tint := rng.randf_range(-0.3, 0.3) + tint_bias
	_instances.get_or_add(kit_name, []).append(
		[
			Transform3D(basis, at),
			Color(tint, rng.randf_range(0.93, 1.03) * bright_scale, rng.randf(), 0.0)
		]
	)


func _ruin_wall(kit_name: String, at: Vector2, yaw: float) -> void:
	# a free-standing wall piece on the terrain with its own collision box
	_place(kit_name, at, yaw, 1.0, false)
	var y := _height(at.x, at.y)
	_box_collider(Vector3(at.x, y + 1.5, at.y), Vector3(4.0, 3.0, 0.8), yaw)


func _box_collider(centre: Vector3, size: Vector3, yaw: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(Basis(Vector3.UP, yaw), centre)
	_add(obstacles, shape, "wall_%d" % obstacles.get_child_count())
