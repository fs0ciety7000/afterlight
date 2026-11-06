extends Node3D
## VFX preview: Fern facing three dummy targets, every spell and combat effect on a key, live
## cost overlay, and a record mode that renders each effect into frames for the clip tool.
##
##   godot --path . res://game/world/prototype/vfx_preview.tscn
##   tools/vfx_record.sh   (record mode under xvfb + ffmpeg clips, see docs/VFX.md)
##
## Keys: 1 mana bolt, 2 Zoltraak, 3 mana volley, 4 barrier (B hit, X break), R / 5 ultimate,
## 6 hit, 7 crit, 8 next status, 9 next telegraph, 0 deaths, H heal, L level up,
## E next element, N day / night, M reduce motion, Space clear.

const TOON_SHADER: Shader = preload("res://assets/shaders/toon.gdshader")
const FERN_GLB := "res://assets/models/characters/fern/fern.glb"
const ENEMY_DIR := "res://assets/models/enemies/%s/%s.glb"
const ELEMENTS := ["arcane", "fire", "frost", "lightning"]
const STATUSES := ["burn", "chill", "frozen", "shock", "stun", "weaken", "haste"]
const TELEGRAPHS := ["circle", "line", "cone"]
## Dummy targets: id (model looked up in assets/models/enemies), position, colour, size.
const DUMMIES := [
	["mist_wolf", Vector3(3.2, 0, -1.6), Color("#5b5f6e"), Vector2(0.38, 1.1)],
	["stone_sentinel", Vector3(4.4, 0, 0.6), Color("#8c8576"), Vector2(0.55, 1.7)],
	["wandering_lantern", Vector3(2.8, 0, 2.4), Color("#c9a46a"), Vector2(0.32, 1.3)],
]
const DAY := {
	"sun_color": Color("#ffe2b0"),
	"sun_energy": 0.75,
	"sun_rot": Vector3(-38, -50, 0),
	"sky_top": Color("#8ea4dd"),
	"sky_horizon": Color("#e9d9ee"),
	"ambient": Color("#a9b8d8"),
	"ambient_energy": 0.35,
	"ground": Color("#93b56c"),
	"path": Color("#d2b48a"),
	"glow": 0.4,
	"bg_energy": 1.0,
}
const NIGHT := {
	"sun_color": Color("#bcd0ff"),
	"sun_energy": 0.42,
	"sun_rot": Vector3(-50, 60, 0),
	"sky_top": Color("#0d1626"),
	"sky_horizon": Color("#2b3a55"),
	"ambient": Color("#1a2433"),
	"ambient_energy": 1.1,
	"ground": Color("#4a5566"),
	"path": Color("#5d6478"),
	"glow": 1.0,
	"bg_energy": 1.0,
}
const RECORD_DIR := "res://art/source/vfx/frames/"
const PERF_PATH := "res://art/source/vfx/perf.json"

@export var camera_pitch_deg := 50.0
@export var camera_distance := 11.0

var night := true
var element := "arcane"
var fern: Node3D
var tip: Node3D
var dummies: Array[Node3D] = []
var _anim: AnimationPlayer
var _status_i := 0
var _telegraph_i := 0
var _barrier: VfxSequence
var _statuses: Array[VfxSequence] = []
var _trauma := 0.0
var _shake_t := 0.0
var _cam_base := Transform3D.IDENTITY
var _recording := false
var _frame := 0
var _clip := ""
var _peak: Dictionary = {}
var _perf: Dictionary = {}

@onready var vfx: Vfx = $Vfx
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var env: WorldEnvironment = $WorldEnvironment
@onready var hud: Label = $Hud/Info


func _ready() -> void:
	_spawn_fern()
	_spawn_dummies()
	for mi: MeshInstance3D in [$Ground, $Path]:
		var toon := ShaderMaterial.new()
		toon.shader = TOON_SHADER
		mi.set_surface_override_material(0, toon)
	_place_camera()
	vfx.hit_stop_requested.connect(_on_hit_stop)
	vfx.shake_requested.connect(_on_shake)
	set_night(night)
	vfx.prewarm(camera)
	if "--record" in OS.get_cmdline_user_args():
		_record.call_deferred()
	elif "--bench" in OS.get_cmdline_user_args():
		_bench.call_deferred()


