extends Node3D
## Fern character preview: toon + outline on every surface, animation cycling, day/night lighting.
##
## Keys: Space / Right = next clip, Left = previous clip, 1-4 = idle/walk/run/cast,
##       N = toggle day/night, C = toggle close-up, Q/E = turn Fern.
## Keys 5-7 = hit/death/victory (when the model has them), S = toggle the staff.
## Screenshot mode (used by tools to grab real frames under xvfb):
##   godot --path . --rendering-driver opengl3 \
##     res://game/world/prototype/fern_preview.tscn -- --shots \
##     [--shots-dir=res://art/source/fern_v1/] [--no-springs]
## writes shot_*.jpg into the shots dir and quits.

const TOON_SHADER: Shader = preload("res://assets/shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/outline.gdshader")
const LOOPING := ["idle", "walk", "run"]
const DEFAULT_SHOT_DIR := "res://art/source/fern_v1/"

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
var _shot_dir := DEFAULT_SHOT_DIR

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
		KEY_5:
			play_clip("hit")
		KEY_6:
			play_clip("death")
		KEY_7:
			play_clip("victory")
		KEY_S:
			var staff := fern.find_child("Staff", true, false) as Node3D
			if staff:
				staff.visible = not staff.visible
		KEY_N:
			set_night(not _night)
		KEY_C:
			_close = not _close
			_update_camera()
		KEY_Q:
			fern.rotate_y(deg_to_rad(-15))
			_reset_springs()
		KEY_E:
			fern.rotate_y(deg_to_rad(15))
			_reset_springs()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_shot_dir + file_name)
	var err := img.save_jpg(path.get_basename() + ".jpg", 0.88)
	print("shot ", path, " ", img.get_size(), " err=", err)


func _seek(clip_name: String, t: float) -> void:
	_anim.play(clip_name)
	_anim.seek(t, true)
	_anim.pause()


func _reset_springs() -> void:
	# after a teleport-like turn the spring bones would whip around for a while: start them afresh
	for sim in fern.find_children("*", "SpringBoneSimulator3D", true, false):
		(sim as SpringBoneSimulator3D).reset()


func _play_live(clip_name: String, seconds: float) -> void:
	# real playback so the spring bones (hair, coat tails) are in motion on the frame
	_anim.play(clip_name)
	await _wait(seconds)


func _take_shots() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_shot_dir = arg.trim_prefix("--shots-dir=")
		if arg == "--no-springs":  # A/B check of the secondary motion
			for sim in fern.find_children("*", "SpringBoneSimulator3D", true, false):
				(sim as SkeletonModifier3D).active = false
	await _play_live("idle", 2.0)
	await _shot("shot_day_idle_34.png")
	_close = true
	_update_camera()
	await _wait(0.3)
	await _shot("shot_day_closeup.png")
	_close = false
	_update_camera()
	await _play_live("walk", 1.33)
	await _shot("shot_day_walk.png")
	# what the player mostly sees: her back, walking away from the camera
	fern.rotation_degrees.y = 25.0
	_reset_springs()
	await _play_live("walk", 1.6)
	await _shot("shot_day_walk_back.png")
	await _play_live("run", 1.2)
	await _shot("shot_day_run_back.png")
	fern.rotation_degrees.y = fern_yaw_deg
	_reset_springs()
	_anim.play("cast")
	await _wait(1.0)  # staff raised: the readable moment of the cast
	await _shot("shot_day_cast.png")
	set_night(true)
	_anim.play("cast")
	await _wait(1.0)  # staff raised: the readable moment of the cast
	await _shot("shot_night_cast.png")
	_close = true
	_update_camera()
	_reset_springs()
	await _play_live("idle", 1.5)
	await _shot("shot_night_closeup.png")
	get_tree().quit()
