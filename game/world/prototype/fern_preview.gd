extends Node3D
## Fern character preview: toon + outline on every surface, animation cycling, day/night lighting.
##
## Keys: Space / Right = next clip, Left = previous clip, 1-4 = idle/walk/run/cast,
##       N = toggle day/night, C = toggle close-up, Q/E = turn Fern.
## Screenshot mode (used by tools to grab real frames under xvfb):
##   godot --path . --rendering-driver opengl3 \
##     res://game/world/prototype/fern_preview.tscn -- --shots
## writes art/source/fern/shot_*.jpg and quits.

const TOON_SHADER: Shader = preload("res://assets/shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/outline.gdshader")
const LOOPING := ["idle", "walk", "run"]
const SHOT_DIR := "res://art/source/fern/"

const DAY := {
	"sun_color": Color("#ffe2b0"),
	"sun_energy": 0.72,
	"sun_pitch": -35.0,
	"sun_yaw": -55.0,
	"sky_top": Color("#8ea4dd"),
	"sky_horizon": Color("#e9d9ee"),
	"ground_bottom": Color("#6f7f6a"),
	"ambient": Color("#a9b8d8"),
	"ambient_energy": 0.32,
	"shadow_tint": Color("#7f93b8"),
	"ink": Color("#2a2233"),
	"grass": Color("#93b56c"),
	"path": Color("#d2b48a"),
}
const NIGHT := {
	"sun_color": Color("#bcd0ff"),
	"sun_energy": 0.45,
	"sun_pitch": -48.0,
	"sun_yaw": 60.0,
	"sky_top": Color("#0d1626"),
	"sky_horizon": Color("#2b3a55"),
	"ground_bottom": Color("#0d1220"),
	"ambient": Color("#1a2433"),
	"ambient_energy": 1.1,
	"shadow_tint": Color("#2d3d5e"),
	"ink": Color("#0d1220"),
	"grass": Color("#4f6b5e"),
	"path": Color("#6f7186"),
}

@export var camera_pitch_deg := 50.0
@export var camera_distance := 4.6
@export var close_distance := 1.9
## Fern faces -Z (Godot forward); turn her toward the camera for the preview.
@export var fern_yaw_deg := 150.0

var _anim: AnimationPlayer
var _clips: PackedStringArray = []
var _clip_index := 0
var _night := false
var _close := false
var _toon_materials: Array[ShaderMaterial] = []
var _outline_materials: Array[ShaderMaterial] = []

@onready var fern: Node3D = $Fern
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var env: WorldEnvironment = $WorldEnvironment
@onready var lantern: OmniLight3D = $Lantern


func _ready() -> void:
	fern.rotation_degrees.y = fern_yaw_deg
	_apply_toon(fern)
	_apply_toon_ground()
	_anim = fern.find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer
	if _anim:
		for clip_name in _anim.get_animation_list():
			if clip_name == "RESET":
				continue
			_clips.append(clip_name)
			var anim := _anim.get_animation(clip_name)
			anim.loop_mode = Animation.LOOP_LINEAR if clip_name in LOOPING else Animation.LOOP_NONE
		_anim.animation_finished.connect(_on_animation_finished)
		play_clip("idle")
	set_night(false)
	_update_camera()
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots()


