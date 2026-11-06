extends Node3D
## Side-by-side review of GLB models at the gameplay camera (50° pitch, CameraRig formula), lit like
## the day locations. Used for the Tripo vs Meshy A/B test (art/source/enemies/AB_TEST.md).
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://game/world/prototype/ab_preview.tscn -- \
##     --models=res://a.glb,res://b.glb --mode=env|toon --distance=11 --spacing=6 \
##     --out=res://art/source/enemies/ab_birch_game.jpg [--yaw=0] [--height=7]
## --mode=env : env_toon material as in location_builder.gd (foliage settings when --foliage)
## --mode=toon: toon + ink outline (characters / creatures, Toon.apply)
## --height   : rescale every model to this height (metres), 0 = keep

const ENV_TOON: Shader = preload("res://assets/shaders/env_toon.gdshader")
const SUN := Color("#ffe2b0")

var _models: PackedStringArray = []
var _mode := "env"
var _distance := 11.0
var _spacing := 6.0
var _out := ""
var _yaw := 0.0
var _height := 0.0
var _foliage := false
var _pitch := 50.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--models="):
			_models = v.split(",")
		elif a.begins_with("--mode="):
			_mode = v
		elif a.begins_with("--distance="):
			_distance = v.to_float()
		elif a.begins_with("--spacing="):
			_spacing = v.to_float()
		elif a.begins_with("--out="):
			_out = v
		elif a.begins_with("--yaw="):
			_yaw = v.to_float()
		elif a.begins_with("--height="):
			_height = v.to_float()
		elif a.begins_with("--pitch="):
			_pitch = v.to_float()
		elif a == "--foliage":
			_foliage = true
	_stage()
	var x0 := -_spacing * (_models.size() - 1) * 0.5
	for i in _models.size():
		var inst: Node3D = (load(_models[i]) as PackedScene).instantiate()
		add_child(inst)
		inst.position = Vector3(x0 + i * _spacing, 0, 0)
		inst.rotation_degrees.y = _yaw
		if _height > 0.0:
			var ab := _aabb(inst)
			inst.scale = Vector3.ONE * (_height / maxf(ab.size.y, 0.01))
		# stand on the ground, centred on its slot (raw generator outputs are centred on the origin)
		var ab2 := _aabb(inst)
		inst.position += Vector3(
			inst.position.x - ab2.get_center().x, -ab2.position.y, -ab2.get_center().z
		)
		if _mode == "toon":
			Toon.apply(inst)
		else:
			_env_material(inst)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var pitch := deg_to_rad(_pitch)
	var focus := Vector3(0, 1.0 if _height <= 0.0 else _height * 0.35, 0)
	cam.position = focus + Vector3(0.0, sin(pitch) * _distance + 0.8, cos(pitch) * _distance)
	cam.rotation = Vector3(-pitch, 0.0, 0.0)
	cam.current = true
	if _out != "":
		await _frames(12)
		var img := get_viewport().get_texture().get_image()
		img.save_jpg(ProjectSettings.globalize_path(_out), 0.9)
		print("saved ", _out)
		get_tree().quit()


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb() if m.is_inside_tree() else m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _env_material(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.get_active_material(0) as BaseMaterial3D
		var mat := ShaderMaterial.new()
		mat.shader = ENV_TOON
		if src:
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("shadow_tint", Color("#8fa0c4"))
		if _foliage:
			var h := mi.get_aabb().size.y
			mat.set_shader_parameter("band_softness", 0.2)
			mat.set_shader_parameter("band_threshold", 0.1)
			mat.set_shader_parameter("rim_strength", 0.15)
			mat.set_shader_parameter("contact_height", h * 0.85)
			mat.set_shader_parameter("contact_darkness", 0.38)
			mat.set_shader_parameter("albedo_tint", Color(0.9, 0.9, 0.88))
			if (
				src
				and src.albedo_texture
				and src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			):
				mat.set_shader_parameter("alpha_scissor", 0.5)
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)


func _stage() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#8ea4dd")
	sky_mat.sky_horizon_color = Color("#efdcd8")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a9b8d8")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -62, 0)
	sun.light_color = SUN
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	var gm := ShaderMaterial.new()
	gm.shader = ENV_TOON
	gm.set_shader_parameter("albedo_tint", Color("#93b56c"))
	gm.set_shader_parameter("shadow_tint", Color("#8fa0c4"))
	plane.material = gm
	ground.mesh = plane
	add_child(ground)


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
