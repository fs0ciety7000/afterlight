extends SceneTree
## Shared toolkit of the offline location builder (build_locations.gd).
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     -s res://game/world/prototype/build_locations.gd
## (a real GL driver is needed: the headless dummy renderer drops MultiMesh buffers)
##
## 1. Turns each environment GLB (assets/environment/<category>/*.glb) into a mesh resource with the
##    env_toon material (assets/environment/meshes/, materials/).
## 2. Builds the painted ground (chunked mesh + splat map + height-map collision) per location.
## 3. Lays out props, vegetation (MultiMesh, chunked so the camera culls them), collisions, spawns,
##    exits and lighting following docs/ARCHITECTURE.md "Scènes de lieu", and saves
##    res://game/world/locations/<location>.tscn.
## Layout is fixed by seeded RNGs: running it again gives the same scenes.

const ENV := "res://assets/environment/"
const OUT := "res://game/world/locations/"
const STREAM_X := 21.0
const ENV_TOON: Shader = preload("res://assets/shaders/env_toon.gdshader")
const ENV_TERRAIN: Shader = preload("res://assets/shaders/env_terrain.gdshader")
const ENV_WATER: Shader = preload("res://assets/shaders/env_water.gdshader")
const ENV_SHAFT: Shader = preload("res://assets/shaders/env_lightshaft.gdshader")
const ENV_GLOW: Shader = preload("res://assets/shaders/env_glow.gdshader")
const ENV_MIST: Shader = preload("res://assets/shaders/env_mist.gdshader")
const ENV_BACKDROP: Shader = preload("res://assets/shaders/env_backdrop.gdshader")
const OUTLINE: Shader = preload("res://assets/shaders/outline.gdshader")

## Kit: category folder, collision ("box", "cyl" with radius factor of footprint, "mesh", ""),
## ink outline, foliage settings, camera fade. "front_yaw": rotation that turns the model's front
## towards +Z. Ink outlines only on smooth meshes: on hard-surface pieces (split normals)
## the inverted hull cracks into stray black slivers.
const KIT := {
	"house_a": {"dir": "buildings", "col": "box", "fade": true, "front_yaw": 0.0},
	"house_b": {"dir": "buildings", "col": "box", "fade": true, "front_yaw": 0.0},
	"house_c": {"dir": "buildings", "col": "box", "fade": true, "front_yaw": 0.0},
	"well": {"dir": "props", "col": "cyl", "r": 0.42},
	"fence": {"dir": "props", "col": "box"},
	"stall": {"dir": "props", "col": "box"},
	"cart": {"dir": "props", "col": "box"},
	"lantern": {"dir": "props", "col": "post"},
	"barrels": {"dir": "props", "col": "box"},
	"bridge": {"dir": "props", "col": "mesh"},
	# card canopies (tools/blender/build_foliage.py): trunk + painted leaf-tuft cards, alpha scissor
	"birch_a": {"dir": "vegetation", "col": "trunk", "wind": 0.07, "fade": true, "cards": true},
	"birch_b": {"dir": "vegetation", "col": "trunk", "wind": 0.07, "fade": true, "cards": true},
	"birch_a_lo": {"dir": "vegetation", "col": "trunk", "wind": 0.07, "fade": true, "cards": true},
	"birch_b_lo": {"dir": "vegetation", "col": "trunk", "wind": 0.07, "fade": true, "cards": true},
	"fruit_tree": {"dir": "vegetation", "col": "trunk", "wind": 0.05, "fade": true, "cards": true},
	"bush": {"dir": "vegetation", "col": "cyl", "r": 0.3, "wind": 0.025, "cards": true},
	# village dressing (tools/blender/build_village_props.py); flower cards in the atlas alpha
	"doorstep": {"dir": "props", "col": "", "cards": true},
	"flower_bed": {"dir": "props", "col": "box", "cards": true},
	"rock_a": {"dir": "rocks", "col": "cyl", "r": 0.42, "outline": true},
	"rock_b": {"dir": "rocks", "col": "", "outline": true},
	# Lantern Mire pieces (tools/blender/build_mire_props.py); the boardwalk's colliders are its deck
	"boardwalk": {"dir": "props", "col": ""},
	"beacon": {"dir": "props", "col": "cyl", "r": 0.4, "fade": true},
	"ferry_hut": {"dir": "props", "col": "box", "fade": true},
	# Watch Ruins and Silent Dial Cloister stone kit (tools/blender/build_cloister_props.py); walls
	# and arches get one collision box per wall run from the layout, not one per piece
	"wall": {"dir": "ruins", "col": "", "fade": true},
	"wall_broken": {"dir": "ruins", "col": "", "fade": true},
	"pillar": {"dir": "ruins", "col": "cyl", "r": 0.42, "fade": true},
	"arch": {"dir": "ruins", "col": "", "fade": true},
	"stairs": {"dir": "ruins", "col": ""},
	"brazier": {"dir": "ruins", "col": "cyl", "r": 0.4},
	"torch_post": {"dir": "ruins", "col": "post"},
	"fountain": {"dir": "ruins", "col": "cyl", "r": 0.5},
	"campfire": {"dir": "ruins", "col": ""},
	"grille": {"dir": "ruins", "col": ""},
	"bell": {"dir": "ruins", "col": "", "fade": true},
	"dial": {"dir": "ruins", "col": ""},
	"tower_ruin": {"dir": "ruins", "col": "box", "fade": true},
	"rubble": {"dir": "ruins", "col": ""},
	"lectern": {"dir": "ruins", "col": "post"},
}
## Grass / flower atlas cells (assets/environment/textures/grass_cards.png, 4 x 2).
const CARD_GREEN := 0
const CARD_DRY := 1
const CARD_DAISY := 2
const CARD_LAVENDER := 3
const CARD_BUTTERCUP := 4
const CARD_FERN := 5
const CARD_PINK := 6
const CARD_SHORT := 7