# --- scene -------------------------------------------------------------------------------


func _spawn_fern() -> void:
	fern = (load(FERN_GLB) as PackedScene).instantiate()
	add_child(fern)
	fern.position = Vector3(-3.6, 0, 0.2)
	fern.rotation.y = deg_to_rad(-90.0)
	Toon.apply(fern, night)
	_anim = fern.find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer
	if _anim:
		_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		_anim.animation_finished.connect(func(_n: StringName) -> void: _anim.play("idle", 0.25))
		_anim.play("idle")
	tip = _make_staff_tip()


## A node that follows the top of the staff (the staff is skinned to a hand bone).
func _make_staff_tip() -> Node3D:
	var skel := fern.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var staff := fern.find_child("Staff", true, false) as MeshInstance3D
	var marker := Node3D.new()
	marker.name = "StaffTip"
	if skel == null or staff == null:
		fern.add_child(marker)
		marker.position = Vector3(0.3, 1.5, -0.3)
		return marker
	var bone := skel.find_bone("Staff_2")
	if bone < 0:
		bone = skel.find_bone("RightHand")
	var top := Vector3(0, -INF, 0)
	var verts: PackedVector3Array = staff.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in verts:
		if v.y > top.y:
			top = v
	var att := BoneAttachment3D.new()
	att.bone_idx = bone
	skel.add_child(att)
	att.add_child(marker)
	# Rest pose: mesh space == skeleton space, so express the tip in the bone rest frame.
	var rest := skel.get_bone_global_rest(bone)
	var top_skel := skel.transform.affine_inverse() * staff.transform * top
	marker.transform = Transform3D(Basis.IDENTITY, rest.affine_inverse() * top_skel)
	return marker


func _spawn_dummies() -> void:
	for d: Array in DUMMIES:
		var path := ENEMY_DIR % [d[0], d[0]]
		var node: Node3D
		if ResourceLoader.exists(path):
			node = (load(path) as PackedScene).instantiate()
		else:
			node = _capsule(d[2], d[3])
		node.name = String(d[0])
		node.position = d[1]
		node.rotation.y = deg_to_rad(90.0)
		add_child(node)
		Toon.apply(node, night)
		dummies.append(node)


func _capsule(color: Color, size: Vector2) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = size.x
	cap.height = size.y
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	cap.material = m
	mi.mesh = cap
	mi.position.y = size.y * 0.5
	root.add_child(mi)
	return root


func _reset_dummies() -> void:
	for i in dummies.size():
		var d := dummies[i]
		if is_instance_valid(d):
			d.queue_free()
	dummies.clear()
	_spawn_dummies()


func _place_camera() -> void:
	var focus := Vector3(0.6, 0.6, 0.0)
	var pitch := deg_to_rad(camera_pitch_deg)
	camera.global_position = focus + Vector3(0.0, sin(pitch), cos(pitch)) * camera_distance
	camera.look_at(focus, Vector3.UP)
	_cam_base = camera.global_transform


func set_night(on: bool) -> void:
	night = on
	vfx.night = on
	var p: Dictionary = NIGHT if on else DAY
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.rotation_degrees = p.sun_rot
	var e := env.environment
	var sky := e.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = p.sky_top
	sky.sky_horizon_color = p.sky_horizon
	sky.ground_horizon_color = p.sky_horizon
	sky.ground_bottom_color = p.sky_top
	e.ambient_light_color = p.ambient
	e.ambient_light_energy = p.ambient_energy
	e.glow_intensity = p.glow
	($Lantern as OmniLight3D).visible = false
	for mi: MeshInstance3D in [$Ground, $Path]:
		var tm := mi.get_surface_override_material(0) as ShaderMaterial
		if tm:
			tm.set_shader_parameter("albedo_tint", p.ground if mi.name == "Ground" else p.path)
			tm.set_shader_parameter("rim_strength", 0.0)


# --- effects -----------------------------------------------------------------------------


func _targets(n: int) -> Array:
	var out: Array = []
	var alive: Array[Node3D] = []
	for d in dummies:
		if is_instance_valid(d) and d.visible:
			alive.append(d)
	if alive.is_empty():
		return out
	for i in n:
		# 50 % on the focused target (the first one), the rest spread (GDD §6).
		out.append(alive[0] if i % 2 == 0 else alive[(i / 2) % alive.size()])
	return out


