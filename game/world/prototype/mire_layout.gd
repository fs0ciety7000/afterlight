extends "res://game/world/prototype/location_builder.gd"
## Lantern Mire layout for the offline builder (build_locations.gd extends this script).
## Follows docs/content/dungeon.md §4: 80 x 80 m bog, zones A (west pontoons, arrival from Aubelin),
## B (central reed bed and the drowned beacon), C (east islets, patrol, flower islet, broken
## pontoon), D (ferryman's hut, north-west), E (north causeway up to the Watch Ruins).

## Still water level of the pools (m) and top of the pontoon decks (level with the paths).
const MIRE_WATER := -0.5
const DECK_Y := 0.05
## Lamp of the lantern post in model space (assets/environment/props/lantern.glb, arm on -X),
## lamp of the beacon (tools/blender/build_mire_props.py).
const LANTERN_LAMP := Vector3(-0.45, 1.85, 0.0)
const BEACON_LAMP := Vector3(0.0, 7.35, 0.0)
const BEACON_AT := Vector2(0.5, 10.5)

## Pontoon sections: [centre (x, z), yaw, walkable]; a section is 2 x 4 m along its local Z.
var _decks: Array = []


func _mire_dry(p: Vector2) -> float:
	# 1 on paths, islets, hummocks and the hills around the bog; 0 in the pools.
	# Shores wobble with noise so no bank follows a path segment or a circle.
	var wobble := noise2.get_noise_2d(p.x * 6.0, p.y * 6.0) * 2.4
	var d := 1.0 - smoothstep(0.4, 2.6, _path_dist(p) + wobble)
	for c in clearings:
		d = maxf(d, 1.0 - smoothstep(c[1] - 1.5, c[1] + 1.5, p.distance_to(c[0]) + wobble))
	d = maxf(d, smoothstep(0.12, 0.3, noise.get_noise_2d(p.x * 1.6, p.y * 1.6)))
	var r := maxf(absf(p.x), absf(p.y)) + noise.get_noise_2d(p.x * 0.7, p.y * 0.7) * 6.0
	return maxf(d, smoothstep(35.0, 40.0, r))


func _mire_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := lerpf(-0.85, 0.05, _mire_dry(p)) + noise2.get_noise_2d(x * 3.0, z * 3.0) * 0.1
	var r := maxf(absf(x), absf(z))
	var rise := smoothstep(40.0, 66.0, r)
	h += rise * rise * (6.0 + 4.0 * noise2.get_noise_2d(x, z))
	return h