## Golden-afternoon light (A_world.jpg): low warm sun, long blue-green tinted shadows, a little
## darker overall than the first pass (owner review of docs/screens/m2/).
const DAY := {
	"sun": Color("#ffd8a0"),
	"sun_energy": 0.68,
	"ambient": Color("#aeb3d6"),
	"ambient_energy": 0.3,
	"shadow_tint": Color("#7c9cb0"),
	"sky_top": Color("#8ea4dd"),
	"sky_horizon": Color("#f3d6c4"),
	"ground_bottom": Color("#8a8f6a"),
	"haze": Color("#efd8c4"),
	"brightness": 0.96,
}

var meshes := {}
var aabbs := {}
var card_mesh: ArrayMesh
## Same cards with the camera cut-out on: tall reeds that would hide Fern (Lantern Mire).
var reed_mesh: ArrayMesh
var scene_root: Node3D
var obstacles: StaticBody3D
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var occupied: Array = []  # [Vector2 centre, radius] kept clear of scatter
# per-location layout data used by the height / splat callables
var paths: Array = []  # [PackedVector2Array, half width]
var clearings: Array = []  # [Vector2, radius]
var fields: Array = []  # Rect2 (x, z)
## Per-location look: added to each placed prop's warm / cool tint (< 0 cooler), ground grass tint.
var tint_bias := 0.0
var grass_tint := Color(0.86, 0.95, 0.76)
## Multiplies the brightness of placed props (instance custom .g): < 1 for night places.
var bright_scale := 1.0
var _height_fn: Callable
var _splat_fn: Callable
## Pending instances per kit name: [Transform3D, custom Color], flushed as chunked MultiMeshes.
var _instances := {}

# --- kit ---------------------------------------------------------------------------------------