func _cast_anim(seek: float = 0.6) -> void:
	if _anim and _anim.has_animation("cast"):
		_anim.play("cast", 0.08)
		_anim.seek(seek, true)


func _ctx(extra: Dictionary = {}) -> Dictionary:
	var c := {"caster": fern, "tip": tip, "element": element, "seed": _frame}
	c.merge(extra, true)
	return c


func mana_bolt() -> void:
	_cast_anim(0.85)
	var seq := vfx.play_recipe("vfx.projectile_bolt", _ctx({"target": dummies[0]}))
	seq.arrived.connect(func(_i: int, _p: Vector3) -> void: _land(dummies[0], 142, false))


func zoltraak(crit: bool = false) -> void:
	_cast_anim(0.45)
	var target := dummies[1]
	var seq := vfx.play_recipe("vfx.beam_precise", _ctx({"target": target, "crit": crit}))
	seq.arrived.connect(func(_i: int, _p: Vector3) -> void: _land(target, 412, crit))


func volley() -> void:
	_cast_anim(0.35)
	var ts := _targets(5)
	var seq := vfx.play_recipe("vfx.volley_homing", _ctx({"targets": ts}))
	seq.arrived.connect(func(i: int, _p: Vector3) -> void: _land(ts[i], 77 + i * 3, false))


func barrier() -> void:
	if _barrier and is_instance_valid(_barrier):
		_barrier.cancel()
	_barrier = vfx.play_recipe("vfx.barrier_dome", _ctx({"duration": 4.0}))


func barrier_hit() -> void:
	var s := _barrier.find_block("shield") if _barrier and is_instance_valid(_barrier) else null
	if s:
		s.call("hit", dummies[1].global_position + Vector3.UP)
		vfx.number(fern, 64, "absorbed")


func barrier_break() -> void:
	var s := _barrier.find_block("shield") if _barrier and is_instance_valid(_barrier) else null
	if s:
		s.call("break_shield")


func afterlight() -> void:
	_cast_anim(0.2)
	var ts := _targets(12)
	var seq := vfx.play_recipe("vfx.sky_rain", _ctx({"targets": ts, "channel_s": 2.0}))
	seq.arrived.connect(func(i: int, _p: Vector3) -> void: _land(ts[i], 188 + i * 7, i == 11))


func hit(target: Node3D, crit: bool) -> void:
	vfx.play_recipe("vfx.crit" if crit else "vfx.hit", _ctx({"target": target}))
	_land(target, 980 if crit else 131, crit)


func _land(target: Node3D, amount: int, crit: bool) -> void:
	if not is_instance_valid(target):
		return
	vfx.number(target, amount, "crit" if crit else "normal")
	vfx.flash(target)


func next_status(target: Node3D = null) -> void:
	var kind: String = STATUSES[_status_i % STATUSES.size()]
	_status_i += 1
	var t := target if target else dummies[_status_i % dummies.size()]
	_statuses.append(vfx.play_recipe("vfx.status_" + kind, _ctx({"target": t})))


func clear_statuses() -> void:
	for s in _statuses:
		if is_instance_valid(s):
			s.cancel()
	_statuses.clear()


func next_telegraph() -> void:
	var shape: String = TELEGRAPHS[_telegraph_i % TELEGRAPHS.size()]
	_telegraph_i += 1
	var caster := dummies[_telegraph_i % dummies.size()]
	var sizes := {
		"circle": {"radius": 3.0},
		"line": {"length": 6.0, "width": 1.2},
		"cone": {"radius": 4.0, "angle": 30.0},
	}
	(
		vfx
		. play_recipe(
			"vfx.telegraph_" + shape,
			{
				"caster": caster,
				"target": fern,
				"cast_s": 1.2,
				"overrides": {"telegraph": sizes[shape]},
			}
		)
	)


func deaths() -> void:
	vfx.play_recipe("vfx.death_ash", {"target": dummies[1]})
	vfx.play_recipe("vfx.death_mist", {"target": dummies[0]})


func clear_all() -> void:
	vfx.stop_all()
	_statuses.clear()
	_reset_dummies()


# --- game feel (owned by the scene, requested by Vfx) ------------------------------------