func _mire_splat(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var dirt := 1.0 - smoothstep(-0.4, 0.8, _path_dist(p))
	# dark peat and fallen leaves along the water, broken by noise
	var h := _mire_height(x, z)
	var peat := 1.0 - smoothstep(MIRE_WATER + 0.1, MIRE_WATER + 0.6, h)
	peat = clampf(peat + noise.get_noise_2d(x * 4.0, z * 4.0) * 0.5 + 0.15, 0.0, 1.0)
	return Color(dirt, 0.0, peat, 1.0)


func _build_mire() -> void:
	_begin("LanternMire")
	rng.seed = 5150
	_height_fn = _mire_height
	_splat_fn = _mire_splat
	tint_bias = -0.22
	grass_tint = Color(0.8, 0.86, 0.68)
	clearings = [
		[Vector2(-36, 6), 4.0],  # A: arrival from Aubelin
		[Vector2(-22, 6), 8.5],  # encounter_01, the party stands on the anchor's +z side
		[Vector2(-6, 24), 8.5],  # encounter_02
		[Vector2(6, 2), 8.5],  # encounter_03
		[Vector2(-4, -20), 8.5],  # encounter_05
		[Vector2(29, 12), 5.5],  # encounter_04 patrol, north end
		[Vector2(29.5, 1), 5.5],
		[Vector2(30, -9), 5.5],  # patrol, south end
		[Vector2(32, 24), 3.0],  # flower islet (discovery_02)
		[Vector2(-30, -24), 6.0],  # D: ferryman's hut (discovery_01)
		[Vector2(-32.5, 14), 2.5],  # herb_01 islet
		[Vector2(4, -36), 3.0],  # herb_03
	]
	var main_west := [
		Vector2(-48, 6),
		Vector2(-39, 6),
		Vector2(-34, 6),
		Vector2(-27, 5),
		Vector2(-20, 6),
		Vector2(-15.5, 6)
	]
	var main_north := [
		Vector2(-2.5, 5),
		Vector2(4, 1),
		Vector2(5, -6),
		Vector2(1, -14),
		Vector2(-3, -20),
		Vector2(-1, -28),
		Vector2(6, -33),
		Vector2(10, -36),
		Vector2(10, -48)
	]
	paths.append([PackedVector2Array(main_west), 1.1])
	paths.append([PackedVector2Array(main_north), 1.1])
	for spur in [
		[[Vector2(-2.5, 5), Vector2(-5, 13), Vector2(-6, 20)], 0.8],  # encounter_02
		[[Vector2(-20, 6), Vector2(-23, -5), Vector2(-27, -16), Vector2(-30, -22)], 0.8],  # D
		[[Vector2(4, 1), Vector2(14, 5), Vector2(22, 9), Vector2(28, 13)], 0.8],  # C
		[[Vector2(28, 13), Vector2(29, 2), Vector2(30, -10)], 1.4],  # patrol strip
		[[Vector2(28, 13), Vector2(32, 24)], 0.5],  # stepping stones
		[[Vector2(30, -10), Vector2(32, -20)], 0.8],  # to the broken pontoon
		[[Vector2(-34, 6), Vector2(-33.5, 8)], 0.7],  # herb_01 pontoon
		[[Vector2(-32.9, 12.6), Vector2(-32.5, 14)], 0.7],  # pontoon end -> herb_01 islet
	]:
		paths.append([PackedVector2Array(spur[0]), spur[1]])
	# pontoons: the main crossing A -> B, herb_01, the ferry landing, the broken pontoon (chest_01)
	_decks = [
		[Vector2(-13, 5.8), PI * 0.5, true],
		[Vector2(-9, 5.5), PI * 0.5, true],
		[Vector2(-5, 5.2), PI * 0.5, true],
		[Vector2(-33.2, 10.5), 0.1, true],
		[Vector2(-25.5, -25.5), PI * 0.5, true],
		[Vector2(32.4, -22.5), -0.2, true],
		[Vector2(33.2, -26.5), -0.2, true],
		[Vector2(34.0, -30.5), -0.2, true],
		[Vector2(34.85, -34.6), -0.3, false],
	]
	_terrain("lantern_mire", 70, 42, 448)
	_mire_water()
	_mire_decks()
	_mire_water_walls()
	_place("beacon", BEACON_AT, 0.4)
	_place("house_b", Vector2(-34, -29), _face(Vector2(-34, -29), Vector2(-29, -23)), 0.72)
	_place("barrels", Vector2(-27.5, -29.5), 0.8, 0.8)
	_place("barrels", Vector2(35.5, -29.0), 2.2, 0.7)
	# lanterns: warm posts in pairs at both exits, along the causeways and at the pontoon ends
	var lamps: Array = []
	var posts := [
		[Vector2(-38, 3.4), Vector2(-38, 6)],
		[Vector2(-38, 8.6), Vector2(-38, 6)],
		[Vector2(7.4, -38), Vector2(10, -38)],
		[Vector2(12.6, -38), Vector2(10, -38)],
		[Vector2(-30, 3.2), Vector2(-30, 5)],
		[Vector2(-16.5, 8.2), Vector2(-16, 6)],
		[Vector2(-1.8, 2.4), Vector2(-1, 4.5)],
		[Vector2(7.6, -7), Vector2(5, -6)],
		[Vector2(3.6, -15), Vector2(1, -14)],
		[Vector2(1.6, -28.8), Vector2(-1, -28)],
		[Vector2(13, -33.5), Vector2(10, -35)],
		[Vector2(-25, -9), Vector2(-23, -8)],
		[Vector2(14.6, 7.6), Vector2(14, 5)],
		[Vector2(33.4, -17.5), Vector2(31.5, -17)],
	]
	for post in posts:
		var yaw := _face(post[0], post[1]) + PI * 0.5
		_place("lantern", post[0], yaw)
		var at: Vector2 = post[0]
		lamps.append(
			[
				(
					Vector3(at.x, _height(at.x, at.y) - 0.05, at.y)
					+ Basis(Vector3.UP, yaw) * LANTERN_LAMP
				),
				1.0
			]
		)
	lamps.append(
		[
			(
				Vector3(BEACON_AT.x, _height(BEACON_AT.x, BEACON_AT.y) - 0.05, BEACON_AT.y)
				+ BEACON_LAMP
			),
			2.4
		]
	)
	_mire_vegetation()
	# stepping stones to the flower islet (2 m apart), stones half sunk in the pools
	for k in range(1, 5):
		var p := Vector2(28, 13).lerp(Vector2(32, 24), k / 5.0)
		_place("rock_b", p, rng.randf() * TAU, rng.randf_range(0.45, 0.55), false)
	for i in 70:
		var p := Vector2(rng.randf_range(-36, 36), rng.randf_range(-36, 36))
		var h := _height(p.x, p.y)
		if h < MIRE_WATER - 0.05 and h > MIRE_WATER - 0.45 and _free_at(p, 1.0):
			_place("rock_b", p, rng.randf() * TAU, rng.randf_range(0.5, 0.9), false)
	_mire_cards()
	_flush()
	# will-o'-wisps hovering over the water: small warm glows in the same halo MultiMesh
	for i in 300:
		if lamps.size() >= posts.size() + 1 + 18:
			break
		var p := Vector2(rng.randf_range(-34, 34), rng.randf_range(-34, 34))
		if _height(p.x, p.y) < MIRE_WATER - 0.2 and _path_dist(p) > 3.0:
			lamps.append(
				[
					Vector3(p.x, MIRE_WATER + rng.randf_range(0.9, 1.8), p.y),
					rng.randf_range(0.3, 0.45)
				]
			)
	_mire_glow(lamps)
	_mire_mist()
	_backdrop(Vector3(40, -6, -150), 300.0)
	_borders(40.0)
	_environment(
		true,
		-104.0,
		-24.0,
		0.6,
		1.15,
		{"color": Color("#bcc2d6"), "density": 0.012, "height": 0.4, "height_density": 0.35}
	)
	_mire_markers()
	_save("lantern_mire.tscn")


func _mire_markers() -> void:
	_marker("Spawns", "default", Vector3(-34, 0, 6), Vector3.RIGHT)
	_marker("Spawns", "from_aubelin", Vector3(-34, 0, 6), Vector3.RIGHT)
	_marker("Spawns", "from_watch_ruins", Vector3(10, 0, -34), Vector3.BACK)
	_exit(
		"to_aubelin", Vector3(-39, 0, 6), Vector3(5, 3, 5), "location.aubelin", "from_lantern_mire"
	)
	_exit(
		"to_watch_ruins",
		Vector3(10, 0, -39),
		Vector3(5, 3, 5),
		"location.watch_ruins",
		"from_lantern_mire"
	)
	# names are the `anchor` fields of docs/content/dungeon.md §4 and bestiary_discoveries.md
	for a in [
		["encounter_01", Vector3(-22, 0, 2)],
		["encounter_02", Vector3(-6, 0, 20)],
		["encounter_03", Vector3(6, 0, -2)],
		["encounter_04", Vector3(28, 0, 12)],
		["encounter_05", Vector3(-4, 0, -24)],
		["discovery_01", Vector3(-30, 0, -24)],
		["discovery_02", Vector3(32, 0, 24)],
		["chest_01", Vector3(34, 0, -32)],
		["herb_01", Vector3(-32, 0, 14)],
		["herb_02", Vector3(0, 0, 6)],
		["herb_03", Vector3(4, 0, -36)],
	]:
		_marker("Anchors", a[0], a[1], Vector3.BACK)
	# the encounter_04 pack walks between these points (x, z), read by the exploration only
	(scene_root.get_node("Anchors/encounter_04") as Node3D).set_meta(
		"patrol", [[28, 12], [30, -10]]
	)
	# chest_01 stands on the last pontoon section, not on the bog floor
	var chest := scene_root.get_node("Anchors/chest_01") as Node3D
	chest.position.y = DECK_Y


func _mire_vegetation() -> void:
	# a few hero birches at the islet edges, low birches on hummocks, a birch rim on the hills
	for c in clearings:
		var centre: Vector2 = c[0]
		for k in 3:
			var a := rng.randf() * TAU
			var p: Vector2 = centre + Vector2(cos(a), sin(a)) * (c[1] + rng.randf_range(-0.5, 1.0))
			if _path_dist(p) > 1.6 and _free_at(p, 2.0) and _height(p.x, p.y) > MIRE_WATER + 0.3:
				_place(
					"birch_a" if rng.randf() < 0.5 else "birch_b",
					p,
					rng.randf() * TAU,
					rng.randf_range(0.65, 0.85)
				)
		for k in 4:
			var a := rng.randf() * TAU
			var p: Vector2 = centre + Vector2(cos(a), sin(a)) * (c[1] + rng.randf_range(-1.5, 0.5))
			if _path_dist(p) > 1.0 and _free_at(p, 0.6) and _height(p.x, p.y) > MIRE_WATER + 0.2:
				_place(
					"bush" if k < 2 else ("rock_a" if k == 2 else "rock_b"),
					p,
					rng.randf() * TAU,
					rng.randf_range(0.6, 1.0)
				)
	for i in 700:
		var p := Vector2(rng.randf_range(-38, 38), rng.randf_range(-38, 38))
		if _path_dist(p) < 2.0 or not _free_at(p, 3.0) or _height(p.x, p.y) < MIRE_WATER + 0.35:
			continue
		if rng.randf() < 0.7:
			continue
		_place(
			"birch_a_lo" if rng.randf() < 0.5 else "birch_b_lo",
			p,
			rng.randf() * TAU,
			rng.randf_range(0.6, 0.8)
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


func _mire_decks() -> void:
	# pontoon sections at deck height, with a box under each walkable deck (calque 1)
	for d in _decks:
		var at: Vector2 = d[0]
		var yaw: float = d[1]
		var y := DECK_Y if d[2] else DECK_Y - 0.35
		var basis := Basis(Vector3.UP, yaw)
		if not d[2]:
			basis = basis * Basis(Vector3.RIGHT, 0.12) * Basis(Vector3.FORWARD, 0.08)
		var xf := Transform3D(basis, Vector3(at.x, y, at.y))
		_instances.get_or_add("boardwalk", []).append(
			[xf, Color(rng.randf_range(-0.2, 0.1) + tint_bias, rng.randf_range(0.9, 1.0), 0, 0)]
		)
		occupied.append([at, 2.0])
		if not d[2]:
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 0.4, 4.0)
		shape.shape = box
		shape.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, DECK_Y - 0.2, at.y))
		_add(obstacles, shape, "boardwalk_%d" % obstacles.get_child_count())


