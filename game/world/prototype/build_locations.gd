extends "res://game/world/prototype/location_builder.gd"
## Offline builder: lays out Aubelin and the Whispering Wood with the toolkit in
## location_builder.gd and saves res://game/world/locations/*.tscn.
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     -s res://game/world/prototype/build_locations.gd


func _init() -> void:
	noise.seed = 11
	noise.frequency = 0.045
	noise2.seed = 23
	noise2.frequency = 0.012
	_prepare_kit()
	_build_aubelin()
	_build_wood()
	quit()


# --- Aubelin -----------------------------------------------------------------------------------


func _stream_x(z: float) -> float:
	return STREAM_X + 1.8 * sin(z * 0.07 + 0.5)


func _aubelin_height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 0.12
	var ds := absf(x - _stream_x(z))
	h -= 1.15 * (1.0 - smoothstep(1.4, 3.4, ds))
	var r := maxf(absf(x), absf(z))
	var rise := smoothstep(31.0, 62.0, r)
	h += rise * rise * (7.0 + 5.0 * noise2.get_noise_2d(x, z))
	return h


func _aubelin_splat(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var dirt := 1.0 - smoothstep(-0.4, 0.9, _path_dist(p))
	var cob := 1.0 - smoothstep(5.6, 6.8, p.length() + noise.get_noise_2d(x * 3.0, z * 3.0) * 1.0)
	var ds := absf(x - _stream_x(z))
	dirt = maxf(dirt, 1.0 - smoothstep(2.6, 3.6, ds))
	if _in_field(p):
		dirt = maxf(dirt, 0.55)
	var forest := (
		smoothstep(34.0, 46.0, p.length()) * (0.5 + 0.5 * noise2.get_noise_2d(x * 3.0, z * 3.0))
	)
	return Color(dirt, cob, forest, 1.0)


func _build_aubelin() -> void:
	_begin("Aubelin")
	rng.seed = 1701
	_height_fn = _aubelin_height
	_splat_fn = _aubelin_splat
	# compact ring: the 50° / 14 m camera shows ~20 x 18 m; a small square reads as a village
	var houses := [
		["house_a", Vector2(-11.5, -2.5)],
		["house_b", Vector2(-3.0, -11.5)],
		["house_c", Vector2(5.5, -11.5)],
		["house_a", Vector2(11.5, -5.0)],
		["house_b", Vector2(11.0, 6.5)],
		["house_c", Vector2(5.5, 12.0)],
		["house_a", Vector2(-6.0, 11.5)],
		["house_c", Vector2(-12.0, 5.5)],
	]
	# roads: NW to the wood, S to the fields, E over the bridge
	var nw_road := [
		Vector2(0, 0),
		Vector2(-7, -7.5),
		Vector2(-15, -15),
		Vector2(-24, -23.5),
		Vector2(-36, -33),
		Vector2(-60, -50)
	]
	paths.append([PackedVector2Array(nw_road), 1.5])
	paths.append(
		[
			PackedVector2Array(
				[Vector2(0, 0), Vector2(1, 12), Vector2(-1, 22), Vector2(0.5, 34), Vector2(2, 62)]
			),
			1.4
		]
	)
	var east := [
		Vector2(0, 0),
		Vector2(10, 1),
		Vector2(STREAM_X - 4, 0.3),
		Vector2(STREAM_X + 4, 0.3),
		Vector2(34, 2),
		Vector2(62, 4)
	]
	paths.append([PackedVector2Array(east), 1.4])
	fields.append(Rect2(-28, 14, 14, 14))
	fields.append(Rect2(4.5, 18, 11, 10))
	fields.append(Rect2(-29, -14, 8, 7))
	_terrain("aubelin", 70, 34, 448)

	# houses face the square; tint / scale variations
	for k in houses.size():
		var at: Vector2 = houses[k][1]
		var yaw := _face(at, Vector2.ZERO) + rng.randf_range(-0.12, 0.12)
		_place(houses[k][0], at, yaw, rng.randf_range(0.95, 1.06))
	_place("well", Vector2(0, -0.5), 0.4)
	_place("stall", Vector2(4.4, -3.4), _face(Vector2(4.4, -3.4), Vector2(0, 4)))
	_place("barrels", Vector2(6.6, -1.8), 0.6, 0.9)
	_place("cart", Vector2(-4.6, 4.4), 2.3)
	_place("barrels", Vector2(-8.4, -6.6), 1.2, 0.85)
	_place("barrels", Vector2(8.4, 9.6), 2.8, 0.8)
	_place("barrels", Vector2(-2.6, 9.4), -0.4, 0.75)
	_stream_water()
	_place("bridge", Vector2(STREAM_X + 0.3, 0.3), 0.0, 1.0)
	# bank walls: the stream is crossed only by the bridge
	_stream_walls()
	# lanterns: square corners, the NW exit (warm posts mark exits, GDD 5.4), bridge, south road
	for at in [Vector2(-5.2, -4.4), Vector2(5.4, 4.6), Vector2(-3.6, 6.2), Vector2(1.6, -6.4)]:
		_place("lantern", at, _face(at, Vector2.ZERO) + PI * 0.5)
	for at in [
		Vector2(-22.0, -24.5),
		Vector2(-25.8, -20.6),
		Vector2(STREAM_X - 4.5, -2.2),
		Vector2(STREAM_X + 4.5, 2.6),
		Vector2(2.8, 24)
	]:
		_place("lantern", at, rng.randf() * TAU)
	# fields: fenced, wheat-like dry grass cards
	_fence_line(Vector2(-28, 13.6), Vector2(-14, 13.6), 4)
	_fence_line(Vector2(-13.6, 14), Vector2(-13.6, 28))
	_fence_line(Vector2(4.2, 17.6), Vector2(15.5, 17.6), 3)
	_fence_line(Vector2(4.2, 18), Vector2(4.2, 28))
	_fence_line(Vector2(-29.5, -14.4), Vector2(-20.6, -14.4))
	_fence_line(Vector2(-20.6, -14), Vector2(-20.6, -6.8))
	for f: Rect2 in fields:
		var x := f.position.x + 0.4
		while x < f.end.x - 0.3:
			var z := f.position.y + 0.4
			while z < f.end.y - 0.3:
				var p := Vector2(x + rng.randf_range(-0.2, 0.2), z + rng.randf_range(-0.2, 0.2))
				_card(p, CARD_DRY, rng.randf_range(0.85, 1.15), rng.randf_range(1.0, 1.35), 0.3)
				z += 0.62
			x += 0.62
	occupied.append([Vector2.ZERO, 6.2])  # keep the square clear
	# trees: a few inside the village, a dense birch belt on the hills (thicker towards the wood, NW)
	var inner_trees := [
		Vector2(-22, -8),
		Vector2(-21, 2),
		Vector2(-11, -22),
		Vector2(3, -24),
		Vector2(15, -18),
		Vector2(24, -14),
		Vector2(25, 13),
		Vector2(-24, 15),
		Vector2(-18, 24),
		Vector2(12, 26),
		Vector2(-26, -14),
		Vector2(19, -26),
		Vector2(-9, 27),
		Vector2(27, 26),
		Vector2(-28, 3)
	]
	for at in inner_trees:
		_place(
			"birch_a" if rng.randf() < 0.55 else "birch_b",
			at,
			rng.randf() * TAU,
			rng.randf_range(0.85, 1.15)
		)
	for i in 1400:
		var p := Vector2(rng.randf_range(-66, 66), rng.randf_range(-66, 66))
		var r := maxf(absf(p.x), absf(p.y))
		if r < 31.5:
			continue
		var nw := clampf((-p.x - p.y) / 60.0, 0.0, 1.0)
		if rng.randf() > 0.25 + 0.55 * nw or _path_dist(p) < 1.2 or not _free_at(p, 2.4):
			continue
		if absf(p.x - _stream_x(p.y)) < 3.0:
			continue
		_place(
			"birch_a_lo" if rng.randf() < 0.5 else "birch_b_lo",
			p,
			rng.randf() * TAU,
			rng.randf_range(0.85, 1.25),
			false
		)
	# bushes against the houses and along the fences
	for h in houses:
		var at: Vector2 = h[1]
		var side := Vector2(-at.y, at.x).normalized()
		for s in [-1.0, 1.0]:
			var p: Vector2 = (
				at
				+ side * s * rng.randf_range(3.6, 4.4)
				- at.normalized() * rng.randf_range(0.5, 2.5)
			)
			if _free_at(p, 0.3) and _path_dist(p) > 0.5:
				_place("bush", p, rng.randf() * TAU, rng.randf_range(0.8, 1.2))
	for i in 60:
		var p := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		if (
			_path_dist(p) > 1.5
			and _free_at(p, 1.0)
			and not _in_field(p, 1.0)
			and absf(p.x - _stream_x(p.y)) > 4.0
		):
			_place("bush", p, rng.randf() * TAU, rng.randf_range(0.7, 1.15))
	for i in 40:
		var p := Vector2(rng.randf_range(-34, 34), rng.randf_range(-34, 34))
		if (
			_path_dist(p) > 1.0
			and _free_at(p, 1.0)
			and not _in_field(p, 0.5)
			and absf(p.x - _stream_x(p.y)) > 3.5
		):
			_place(
				"rock_a" if rng.randf() < 0.4 else "rock_b",
				p,
				rng.randf() * TAU,
				rng.randf_range(0.45, 0.9)
			)
	_grass(34.0, 9000, 0.35)
	_flush()
	_backdrop(Vector3(-10, -6, -150), 300.0)
	_borders(30.0)
	_environment(false, -62.0, -30.0)
	_marker("Spawns", "default", Vector3(0.5, 0, 4.0), Vector3.FORWARD)
	_marker(
		"Spawns", "from_whispering_wood", Vector3(-21.0, 0, -20.0), Vector3(1, 0, 1).normalized()
	)
	_exit(
		"to_whispering_wood",
		Vector3(-26.5, 0, -25.5),
		Vector3(5, 3, 5),
		"location.whispering_wood",
		"from_aubelin"
	)
	for a in [
		["npc_well", Vector3(-1.8, 0, 1.6)],
		["npc_stall", Vector3(4.0, 0, -1.4)],
		["board", Vector3(-4.4, 0, -2.4)],
		["discovery_bridge", Vector3(STREAM_X - 3, 0, 1.5)]
	]:
		_marker("Anchors", a[0], a[1], Vector3.BACK)
	_save("aubelin.tscn")


func _stream_water() -> void:
	# ribbon along the stream bed: UV.x across (0..1), UV.y in metres along the flow
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := 2.4
	for z in range(-70, 70):
		var quad := []
		for zz in [z, z + 1]:
			var xs := _stream_x(zz)
			quad.append([Vector3(xs - half_w, -0.62, zz), Vector2(0, zz)])
			quad.append([Vector3(xs + half_w, -0.62, zz), Vector2(1, zz)])
		for k in [0, 2, 1, 1, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(quad[k][1])
			st.add_vertex(quad[k][0])
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = ENV_WATER
	mesh.surface_set_material(0, mat)
	var path := ENV + "terrain/aubelin/stream.res"
	ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
	var mi := MeshInstance3D.new()
	_add(_group("Water"), mi, "Stream")
	mi.mesh = load(path)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _stream_walls() -> void:
	for z in range(-31, 31, 2):
		if absf(z - 0.3) < 2.6:
			continue
		for s in [-1.0, 1.0]:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.6, 3, 2.2)
			shape.shape = box
			shape.position = Vector3(_stream_x(z + 1) + s * 2.2, 1.0, z + 1)
			_add(obstacles, shape, "bank_%d_%d" % [z + 40, int(s)])


func _grass(extent: float, tries: int, flower_bias: float) -> void:
	var flowers := [CARD_DAISY, CARD_LAVENDER, CARD_BUTTERCUP, CARD_PINK]
	for i in tries:
		var p := Vector2(rng.randf_range(-extent, extent), rng.randf_range(-extent, extent))
		var s: Color = _splat_fn.call(p.x, p.y)
		if s.r + s.g > 0.25 or _in_field(p, 0.3) or not _free_at(p, -0.2):
			continue
		var edge := _path_dist(p)
		var cell := CARD_GREEN if rng.randf() < 0.5 else CARD_SHORT
		# flowers gather along the roads and fences, like the A_world frame
		if rng.randf() < flower_bias + (0.35 if edge < 2.5 else 0.0):
			cell = flowers[rng.randi() % flowers.size()]
		elif s.b > 0.4 and rng.randf() < 0.5:
			cell = CARD_FERN
		elif rng.randf() < 0.12:
			cell = CARD_DRY
		var size := rng.randf_range(0.45, 0.8) if cell != CARD_FERN else rng.randf_range(0.6, 0.95)
		_card(p, cell, size)


# --- Whispering Wood ---------------------------------------------------------------------------


func _wood_height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 0.35 + noise2.get_noise_2d(x * 2.0, z * 2.0) * 0.6
	var r := maxf(absf(x), absf(z))
	var rise := smoothstep(36.0, 70.0, r)
	h += rise * rise * (6.0 + 4.0 * noise2.get_noise_2d(x, z))
	# flatten the path and clearings a little
	var p := Vector2(x, z)
	var flat := 1.0 - smoothstep(0.0, 3.0, _path_dist(p))
	for c in clearings:
		flat = maxf(flat, 1.0 - smoothstep(c[1] * 0.6, c[1] + 2.0, p.distance_to(c[0])))
	return lerpf(h, h * 0.35, flat)


func _wood_splat(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var dirt := 1.0 - smoothstep(-0.5, 0.8, _path_dist(p))
	var open := 0.0
	for c in clearings:
		open = maxf(open, 1.0 - smoothstep(c[1] * 0.55, c[1] * 1.05, p.distance_to(c[0])))
	var forest := clampf(1.0 - open * 1.2 + noise.get_noise_2d(x * 2.0, z * 2.0) * 0.4, 0.0, 1.0)
	return Color(dirt, 0.0, forest, 1.0)


func _build_wood() -> void:
	_begin("WhisperingWood")
	rng.seed = 4242
	_height_fn = _wood_height
	_splat_fn = _wood_splat
	clearings = [
		[Vector2(23, 22), 6.5],  # arrival from Aubelin
		[Vector2(8, 6), 7.0],
		[Vector2(-11, 13), 6.0],
		[Vector2(-4, -10), 8.0],
		[Vector2(-23, -7), 6.0],
		[Vector2(-14, -26), 7.0],
		[Vector2(15, -19), 6.0],
	]
	paths.append(
		[
			PackedVector2Array(
				[
					Vector2(40, 40),
					Vector2(30, 30),
					Vector2(23, 22),
					Vector2(15, 13),
					Vector2(8, 6),
					Vector2(1, -3),
					Vector2(-4, -10),
					Vector2(-10, -18),
					Vector2(-14, -26),
					Vector2(-20, -34),
					Vector2(-30, -50)
				]
			),
			1.2
		]
	)
	paths.append(
		[
			PackedVector2Array(
				[
					Vector2(8, 6),
					Vector2(-1, 10),
					Vector2(-11, 13),
					Vector2(-18, 4),
					Vector2(-23, -7)
				]
			),
			0.9
		]
	)
	paths.append([PackedVector2Array([Vector2(-4, -10), Vector2(5, -15), Vector2(15, -19)]), 0.9])
	_terrain("whispering_wood", 75, 38, 480)
	# trees: dense birches everywhere except the path and the clearings
	var tree_spots := []
	for i in 9000:
		var p := Vector2(rng.randf_range(-72, 72), rng.randf_range(-72, 72))
		var inner := maxf(absf(p.x), absf(p.y)) < 37.0
		var spacing := 3.9 if inner else 4.6
		if _path_dist(p) < 1.6:
			continue
		var in_clear := false
		for c in clearings:
			if p.distance_to(c[0]) < c[1]:
				in_clear = true
		if in_clear:
			continue
		var ok := true
		for q in tree_spots:
			if p.distance_squared_to(q) < spacing * spacing:
				ok = false
				break
		if not ok:
			continue
		tree_spots.append(p)
		var hero := inner and rng.randf() < 0.18
		var kit_name := (
			("birch_a" if rng.randf() < 0.5 else "birch_b")
			if hero
			else ("birch_a_lo" if rng.randf() < 0.5 else "birch_b_lo")
		)
		_place(kit_name, p, rng.randf() * TAU, rng.randf_range(0.7, 1.0), inner)
	# undergrowth: bushes and rocks at clearing edges, ferns and grass everywhere
	for c in clearings:
		var centre: Vector2 = c[0]
		for k in 5:
			var a := rng.randf() * TAU
			var p: Vector2 = centre + Vector2(cos(a), sin(a)) * (c[1] + rng.randf_range(-1.2, 0.8))
			if _path_dist(p) > 1.0 and _free_at(p, 0.5):
				_place(
					"bush" if k < 3 else ("rock_a" if k == 3 else "rock_b"),
					p,
					rng.randf() * TAU,
					rng.randf_range(0.7, 1.2)
				)
	for i in 70:
		var p := Vector2(rng.randf_range(-36, 36), rng.randf_range(-36, 36))
		if _path_dist(p) > 1.2 and _free_at(p, 0.8):
			_place(
				["bush", "rock_a", "rock_b"][rng.randi() % 3],
				p,
				rng.randf() * TAU,
				rng.randf_range(0.6, 1.1)
			)
	occupied.clear()
	for p in tree_spots:
		occupied.append([p, 0.35])
	_grass(40.0, 11000, 0.12)
	_flush()
	# light shafts through the canopy in the clearings, leaning with the sun
	var shaft := QuadMesh.new()
	shaft.size = Vector2(2.6, 16)
	var shaft_mat := ShaderMaterial.new()
	shaft_mat.shader = ENV_SHAFT
	shaft_mat.set_shader_parameter("intensity", 0.13)
	shaft_mat.set_shader_parameter("near_fade", 10.0)
	shaft.material = shaft_mat
	var shafts := _group("LightShafts")
	for c in clearings:
		for k in 3:
			var mi := MeshInstance3D.new()
			_add(shafts, mi, "Shaft_%d" % shafts.get_child_count())
			mi.mesh = shaft
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var centre: Vector2 = c[0]
			var p := centre + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			mi.position = Vector3(p.x, _height(p.x, p.y) + 6.5, p.y)
			mi.rotation = Vector3(
				0, deg_to_rad(rng.randf_range(-20, 20)), deg_to_rad(-28 + rng.randf_range(-4, 4))
			)
	_borders(35.0)
	_environment(true, -48.0, -38.0, 0.85, 0.85)
	_marker("Spawns", "default", Vector3(8, 0, 9), Vector3(-0.6, 0, -1).normalized())
	_marker("Spawns", "from_aubelin", Vector3(26.5, 0, 25.5), Vector3(-1, 0, -1).normalized())
	_exit(
		"to_aubelin",
		Vector3(31.5, 0, 31.5),
		Vector3(5, 3, 5),
		"location.aubelin",
		"from_whispering_wood"
	)
	var enc := 1
	for c in clearings.slice(2):
		var centre: Vector2 = c[0]
		_marker("Anchors", "encounter_%02d" % enc, Vector3(centre.x, 0, centre.y), Vector3.BACK)
		enc += 1
	_marker("Anchors", "chest_01", Vector3(-16, 0, -29), Vector3.BACK)
	_marker("Anchors", "discovery_01", Vector3(17, 0, -21), Vector3.BACK)
	_save("whispering_wood.tscn")