func _on_hit_stop(duration_s: float) -> void:
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration_s, true, false, true).timeout
	Engine.time_scale = 1.0


func _on_shake(trauma: float) -> void:
	_trauma = minf(_trauma + trauma, 1.0)


func _process(delta: float) -> void:
	var real := delta if Engine.time_scale > 0.0 else 1.0 / 30.0
	_shake_t += real
	_trauma = maxf(_trauma - real * 1.4, 0.0)
	var s := _trauma * _trauma
	var off := Vector3(
		(0.6 * sin(_shake_t * 41.0) + 0.4 * sin(_shake_t * 87.0)) * 0.22 * s,
		(0.6 * sin(_shake_t * 37.0 + 1.3) + 0.4 * sin(_shake_t * 71.0)) * 0.16 * s,
		0.0
	)
	camera.global_transform = _cam_base.translated_local(off)
	_update_hud()


func _update_hud() -> void:
	var st := vfx.stats()
	var draw := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if _recording:
		_peak["draw_calls"] = maxf(float(_peak.get("draw_calls", 0.0)), draw)
		_peak["objects"] = maxf(float(_peak.get("objects", 0.0)), objs)
		_peak["primitives"] = maxf(float(_peak.get("primitives", 0.0)), prims)
		_peak["vfx_particles"] = maxi(int(_peak.get("vfx_particles", 0)), int(st["particles"]))
		_peak["vfx_layers"] = maxi(int(_peak.get("vfx_layers", 0)), int(st["layers"]))
		var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_peak["process_ms"] = maxf(float(_peak.get("process_ms", 0.0)), proc)
		hud.visible = false
		return
	hud.text = (
		(
			"%d fps  draw %d  obj %d  prim %d  |  vfx blocks %d  layers %d  particles %d\n"
			+ "%s  element %s  reduce motion %s\n"
			+ "1 bolt  2 Zoltraak  3 volley  4 barrier (B hit, X break)  R ultimate  6 hit  7 crit"
			+ "\n8 status  9 telegraph  0 deaths  H heal  L level up  E element  N day/night"
			+ "  M reduce motion  Space reset"
		)
		% [
			Engine.get_frames_per_second(),
			draw,
			objs,
			prims,
			st["blocks"],
			st["layers"],
			st["particles"],
			"night" if night else "day",
			element,
			"on" if vfx.reduce_motion else "off",
		]
	)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			mana_bolt()
		KEY_2:
			zoltraak()
		KEY_3:
			volley()
		KEY_4:
			barrier()
		KEY_B:
			barrier_hit()
		KEY_X:
			barrier_break()
		KEY_R, KEY_5:
			afterlight()
		KEY_6:
			hit(dummies[randi() % dummies.size()], false)
		KEY_7:
			hit(dummies[1], true)
		KEY_8:
			next_status()
		KEY_9:
			next_telegraph()
		KEY_0:
			deaths()
		KEY_H:
			vfx.play_recipe("vfx.heal", {"target": fern})
			vfx.number(fern, 120, "heal")
		KEY_L:
			vfx.play_recipe("vfx.level_up", {"caster": fern})
		KEY_E:
			element = ELEMENTS[(ELEMENTS.find(element) + 1) % ELEMENTS.size()]
		KEY_N:
			set_night(not night)
		KEY_M:
			vfx.reduce_motion = not vfx.reduce_motion
		KEY_SPACE:
			clear_all()


# --- record mode -------------------------------------------------------------------------


func _record() -> void:
	_recording = true
	# Partial runs (--only) update their clips and keep the other measures.
	if FileAccess.file_exists(PERF_PATH):
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERF_PATH))
		if previous is Dictionary:
			_perf = previous
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECORD_DIR))
	await _frames(10)
	_peak = {}
	await _frames(10)
	_perf["baseline_night"] = _peak.duplicate()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
	for clip: Array in _clips():
		if only != "" and not String(clip[0]).contains(only):
			continue
		await _record_clip(clip[0], clip[1], clip[2], clip[3])
	var f := FileAccess.open(PERF_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(_perf, "  ", false))
	f.close()
	print("VFX record done")
	get_tree().quit()


