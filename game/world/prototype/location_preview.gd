extends Node3D
## Location preview: instances a location scene, Fern and the gameplay camera rig (CameraRig, the
## same 50° / 14 m camera the exploration code uses) to review the decor and measure its cost.
##
##   godot --path . res://game/world/prototype/location_preview.tscn -- --location=aubelin
##   ... -- --location=whispering_wood --shots  (writes art/source/env/shot_*.jpg, perf_*.json)
##   --distance=11 : gameplay camera distance for the shots (default: CameraRig's first zoom step)
##   --tag=before  : file name suffix (shot_<name>_<tag>.jpg, perf_<location>_<tag>.json)
##   --out=res://art/source/env/lantern_mire/ : folder for the shots (default art/source/env/)
##   --only=a,b    : only these shots (names without the shot_ prefix)
##   --top         : also writes an orthographic top-down view of the place (top_<location>.jpg)
## Keys: arrows move Fern, Q / E turn the camera, Z zoom, P print the render monitors.

const LOCATIONS := {
	"aubelin": "res://game/world/locations/aubelin.tscn",
	"whispering_wood": "res://game/world/locations/whispering_wood.tscn",
	"lantern_mire": "res://game/world/locations/lantern_mire.tscn",
	"watch_ruins": "res://game/world/locations/watch_ruins.tscn",
	"aubelin_npcs": "res://game/world/locations/aubelin.tscn",
	"silent_dial_cloister": "res://game/world/dungeons/silent_dial_cloister.tscn",
}
## Top-down frame per place (centre x, z and width in metres); default (0, 0), 84 m.
const TOP := {"silent_dial_cloister": [Vector2(4, -88), 290.0]}
const FERN := "res://assets/models/characters/fern/fern.glb"
const SHOT_DIR := "res://art/source/env/"
## name, Fern position (x, z), camera yaw (degrees), Fern yaw (degrees), vista (low pitch, wide)
const SHOTS := {
	"aubelin":
	[
		["aubelin_square", Vector2(0.5, 5.5), 0.0, 180.0, false],
		["aubelin_east", Vector2(10.0, 3.0), -35.0, 120.0, false],
		["aubelin_nw_exit", Vector2(-19.0, -17.0), 25.0, 135.0, false],
		["aubelin_vista", Vector2(0.0, 18.0), 0.0, 180.0, true],
	],
	"whispering_wood":
	[
		["wood_entrance", Vector2(22.0, 23.0), 0.0, 135.0, false],
		["wood_clearing", Vector2(-4.0, -6.0), 30.0, 160.0, false],
		["wood_path", Vector2(4.0, 2.0), -20.0, 140.0, false],
		["wood_vista", Vector2(8.0, 12.0), -30.0, 160.0, true],
	],
	"lantern_mire":
	[
		["mire_arrival", Vector2(-31.0, 6.0), 0.0, 90.0, false],
		["mire_pontoon", Vector2(-9.0, 5.5), 0.0, 90.0, false],
		["mire_beacon", Vector2(-5.0, 13.5), 0.0, 160.0, false],
		["mire_ferry", Vector2(-28.0, -20.0), 0.0, 200.0, false],
		["mire_east", Vector2(27.0, 4.0), 0.0, 180.0, false],
		["mire_chest", Vector2(32.5, -24.0), 0.0, 170.0, false],
		["mire_north", Vector2(4.0, -31.0), 0.0, 180.0, false],
		["mire_vista", Vector2(-12.0, 14.0), -15.0, 160.0, true],
	],
	"watch_ruins":
	[
		["ruins_arrival", Vector2(0.0, 33.0), 0.0, 180.0, false],
		["ruins_gate", Vector2(1.0, 24.0), 0.0, 180.0, false],
		["ruins_guardroom", Vector2(-21.0, -5.0), 0.0, 200.0, false],
		["ruins_tower", Vector2(27.0, -19.0), 0.0, 160.0, false],
		["ruins_postern", Vector2(24.0, -31.0), 0.0, 180.0, false],
		["ruins_vista", Vector2(0.0, 22.0), -10.0, 170.0, true],
	],
	"aubelin_npcs":
	[
		["aubelin_npcs_square", Vector2(0.5, 5.5), 0.0, 180.0, false],
	],
	"silent_dial_cloister":
	[
		["cloister_vestibule", Vector2(0.0, 8.0), 0.0, 180.0, false],
		["cloister_gallery", Vector2(0.0, -44.0), 0.0, 180.0, false],
		["cloister_fountain", Vector2(30.0, -63.0), 0.0, 180.0, false],
		["cloister_courtyard", Vector2(30.0, -96.0), 0.0, 180.0, false],
		["cloister_kennel", Vector2(-18.0, -98.0), 0.0, 180.0, false],
		["cloister_campfire", Vector2(-18.0, -134.0), 0.0, 180.0, false],
		["cloister_dial", Vector2(-18.0, -168.0), 0.0, 180.0, false],
		["cloister_dial_centre", Vector2(-18.0, -177.0), 0.0, 180.0, false],
		["cloister_dial_north", Vector2(-18.0, -186.0), 0.0, 180.0, false],
		["cloister_dial_vista", Vector2(-18.0, -163.0), 0.0, 180.0, true],
		["cloister_vista", Vector2(30.0, -92.0), 0.0, 180.0, true],
	],
}

