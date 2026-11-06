extends "res://game/world/prototype/ruins_layout.gd"
## Silent Dial Cloister set pieces and helpers for the offline builder (cloister_layout.gd extends
## this): statues, fallen columns, feathered moon pools, mist banks, ember threads, and the
## terrain over any rectangle.


func _statue(at: Vector2, yaw: float, scale: float, y: float = 0.0, look_at := Vector2.INF) -> void:
	# a hooded watcher on its plinth, with a small collider at its foot
	if look_at != Vector2.INF:
		yaw = _face(at, look_at)
	_put_at("watcher_statue", Vector3(at.x, y - 0.03, at.y), yaw, Vector3.ONE * scale)
	var cyl := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.4
	shape.height = 3.0
	cyl.shape = shape
	cyl.position = Vector3(at.x, y + 1.5, at.y)
	_add(obstacles, cyl, "statue_%d" % obstacles.get_child_count())


func _fallen_column(at: Vector2, yaw: float, scale: float, y: float = 0.0) -> void:
	# broken drums lying along their local Z (4.6 m at scale 1), with a low collision box
	_put_at("fallen_column", Vector3(at.x, y - 0.05, at.y), yaw, Vector3.ONE * scale)
	_box_collider(Vector3(at.x, y + 0.6, at.y), Vector3(1.6, 1.2, 4.0) * scale, yaw)


func _moon_pool(at: Vector3, radius: float, intensity: float, aspect: float = 1.0) -> void:
	# feathered moonlight on the floor (env_moonpool); `aspect` stretches it along x
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0 * aspect, radius * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = ENV_MOONPOOL
	mat.set_shader_parameter("color", Color("#bcd0ff"))
	mat.set_shader_parameter("intensity", intensity)
	plane.material = mat
	var mi := MeshInstance3D.new()
	var g := _group("LightShafts")
	_add(g, mi, "MoonPool_%d" % g.get_child_count())
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at + Vector3(0, 0.06, 0)


func _shade_ring(at: Vector3, radius: float, inner: float, darkness: float) -> void:
	# multiply-blended annulus (env_shade): the floor dims from `inner` (fraction) to `radius`
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = ENV_SHADE
	mat.set_shader_parameter("inner", inner)
	mat.set_shader_parameter("darkness", darkness)
	plane.material = mat
	var mi := MeshInstance3D.new()
	var g := _group("LightShafts")
	_add(g, mi, "Shade_%d" % g.get_child_count())
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at + Vector3(0, 0.05, 0)


func _dial_mist(c: Vector2, y: float) -> void:
	# low mist banks over the rim of the dial (one MultiMesh of flat env_mist cards)
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0, 4.5)
	var mat := ShaderMaterial.new()
	mat.shader = ENV_MIST
	mat.set_shader_parameter("color", Color(0.72, 0.78, 0.92))
	mat.set_shader_parameter("opacity", 0.34)
	mat.set_shader_parameter("near_fade", 6.0)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 12
	for i in 12:
		var a := i * TAU / 12.0 + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(13.0, 16.5)
		var p := c + Vector2(cos(a), -sin(a)) * r
		var basis := Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)
		mm.set_instance_transform(
			i, Transform3D(basis, Vector3(p.x, y + 0.35 + 0.1 * (i % 3), p.y))
		)
	var mmi := MultiMeshInstance3D.new()
	_add(_group("Mist"), mmi, "DialMist")
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ember_threads(from: Vector3, tips: Array) -> void:
	# one ribbon per lantern, sagging a little, made of a flat strip (seen from the 50 deg camera) and
	# an upright one (seen low); UV.x along the thread, UV2.x a per-thread phase. One draw call.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	for k in tips.size():
		var to: Vector3 = tips[k]
		var dir := to - from
		var side := Vector3(-dir.z, 0, dir.x).normalized()
		var pts := []
		for j in segs + 1:
			var t := float(j) / segs
			var p := from.lerp(to, t)
			p.y -= sin(t * PI) * 1.0  # sag
			p += side * sin(t * PI * 3.0 + k) * 0.25 * sin(t * PI)  # a slight drift
			pts.append(p)
		for across: Vector3 in [side * 0.22, Vector3.UP * 0.22]:
			for j in segs:
				var q := [
					pts[j] - across, pts[j] + across, pts[j + 1] + across, pts[j + 1] - across
				]
				var uv := [
					Vector2(float(j) / segs, 0),
					Vector2(float(j) / segs, 1),
					Vector2(float(j + 1) / segs, 1),
					Vector2(float(j + 1) / segs, 0)
				]
				for i in [0, 1, 2, 0, 2, 3]:
					st.set_uv(uv[i])
					st.set_uv2(Vector2(k * 1.7, 0))
					st.set_normal(Vector3.UP)
					st.add_vertex(q[i])
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = ENV_EMBER
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	_add(_group("Glow"), mi, "EmberThreads")
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