## name, night, seconds, callable.
func _clips() -> Array:
	return [
		["mana_bolt", true, 1.1, mana_bolt],
		["zoltraak_night", true, 1.6, zoltraak],
		["zoltraak_day", false, 1.6, zoltraak],
		["zoltraak_crit", true, 1.6, zoltraak.bind(true)],
		["mana_volley", true, 1.8, volley],
		["barrier", true, 2.8, _barrier_clip],
		["afterlight_night", true, 4.4, afterlight],
		["afterlight_day", false, 4.4, afterlight],
		["hits_elements", true, 2.4, _hits_clip],
		["statuses", true, 2.6, _status_clip],
		["telegraphs", true, 1.8, _telegraph_clip],
		["deaths", true, 1.7, deaths],
		["heal_level_up", true, 1.9, _support_clip],
	]


func _record_clip(clip_name: String, on_night: bool, seconds: float, fn: Callable) -> void:
	clear_all()
	set_night(on_night)
	element = "arcane"
	_status_i = 0
	_telegraph_i = 0
	if _anim:
		_anim.play("idle")
	await _frames(8)
	_peak = {}
	await _frames(6)
	_perf["baseline_" + clip_name] = _peak.duplicate()
	_clip = clip_name
	_frame = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECORD_DIR + clip_name))
	_peak = {}
	fn.call()
	var n := int(seconds * 30.0)
	for i in n:
		await RenderingServer.frame_post_draw
		_save_frame()
	_perf[clip_name] = _peak.duplicate()
	print("clip ", clip_name, " ", n, " frames ", _perf[clip_name])


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _save_frame() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := RECORD_DIR + "%s/%04d.png" % [_clip, _frame]
	img.save_png(ProjectSettings.globalize_path(path))
	_frame += 1


func _barrier_clip() -> void:
	barrier()
	await get_tree().create_timer(0.8).timeout
	barrier_hit()
	await get_tree().create_timer(0.5).timeout
	barrier_hit()
	await get_tree().create_timer(0.7).timeout
	barrier_break()


func _hits_clip() -> void:
	for e: String in ELEMENTS:
		element = e
		hit(dummies[ELEMENTS.find(e) % 3], false)
		await get_tree().create_timer(0.4).timeout
	element = "arcane"
	hit(dummies[1], true)


func _status_clip() -> void:
	for i in 3:
		next_status(dummies[i])
	await get_tree().create_timer(1.2).timeout
	clear_statuses()
	for i in 3:
		next_status(dummies[i])
	next_status(fern)


func _telegraph_clip() -> void:
	for i in 3:
		next_telegraph()


func _support_clip() -> void:
	vfx.play_recipe("vfx.heal", {"target": fern})
	vfx.number(fern, 120, "heal")
	await get_tree().create_timer(0.5).timeout
	vfx.play_recipe("vfx.level_up", {"caster": fern})


# --- bench mode (headless: CPU cost of the VFX scripts and CPU particles) -----------------


## godot --headless --path . --fixed-fps 60 res://game/world/prototype/vfx_preview.tscn -- --bench
## Prints the mean wall time per frame (headless: CPU only) of each spell over its duration.
func _bench() -> void:
	var cases := [
		["idle", 2.0, func() -> void: pass],
		["mana_bolt", 1.0, mana_bolt],
		["zoltraak", 1.5, zoltraak],
		["mana_volley", 1.6, volley],
		["barrier", 2.0, barrier],
		["afterlight", 4.0, afterlight],
		["statuses_x4", 2.0, _bench_statuses],
	]
	var out := {}
	for c: Array in cases:
		clear_all()
		for i in 5:
			await get_tree().process_frame
		(c[2] as Callable).call()
		var total := 0.0
		var n := int(float(c[1]) * 60.0)
		var t0 := Time.get_ticks_usec()
		for i in n:
			await get_tree().process_frame
		# Headless + --fixed-fps runs frames back to back: wall time per frame = CPU cost.
		total = (Time.get_ticks_usec() - t0) / 1000.0
		out[c[0]] = snappedf(total / n, 0.001)
		print("bench ", c[0], " ", out[c[0]], " ms/frame")
	var f := FileAccess.open("res://art/source/vfx/bench.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ", false))
	f.close()
	get_tree().quit()


func _bench_statuses() -> void:
	for i in 4:
		next_status(dummies[i % dummies.size()])
