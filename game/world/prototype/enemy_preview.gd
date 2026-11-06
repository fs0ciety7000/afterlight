extends Node3D
## Enemy preview (Milestone 3): every enemy of assets/models/enemies/ in a Whispering Wood clearing,
## toon + ink outline (Toon.apply), seen from the gameplay camera (50° pitch, 11 m, as CameraRig).
## The elite mist_wolf_alpha is the mist wolf at 1.3x with a darker tint (no separate model).
##
##   godot --path . res://game/world/prototype/enemy_preview.tscn
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://game/world/prototype/enemy_preview.tscn -- --shots   (art/source/enemies/shot_*.jpg)
## Keys: Space / Right = next clip, Left = previous, 1-6 = idle run attack cast hit death,
##       Z = camera distance 11 m / 6 m, Q / E = turn the line-up.

const MODELS := "res://assets/models/enemies/%s/%s.glb"
const LOCATION := "res://game/world/locations/whispering_wood.tscn"
const SHOT_DIR := "res://art/source/enemies/"
const CLIPS := ["idle", "run", "attack", "cast", "hit", "death"]
const LOOPING := ["idle", "run"]
const CENTRE := Vector3(-4.0, 0.0, -10.0)  # clearing of the wood (encounter anchor area)
const PITCH_DEG := 50.0
## id, model, x offset, scale, tint (alpha variant)
const LINEUP := [
	["mist_wolf", "mist_wolf", -4.2, 1.0, Color(1, 1, 1)],
	["mist_wolf_alpha", "mist_wolf", -1.6, 1.3, Color(0.62, 0.64, 0.74)],
	["wandering_lantern", "wandering_lantern", 0.8, 1.0, Color(1, 1, 1)],
	["stone_sentinel", "stone_sentinel", 3.0, 1.0, Color(1, 1, 1)],
	["morvaine", "morvaine", 5.4, 1.0, Color(1, 1, 1)],
]

var _actors: Array[Node3D] = []
var _players: Array[AnimationPlayer] = []
var _clip := 0
var _camera: Camera3D
var _distance := 11.0
var _focus_x := 0.6
var _pivot: Node3D


func _ready() -> void:
	var loc := (load(LOCATION) as PackedScene).instantiate()
	add_child(loc)
	# let the physics server register the location's collisions before ray-casting the ground
	await get_tree().physics_frame
	await get_tree().physics_frame
	_pivot = Node3D.new()
	add_child(_pivot)
	_pivot.position = _ground(CENTRE)
	for row in LINEUP:
		var inst: Node3D = (load(MODELS % [row[1], row[1]]) as PackedScene).instantiate()
		_pivot.add_child(inst)
		inst.name = row[0]
		inst.position = Vector3(row[2], 0, 0)
		inst.position.y = _ground(_pivot.position + inst.position).y - _pivot.position.y
		inst.scale = Vector3.ONE * float(row[3])
		inst.rotation_degrees.y = 200.0  # facing -Z: turn towards the camera, slightly 3/4
		Toon.apply(inst)
		if row[4] != Color(1, 1, 1):
			_tint(inst, row[4])
		_actors.append(inst)
		var players := inst.find_children("*", "AnimationPlayer", true, false)
		var ap: AnimationPlayer = players[0] if not players.is_empty() else null
		_players.append(ap)
		if ap:
			for n in LOOPING:
				if ap.has_animation(n):
					ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_camera.current = true
	_place_camera()
	_play(0)
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots()


func _tint(root: Node, c: Color) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s) as ShaderMaterial
			if mat:
				mat.set_shader_parameter("albedo_tint", c)


func _ground(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 40.0, p + Vector3.DOWN * 40.0, 1)
	var hit := space.intersect_ray(q)
	return hit["position"] if hit else p


func _place_camera() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	var focus := _pivot.position + Vector3(_focus_x, 0.0, 0.0)
	_camera.position = focus + Vector3(0.0, sin(pitch) * _distance + 0.8, cos(pitch) * _distance)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)


func _play(i: int) -> void:
	_clip = wrapi(i, 0, CLIPS.size())
	var clip: String = CLIPS[_clip]
	for ap in _players:
		if ap == null:
			continue
		ap.play(clip if ap.has_animation(clip) else "idle")
	print("clip: ", clip)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key := (event as InputEventKey).keycode
	match key:
		KEY_SPACE, KEY_RIGHT:
			_play(_clip + 1)
		KEY_LEFT:
			_play(_clip - 1)
		KEY_Z:
			_distance = 6.0 if _distance > 8.0 else 11.0
			_place_camera()
		KEY_Q:
			_pivot.rotation.y += deg_to_rad(15)
		KEY_E:
			_pivot.rotation.y -= deg_to_rad(15)
		_:
			if key >= KEY_1 and key <= KEY_6:
				_play(key - KEY_1)


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _shot(file_name: String) -> void:
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(ProjectSettings.globalize_path(SHOT_DIR + file_name), 0.88)
	print("saved ", file_name)


func _take_shots() -> void:
	await _frames(10)
	# line-up at the gameplay camera, one frame per clip at a telling moment (fraction of the clip)
	var moments := {
		"idle": 0.3,
		"run": 0.35,
		"attack": 0.5,
		"cast": 0.45,
		"hit": 0.25,
		"death": 1.0,
	}
	# 11 m line-up, 6 m on the wolves and lantern, 6 m on the sentinel and Morvaine ("_6m_right")
	for view: Array in [[11.0, 0.6, ""], [6.0, 0.6, ""], [6.0, 4.4, "_right"]]:
		var d: float = view[0]
		_distance = d
		_focus_x = view[1]
		_place_camera()
		for clip: String in moments:
			for ap in _players:
				if ap == null:
					continue
				var clip_name := clip if ap.has_animation(clip) else "idle"
				ap.play(clip_name)
				ap.seek(ap.get_animation(clip_name).length * moments[clip], true)
				ap.pause()
			await _shot("shot_%s_%dm%s.jpg" % [clip, int(d), view[2]])
	get_tree().quit()