var location := "aubelin"
var fern: Node3D
var rig: CameraRig
var _vista := false
var _distance := 0.0
var _tag := ""
var _out := SHOT_DIR
var _only: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--location="):
			location = a.get_slice("=", 1)
		elif a.begins_with("--distance="):
			_distance = a.get_slice("=", 1).to_float()
		elif a.begins_with("--tag="):
			_tag = "_" + a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--only="):
			_only = a.get_slice("=", 1).split(",")
	add_child((load(LOCATIONS[location]) as PackedScene).instantiate())
	if "--nofog" in OS.get_cmdline_user_args():  # diagnosis: what the fog does to a view
		for node in find_children("*", "WorldEnvironment", true, false):
			var env: Environment = (node as WorldEnvironment).environment
			env.fog_enabled = false
	fern = (load(FERN) as PackedScene).instantiate()
	add_child(fern)
	Toon.apply(fern)
	var players := fern.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var anim := players[0] as AnimationPlayer
		if anim.has_animation("idle"):
			anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			anim.play("idle")
	rig = CameraRig.new()
	add_child(rig)
	rig.target = fern
	var spawn := get_node_or_null("%s/Spawns/default" % get_child(0).name) as Node3D
	if spawn:
		fern.global_transform = spawn.global_transform
	rig.snap()
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots()


func _process(delta: float) -> void:
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if v != Vector2.ZERO:
		var dir := Vector3(v.x, 0, v.y).rotated(Vector3.UP, rig.rotation.y)
		fern.global_position = _ground(fern.global_position + dir * 4.0 * delta)
		fern.rotation.y = atan2(-dir.x, -dir.z)
	if _vista:
		_place_vista()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match (event as InputEventKey).keycode:
		KEY_Q:
			rig.rotation.y += deg_to_rad(15)
		KEY_E:
			rig.rotation.y -= deg_to_rad(15)
		KEY_Z:
			rig.zoom(1 if rig.zoom_index < 2 else -2)
		KEY_P:
			print(JSON.stringify(_monitors()))


func _ground(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 40.0, p + Vector3.DOWN * 40.0, 1)
	var hit := space.intersect_ray(q)
	return hit["position"] if hit else p


func _monitors() -> Dictionary:
	return {
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb":
		snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
	}


func _place_vista() -> void:
	# wider, lower look for review only (the game camera stays at 50°)
	var target := fern.global_position + Vector3(0, 1.5, 0)
	var pitch := deg_to_rad(16.0)
	var dir := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, rig.rotation.y)
	rig.camera.global_position = target + dir * 16.0
	rig.camera.look_at(target + Vector3(0, 3.0, 0) - dir * 10.0, Vector3.UP)


func _place_at_distance(d: float) -> void:
	# same placement as CameraRig._place_camera, at an explicit distance
	var pitch := deg_to_rad(CameraRig.PITCH_DEG)
	rig.camera.position = Vector3(0.0, sin(pitch) * d + 0.8, cos(pitch) * d)
	rig.camera.rotation = Vector3(-pitch, 0.0, 0.0)


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _take_shots() -> void:
	await _frames(10)
	var report := {}
	for s in SHOTS[location]:
		if not _only.is_empty() and not s[0] in _only:
			continue
		var at: Vector2 = s[1]
		fern.global_position = _ground(Vector3(at.x, 0, at.y))
		fern.rotation.y = deg_to_rad(s[3])
		rig.rotation.y = deg_to_rad(s[2])
		rig.zoom_index = 0
		rig.snap()
		_vista = s[4]
		rig.set_process(not _vista and _distance <= 0.0)
		if _vista:
			_place_vista()
		elif _distance > 0.0:
			_place_at_distance(_distance)
		await _frames(8)
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path(_out + "shot_%s%s.jpg" % [s[0], _tag])
		img.save_jpg(path, 0.88)
		report[s[0]] = _monitors()
		print(s[0], " ", report[s[0]])
	var f := FileAccess.open(
		ProjectSettings.globalize_path(_out + "perf_%s%s.json" % [location, _tag]), FileAccess.WRITE
	)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	if "--top" in OS.get_cmdline_user_args():
		await _top_down()
	get_tree().quit()


func _top_down() -> void:
	# whole place seen from above (orthographic, north up) to review the layout
	_vista = false
	rig.set_process(false)
	var cam := rig.camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var frame: Array = TOP.get(location, [Vector2.ZERO, 84.0])
	cam.size = frame[1]
	cam.far = 200.0
	cam.global_transform = Transform3D(
		Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(frame[0].x, 80, frame[0].y)
	)
	for node in find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		env.fog_enabled = false
	await _frames(8)
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(ProjectSettings.globalize_path(_out + "top_%s%s.jpg" % [location, _tag]), 0.88)