func _on_deck(p: Vector2, margin: float) -> bool:
	for d in _decks:
		if not d[2]:
			continue
		var centre: Vector2 = d[0]
		var local := (p - centre).rotated(d[1])
		if absf(local.x) < 1.0 + margin and absf(local.y) < 2.0 + margin:
			return true
	return false


func _mire_water() -> void:
	# one flat sheet over every low cell; UV.x = 0 on the shore (foam) .. 0.5 in deep water
	# (env_water reads |UV.x - 0.5| as the distance to the bank), UV.y in metres.
	# Half-metre cells so the pale shore band follows the bank instead of the 1 m terrain grid.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(-90, 90):
		for i in range(-90, 90):
			var o := Vector2(i, j) * 0.5
			var corners := [o, o + Vector2(0.5, 0), o + Vector2(0, 0.5), o + Vector2(0.5, 0.5)]
			var low := false
			var depth := []
			for c: Vector2 in corners:
				var h := _height(c.x, c.y)
				low = low or h < MIRE_WATER + 0.02
				depth.append(0.5 * clampf((MIRE_WATER - h) / 0.3, 0.0, 1.0))
			if not low:
				continue
			for k in [0, 2, 1, 1, 2, 3]:
				var c: Vector2 = corners[k]
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(depth[k], c.y + c.x * 0.3))
				st.add_vertex(Vector3(c.x, MIRE_WATER, c.y))
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = ENV_WATER
	mat.set_shader_parameter("deep_color", Color(0.15, 0.24, 0.25, 0.95))
	mat.set_shader_parameter("shallow_color", Color(0.3, 0.4, 0.35, 0.92))
	mat.set_shader_parameter("foam_color", Color(0.62, 0.66, 0.6, 1.0))
	mat.set_shader_parameter("flow_speed", 0.03)
	mat.set_shader_parameter("streak_scale", 0.7)
	mesh.surface_set_material(0, mat)
	var path := ENV + "terrain/lantern_mire/pools.res"
	ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
	var mi := MeshInstance3D.new()
	_add(_group("Water"), mi, "Pools")
	mi.mesh = load(path)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mire_water_walls() -> void:
	# deep water blocks Fern and the navmesh: 1 m cells merged into row runs, then into boxes
	var open := {}  # Vector2i(x0, x1) -> [z0, z1]
	var boxes := []
	for j in range(-41, 41):
		var runs := {}
		var i := -41
		while i < 41:
			if _mire_deep(Vector2(i + 0.5, j + 0.5)):
				var i0 := i
				while i < 41 and _mire_deep(Vector2(i + 0.5, j + 0.5)):
					i += 1
				runs[Vector2i(i0, i)] = true
			i += 1
		for key: Vector2i in open.keys():
			if runs.has(key):
				open[key][1] = j + 1
				runs.erase(key)
			else:
				boxes.append([key, open[key]])
				open.erase(key)
		for key: Vector2i in runs:
			open[key] = [j, j + 1]
	for key: Vector2i in open:
		boxes.append([key, open[key]])
	for b in boxes:
		var xs: Vector2i = b[0]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(xs.y - xs.x, 3.0, b[1][1] - b[1][0])
		shape.shape = box
		shape.position = Vector3((xs.x + xs.y) * 0.5, 0.5, (b[1][0] + b[1][1]) * 0.5)
		_add(obstacles, shape, "water_%d" % obstacles.get_child_count())