func _prepare_kit() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for d in ["meshes", "materials", "terrain"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ENV + d))
	for kit_name: String in KIT:
		var spec: Dictionary = KIT[kit_name]
		var scene: PackedScene = load("%s%s/%s.glb" % [ENV, spec["dir"], kit_name])
		var inst := scene.instantiate()
		var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: ArrayMesh = mi.mesh.duplicate()
		var src := mi.get_active_material(0) as BaseMaterial3D
		var mat := ShaderMaterial.new()
		mat.shader = ENV_TOON
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("use_instance_custom", true)
		mat.set_shader_parameter("shadow_tint", DAY["shadow_tint"])
		if spec.has("wind"):
			var h: float = mesh.get_aabb().size.y
			mat.set_shader_parameter("wind_strength", spec["wind"] * h / 4.0)
			mat.set_shader_parameter("wind_height", h)
			# foliage: soft wide bands, darker towards the bottom of the canopy for volume
			mat.set_shader_parameter("band_softness", 0.2)
			mat.set_shader_parameter("band_threshold", 0.1)
			mat.set_shader_parameter("rim_strength", 0.15)
			mat.set_shader_parameter("contact_height", h * 0.85)
			mat.set_shader_parameter("contact_darkness", 0.38)
			mat.set_shader_parameter("albedo_tint", Color(0.9, 0.9, 0.88))
		else:
			mat.set_shader_parameter("contact_height", 0.45)
			mat.set_shader_parameter("contact_darkness", 0.22)
		if spec.get("fade", false):
			mat.set_shader_parameter("cam_fade_near", 10.0)
		if spec.get("cards", false):
			mat.set_shader_parameter("alpha_scissor", 0.5)
		if spec["dir"] == "rocks":
			mat.set_shader_parameter("albedo_tint", Color(0.78, 0.76, 0.8))
		if spec.get("outline", false):
			var ink := ShaderMaterial.new()
			ink.shader = OUTLINE
			ink.set_shader_parameter("ink_color", Color("#2a2233"))
			ink.set_shader_parameter("thickness_px", 1.2)
			mat.next_pass = ink
		var mat_path := "%smaterials/%s.tres" % [ENV, kit_name]
		ResourceSaver.save(mat, mat_path)
		mesh.surface_set_material(0, load(mat_path))
		var mesh_path := "%smeshes/%s.res" % [ENV, kit_name]
		ResourceSaver.save(mesh, mesh_path)
		meshes[kit_name] = load(mesh_path)
		aabbs[kit_name] = mesh.get_aabb()
		inst.free()
	_prepare_cards()


func _prepare_cards() -> void:
	# one quad, both faces, 1 x 1 m, base at y = 0, facing +Z (the gameplay camera never turns);
	# crossed quads read as "X" stars from the 50° camera. Normals up: lit like the ground.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0.0]:
		var ax := Vector3(cos(angle), 0, sin(angle)) * 0.5
		var quad := [-ax, ax, ax + Vector3.UP, -ax + Vector3.UP]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for tri in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
			for k in tri:
				st.set_normal(Vector3.UP)
				st.set_uv(uvs[k])
				st.add_vertex(quad[k])
	card_mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = ENV_TOON
	mat.set_shader_parameter("albedo_tex", load(ENV + "textures/grass_cards.png"))
	mat.set_shader_parameter("use_instance_custom", true)
	mat.set_shader_parameter("atlas_grid", Vector2(4, 2))
	mat.set_shader_parameter("alpha_scissor", 0.4)
	mat.set_shader_parameter("wind_strength", 0.07)
	mat.set_shader_parameter("wind_height", 1.0)
	mat.set_shader_parameter("rim_strength", 0.0)
	mat.set_shader_parameter("contact_height", 0.55)
	mat.set_shader_parameter("contact_darkness", 0.3)
	mat.set_shader_parameter("shadow_tint", DAY["shadow_tint"])
	ResourceSaver.save(mat, ENV + "materials/grass_cards.tres")
	card_mesh.surface_set_material(0, load(ENV + "materials/grass_cards.tres"))
	ResourceSaver.save(card_mesh, ENV + "meshes/grass_card.res")
	card_mesh = load(ENV + "meshes/grass_card.res")
	var reed_mat: ShaderMaterial = mat.duplicate()
	reed_mat.set_shader_parameter("cam_fade_near", 10.0)
	ResourceSaver.save(reed_mat, ENV + "materials/reed_cards.tres")
	var reeds: ArrayMesh = card_mesh.duplicate()
	reeds.surface_set_material(0, load(ENV + "materials/reed_cards.tres"))
	ResourceSaver.save(reeds, ENV + "meshes/reed_card.res")
	reed_mesh = load(ENV + "meshes/reed_card.res")