func _apply_toon(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var toon := ShaderMaterial.new()
			toon.shader = TOON_SHADER
			if src is BaseMaterial3D:
				toon.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
				toon.set_shader_parameter("albedo_tint", (src as BaseMaterial3D).albedo_color)
			var outline := ShaderMaterial.new()
			outline.shader = OUTLINE_SHADER
			toon.next_pass = outline
			mi.set_surface_override_material(s, toon)
			_toon_materials.append(toon)
			_outline_materials.append(outline)


func _apply_toon_ground() -> void:
	for mi: MeshInstance3D in [$Ground, $Path]:
		var toon := ShaderMaterial.new()
		toon.shader = TOON_SHADER
		toon.set_shader_parameter("rim_strength", 0.0)
		mi.material_override = toon
		_toon_materials.append(toon)


func play_clip(clip_name: String) -> void:
	if not _anim or not _anim.has_animation(clip_name):
		return
	_clip_index = _clips.find(clip_name)
	_anim.play(clip_name, 0.2)


func next_clip(step: int = 1) -> void:
	if _clips.is_empty():
		return
	_clip_index = posmod(_clip_index + step, _clips.size())
	play_clip(_clips[_clip_index])


func _on_animation_finished(clip_name: StringName) -> void:
	if not (String(clip_name) in LOOPING):
		play_clip("idle")


func set_night(on: bool) -> void:
	_night = on
	var p: Dictionary = NIGHT if on else DAY
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.rotation_degrees = Vector3(p.sun_pitch, p.sun_yaw, 0.0)
	var sky_mat := env.environment.sky.sky_material as ProceduralSkyMaterial
	sky_mat.sky_top_color = p.sky_top
	sky_mat.sky_horizon_color = p.sky_horizon
	sky_mat.ground_horizon_color = p.sky_horizon
	sky_mat.ground_bottom_color = p.ground_bottom
	env.environment.ambient_light_color = p.ambient
	env.environment.ambient_light_energy = p.ambient_energy
	lantern.visible = on
	for m in _toon_materials:
		m.set_shader_parameter("shadow_tint", p.shadow_tint)
	for m in _outline_materials:
		m.set_shader_parameter("ink_color", p.ink)
	($Ground.material_override as ShaderMaterial).set_shader_parameter("albedo_tint", p.grass)
	($Path.material_override as ShaderMaterial).set_shader_parameter("albedo_tint", p.path)


func _update_camera() -> void:
	var target := fern.global_position + Vector3(0, 1.32 if _close else 0.8, 0)
	var dist := close_distance if _close else camera_distance
	var pitch := deg_to_rad(18.0 if _close else camera_pitch_deg)
	camera.global_position = target + Vector3(0.0, sin(pitch), cos(pitch)) * dist
	camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE, KEY_RIGHT:
			next_clip(1)
		KEY_LEFT:
			next_clip(-1)
		KEY_1:
			play_clip("idle")
		KEY_2:
			play_clip("walk")
		KEY_3:
			play_clip("run")
		KEY_4:
			play_clip("cast")
		KEY_N:
			set_night(not _night)
		KEY_C:
			_close = not _close
			_update_camera()
		KEY_Q:
			fern.rotate_y(deg_to_rad(-15))
		KEY_E:
			fern.rotate_y(deg_to_rad(15))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + file_name)
	var err := img.save_jpg(path.get_basename() + ".jpg", 0.88)
	print("shot ", path, " ", img.get_size(), " err=", err)


func _seek(clip_name: String, t: float) -> void:
	_anim.play(clip_name)
	_anim.seek(t, true)
	_anim.pause()


func _take_shots() -> void:
	await _wait(1.0)
	_seek("idle", 1.0)
	await _wait(0.2)
	await _shot("shot_day_idle_34.png")
	_close = true
	_update_camera()
	await _wait(0.2)
	await _shot("shot_day_closeup.png")
	_close = false
	_update_camera()
	_seek("walk", 0.33)
	await _wait(0.2)
	await _shot("shot_day_walk.png")
	_seek("cast", 1.7)
	await _wait(0.2)
	await _shot("shot_day_cast.png")
	# what the player mostly sees: her back, walking away from the camera
	fern.rotation_degrees.y = 25.0
	_seek("walk", 0.6)
	await _wait(0.2)
	await _shot("shot_day_walk_back.png")
	fern.rotation_degrees.y = fern_yaw_deg
	set_night(true)
	_seek("cast", 1.7)
	await _wait(0.3)
	await _shot("shot_night_cast.png")
	_seek("idle", 1.0)
	_close = true
	_update_camera()
	await _wait(0.2)
	await _shot("shot_night_closeup.png")
	get_tree().quit()