func _mire_deep(p: Vector2) -> bool:
	return _height(p.x, p.y) < MIRE_WATER - 0.1 and not _on_deck(p, 0.4)


func _mire_cards() -> void:
	# reeds (1.5 m, camera cut-out) on every shore; autumn grass, ferns and a few flowers on land
	for i in 9000:
		var p := Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		var h := _height(p.x, p.y)
		if h < MIRE_WATER - 0.35 or h > MIRE_WATER + 0.25 or _path_dist(p) < 0.6:
			continue
		if not _free_at(p, -0.2):
			continue
		var cell := CARD_DRY if rng.randf() < 0.6 else CARD_GREEN
		_card(p, cell, rng.randf_range(0.7, 0.9), rng.randf_range(1.7, 2.2), -0.2, "_reeds")
	for i in 15000:
		var p := Vector2(rng.randf_range(-42, 42), rng.randf_range(-42, 42))
		var h := _height(p.x, p.y)
		if h < MIRE_WATER + 0.05 or _path_dist(p) < 0.3 or not _free_at(p, -0.2):
			continue
		var r := rng.randf()
		var cell := CARD_DRY if r < 0.4 else (CARD_GREEN if r < 0.62 else CARD_SHORT)
		if r > 0.9:
			cell = CARD_FERN
		elif r > 0.87:
			cell = CARD_LAVENDER if rng.randf() < 0.6 else CARD_PINK
		var size := rng.randf_range(0.45, 0.8) if cell != CARD_FERN else rng.randf_range(0.6, 0.95)
		_card(p, cell, size, 1.0, -0.1)
	# the flower islet (discovery_02)
	for k in 16:
		var p := Vector2(32, 24) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 2.0
		_card(p, CARD_PINK if k % 3 else CARD_DAISY, rng.randf_range(0.5, 0.7))