# --- scene skeleton ----------------------------------------------------------------------------


func _begin(scene_name: String) -> void:
	scene_root = Node3D.new()
	scene_root.name = scene_name
	occupied.clear()
	paths.clear()
	clearings.clear()
	fields.clear()
	tint_bias = 0.0
	bright_scale = 1.0
	grass_tint = Color(0.86, 0.95, 0.76)
	for n in ["Spawns", "Exits", "Anchors", "Visuals"]:
		_add(scene_root, Node3D.new(), n)
	var walkable := StaticBody3D.new()
	_add(scene_root, walkable, "Walkable")
	walkable.collision_mask = 0
	obstacles = StaticBody3D.new()
	_add(walkable, obstacles, "Obstacles")
	obstacles.collision_mask = 0


func _add(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = scene_root
	return node


func _group(group_name: String) -> Node3D:
	var visuals := scene_root.get_node("Visuals")
	if visuals.has_node(group_name):
		return visuals.get_node(group_name)
	return _add(visuals, Node3D.new(), group_name)


func _save(file_name: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	assert(err == OK)
	ResourceSaver.save(packed, OUT + file_name)
	print("saved ", OUT + file_name, " nodes=", _count(scene_root))
	scene_root.free()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _marker(
	group: String, marker_name: String, at: Vector3, facing: Vector3 = Vector3.FORWARD
) -> void:
	var m := Marker3D.new()
	_add(scene_root.get_node(group), m, marker_name)
	m.position = Vector3(at.x, _height(at.x, at.z), at.z)
	# Fern looks along the marker's -Z
	m.rotation.y = atan2(-facing.x, -facing.z)


func _exit(exit_name: String, at: Vector3, size: Vector3, to: String, spawn: String) -> void:
	var area := Area3D.new()
	_add(scene_root.get_node("Exits"), area, exit_name)
	area.position = Vector3(at.x, _height(at.x, at.z) + size.y * 0.5, at.z)
	area.collision_layer = 8  # layer 4
	area.collision_mask = 2  # the player (game/world/explore/player.gd)
	area.monitorable = false
	area.set_meta("to", to)
	area.set_meta("spawn", spawn)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_add(area, shape, "Shape")


func _borders(half: float) -> void:
	var body := StaticBody3D.new()
	_add(scene_root.get_node("Walkable"), body, "Borders")
	body.collision_mask = 0
	for side in 4:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var along := side < 2
		box.size = Vector3(half * 2 + 2, 8, 1) if along else Vector3(1, 8, half * 2 + 2)
		shape.shape = box
		var s := -1.0 if side % 2 == 0 else 1.0
		shape.position = (
			Vector3(0, 3, s * (half + 0.5)) if along else Vector3(s * (half + 0.5), 3, 0)
		)
		_add(body, shape, "Wall%d" % side)


func _environment(
	fog: bool,
	sun_yaw: float,
	sun_pitch: float,
	energy_scale: float = 1.0,
	ambient_scale: float = 1.0,
	mist: Dictionary = {}
) -> void:
	var holder := Node3D.new()
	_add(scene_root, holder, "Environment")
	var we := WorldEnvironment.new()
	_add(holder, we, "WorldEnvironment")
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = DAY["sky_top"]
	sky_mat.sky_horizon_color = DAY["sky_horizon"]
	sky_mat.ground_horizon_color = DAY["sky_horizon"]
	sky_mat.ground_bottom_color = DAY["ground_bottom"]
	sky_mat.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = DAY["ambient"]
	env.ambient_light_energy = DAY["ambient_energy"] * ambient_scale
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.adjustment_enabled = true
	env.adjustment_brightness = DAY["brightness"]
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.1
	if fog:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color("#b9bfd6")
		env.fog_density = 0.0035
		env.fog_sky_affect = 0.0
		env.fog_height = 0.6
		env.fog_height_density = 0.03
		# heavier, lower ground mist (Lantern Mire): colour, density, height
		if not mist.is_empty():
			env.fog_light_color = mist["color"]
			env.fog_density = mist["density"]
			env.fog_height = mist["height"]
			env.fog_height_density = mist["height_density"]
	else:
		env.fog_enabled = true
		env.fog_light_color = DAY["haze"]
		env.fog_density = 0.0045
		env.fog_sky_affect = 0.0
	we.environment = env
	var sun := DirectionalLight3D.new()
	_add(holder, sun, "Sun")
	sun.rotation_degrees = Vector3(sun_pitch, sun_yaw, 0)
	sun.light_color = DAY["sun"]
	sun.light_energy = DAY["sun_energy"] * energy_scale
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 0.6
	# one orthogonal map over 32 m: crisp enough at the 14 m camera, and casters are drawn once
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 32.0
	sun.light_bake_mode = Light3D.BAKE_STATIC


# --- terrain -----------------------------------------------------------------------------------


func _height(x: float, z: float) -> float:
	return _height_fn.call(x, z)


func _terrain(label: String, half: int, collide_half: int, splat_px: int) -> void:
	var dir := "%sterrain/%s/" % [ENV, label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	# splat map: R dirt, G cobble, B forest floor
	var img := Image.create(splat_px, splat_px, false, Image.FORMAT_RGBA8)
	for j in splat_px:
		for i in splat_px:
			var x := -half + (i + 0.5) * 2.0 * half / splat_px
			var z := -half + (j + 0.5) * 2.0 * half / splat_px
			img.set_pixel(i, j, _splat_fn.call(x, z))
	var splat := ImageTexture.create_from_image(img)
	ResourceSaver.save(splat, dir + "splat.res", ResourceSaver.FLAG_COMPRESS)
	img.save_png(ProjectSettings.globalize_path("res://art/source/env/%s_splat.png" % label))
	var mat := ShaderMaterial.new()
	mat.shader = ENV_TERRAIN
	mat.set_shader_parameter("splat_tex", load(dir + "splat.res"))
	for t in ["grass", "dirt", "cobble", "forest"]:
		mat.set_shader_parameter(t + "_tex", load("%stextures/ground_%s.jpg" % [ENV, t]))
	mat.set_shader_parameter("splat_rect", Vector4(-half, -half, half * 2, half * 2))
	mat.set_shader_parameter("shadow_tint", DAY["shadow_tint"])
	# pull the golden grass towards sage green so paths, flowers and props read against it
	mat.set_shader_parameter("grass_tint", grass_tint)
	ResourceSaver.save(mat, dir + "ground.tres")
	mat = load(dir + "ground.tres")
	# heights on a 1 m grid
	var n := half * 2
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			hs[j * (n + 1) + i] = _height(i - half, j - half)
	var ground := _group("Ground")
	var chunk := 30
	for cj in range(0, n, chunk):
		for ci in range(0, n, chunk):
			var mesh := _terrain_chunk(
				hs, n, half, ci, cj, mini(chunk, n - ci), mini(chunk, n - cj)
			)
			mesh.surface_set_material(0, mat)
			var path := "%sground_%d_%d.res" % [dir, ci / chunk, cj / chunk]
			ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
			var mi := MeshInstance3D.new()
			_add(ground, mi, "Ground_%d_%d" % [ci / chunk, cj / chunk])
			mi.mesh = load(path)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# collision: height map over the walkable area (+ margin)
	var w := collide_half * 2 + 1
	var data := PackedFloat32Array()
	data.resize(w * w)
	for j in w:
		for i in w:
			data[j * w + i] = _height(i - collide_half, j - collide_half)
	var hm := HeightMapShape3D.new()
	hm.map_width = w
	hm.map_depth = w
	hm.map_data = data
	var shape := CollisionShape3D.new()
	shape.shape = hm
	_add(scene_root.get_node("Walkable"), shape, "Ground")


func _terrain_chunk(
	hs: PackedFloat32Array, n: int, half: int, ci: int, cj: int, cw: int, ch: int
) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in ch + 1:
		for i in cw + 1:
			var gi := ci + i
			var gj := cj + j
			verts.append(Vector3(gi - half, hs[gj * (n + 1) + gi], gj - half))
			var hl := hs[gj * (n + 1) + maxi(gi - 1, 0)]
			var hr := hs[gj * (n + 1) + mini(gi + 1, n)]
			var hd := hs[maxi(gj - 1, 0) * (n + 1) + gi]
			var hu := hs[mini(gj + 1, n) * (n + 1) + gi]
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


# --- placement helpers -------------------------------------------------------------------------


func _place(
	kit_name: String, at: Vector2, yaw: float, scale: float = 1.0, collide: bool = true
) -> void:
	var y := _height(at.x, at.y) - 0.05
	var basis := (
		Basis(Vector3.UP, yaw + deg_to_rad(KIT.get(kit_name, {}).get("front_yaw", 0.0)))
		. scaled(Vector3.ONE * scale)
	)
	var xf := Transform3D(basis, Vector3(at.x, y, at.y))
	var tint := rng.randf_range(-0.35, 0.35) + tint_bias
	var bright := rng.randf_range(0.93, 1.05) * bright_scale
	_instances.get_or_add(kit_name, []).append([xf, Color(tint, bright, rng.randf(), 0.0)])
	if collide:
		_collider(kit_name, xf)
	var r: float = maxf(aabbs[kit_name].size.x, aabbs[kit_name].size.z) * 0.5 * scale
	occupied.append([at, r])


func _card(
	at: Vector2,
	cell: int,
	size: float,
	height_scale: float = 1.0,
	tint: float = 0.0,
	bucket: String = "_cards"
) -> void:
	var y := _height(at.x, at.y) - 0.03
	# lean the top away from the camera so the card faces the 50° view instead of showing its edge
	var facing := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, -0.5)
	var basis := facing.scaled(Vector3(size, size * height_scale, size))
	var xf := Transform3D(basis, Vector3(at.x, y, at.y))
	_instances.get_or_add(bucket, []).append(
		[
			xf,
			Color(
				tint + rng.randf_range(-0.15, 0.15), rng.randf_range(0.86, 0.98), rng.randf(), cell
			)
		]
	)


func _flush(chunk: float = 24.0) -> void:
	for kit_name: String in _instances:
		# "_cards" grass and flowers, "_reeds" tall reeds with the camera cut-out
		var is_card := kit_name.begins_with("_")
		var mesh: Mesh = (
			(card_mesh if kit_name == "_cards" else reed_mesh) if is_card else meshes[kit_name]
		)
		var parent := _group("Grass" if is_card else KIT[kit_name]["dir"].capitalize())
		var groups := {}
		for it in _instances[kit_name]:
			var o: Vector3 = (it[0] as Transform3D).origin
			groups.get_or_add(Vector2i(floori(o.x / chunk), floori(o.z / chunk)), []).append(it)
		for key: Vector2i in groups:
			var items: Array = groups[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = items.size()
			for i in items.size():
				mm.set_instance_transform(i, items[i][0])
				mm.set_instance_custom_data(i, items[i][1])
			var mmi := MultiMeshInstance3D.new()
			var label := kit_name.trim_prefix("_").capitalize() if is_card else kit_name
			_add(parent, mmi, "%s_%d_%d" % [label, key.x + 50, key.y + 50])
			mmi.multimesh = mm
			if is_card:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instances.clear()


func _collider(kit_name: String, xf: Transform3D) -> void:
	var spec: Dictionary = KIT[kit_name]
	var kind: String = spec["col"]
	if kind == "":
		return
	var ab: AABB = aabbs[kit_name]
	var s := xf.basis.get_scale().x
	var rot := xf.basis.orthonormalized()
	var shape := CollisionShape3D.new()
	var centre := ab.get_center() * s
	match kind:
		"box":
			var box := BoxShape3D.new()
			box.size = Vector3(ab.size.x * s * 0.9, minf(ab.size.y * s, 4.0), ab.size.z * s * 0.9)
			shape.shape = box
			shape.transform = Transform3D(
				rot, xf.origin + rot * Vector3(centre.x, box.size.y * 0.5, centre.z)
			)
		"cyl", "trunk", "post":
			var cyl := CylinderShape3D.new()
			var r: float = maxf(ab.size.x, ab.size.z) * s * spec.get("r", 0.4)
			if kind == "trunk":
				r = 0.32 * s
			elif kind == "post":
				r = 0.18
			cyl.radius = r
			cyl.height = 3.0
			shape.shape = cyl
			var off := Vector3.ZERO if kind != "cyl" else rot * Vector3(centre.x, 0, centre.z)
			shape.transform = Transform3D(Basis.IDENTITY, xf.origin + off + Vector3(0, 1.5, 0))
		"mesh":
			shape.shape = (meshes[kit_name] as Mesh).create_trimesh_shape()
			shape.transform = xf
	_add(obstacles, shape, "%s_%d" % [kit_name, obstacles.get_child_count()])


func _free_at(p: Vector2, r: float) -> bool:
	for o in occupied:
		if p.distance_to(o[0]) < r + o[1]:
			return false
	return true


func _path_dist(p: Vector2) -> float:
	var best := 1e9
	for path in paths:
		var pts: PackedVector2Array = path[0]
		for k in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
			best = minf(best, p.distance_to(q) - path[1])
	return best


func _in_field(p: Vector2, margin: float = 0.0) -> bool:
	for f: Rect2 in fields:
		if f.grow(margin).has_point(p):
			return true
	return false


func _fence_line(a: Vector2, b: Vector2, gap_every: int = 0) -> void:
	var seg: float = aabbs["fence"].size.x
	var d := b - a
	var count := maxi(1, roundi(d.length() / seg))
	var yaw := atan2(-d.y, d.x)
	for k in count:
		if gap_every > 0 and k % gap_every == gap_every - 1:
			continue
		var c := a + d * ((k + 0.5) / count)
		_place("fence", c, yaw + rng.randf_range(-0.04, 0.04), d.length() / count / seg)


func _face(from: Vector2, to: Vector2) -> float:
	# yaw that turns a model's +Z front from `from` towards `to`
	var d := to - from
	return atan2(d.x, d.y)


func _backdrop(at: Vector3, width: float) -> void:
	var tex: Texture2D = load(ENV + "textures/backdrop_cloister.png")
	var quad := QuadMesh.new()
	quad.size = Vector2(width, width * tex.get_height() / tex.get_width())
	var mat := ShaderMaterial.new()
	mat.shader = ENV_BACKDROP
	mat.set_shader_parameter("tex", tex)
	quad.material = mat
	var mi := MeshInstance3D.new()
	_add(_group("Backdrop"), mi, "Cloister")
	mi.mesh = quad
	mi.position = at + Vector3(0, quad.size.y * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