func _mire_glow(lamps: Array) -> void:
	# lantern halos and wisps: one billboard MultiMesh, [position, scale] per light
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 1.7)
	var mat := ShaderMaterial.new()
	mat.shader = ENV_GLOW
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = lamps.size()
	for i in lamps.size():
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * lamps[i][1])
		mm.set_instance_transform(i, Transform3D(basis, lamps[i][0]))
	var mmi := MultiMeshInstance3D.new()
	_add(_group("Glow"), mmi, "LanternHalos")
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mire_mist() -> void:
	# low mist banks over the pools: soft alpha cards tilted towards the camera
	var quad := QuadMesh.new()
	quad.size = Vector2(12, 5)
	var mat := ShaderMaterial.new()
	mat.shader = ENV_MIST
	quad.material = mat
	var xfs := []
	for i in 600:
		if xfs.size() >= 28:
			break
		var p := Vector2(rng.randf_range(-38, 38), rng.randf_range(-38, 38))
		if _height(p.x, p.y) > MIRE_WATER - 0.2 or _path_dist(p) < 1.5:
			continue
		var basis := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, -1.1)
		xfs.append(
			Transform3D(
				basis.scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)),
				Vector3(p.x, MIRE_WATER + 0.9, p.y)
			)
		)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	_add(_group("Mist"), mmi, "MistBanks")
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
