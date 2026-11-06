class_name CombatView
extends Node3D
## Runs one encounter on the spot: steps the deterministic CombatSim at the
## chosen speed, mirrors units with actors, and forwards events to the HUD
## and effects. The sim decides everything; this node only shows it.

signal sim_event(event: Dictionary)
signal finished(completed: Dictionary)

const SPEEDS := [1, 2, 4]
const GLOW_KEYS := [
	"glow_enabled",
	"glow_intensity",
	"glow_strength",
	"glow_bloom",
	"glow_blend_mode",
	"glow_hdr_threshold",
]

## Hit-stops applied since boot (all views), read by MotionFlags for the E2E probe.
static var hit_stops_applied := 0

var sim: CombatSim
var paused := false
var speed_index := 0
var encounter_id := ""
var ticks := 0
var vfx: Vfx
var _anchor: Node3D
var _player: ExplorePlayer
var _actors := {}
var _prev := {}
var _curr := {}
var _clock := CombatClock.new()
var _done := false
var _speed_cap := 4
var _fx: CombatFx
var _rig: CameraRig
var _look: Environment
var _look_saved := {}


## Builds the sim from the game state. Returns "" or an error message.
func start(
	id: String, anchor: Node3D, player: ExplorePlayer, setup: Dictionary, rig: CameraRig = null
) -> String:
	encounter_id = id
	_anchor = anchor
	_player = player
	_rig = rig
	var full := setup.duplicate(true)
	full["encounter"] = id
	sim = CombatSim.create(full, Content.index())
	if sim.error != "":
		return sim.error
	_player.combat_driven = true
	_setup_vfx()
	_step_once()
	return ""


func _setup_vfx() -> void:
	vfx = Vfx.new()
	vfx.name = "Vfx"
	vfx.reduce_motion = Settings.reduce_motion
	vfx.quality = Settings.graphics_quality
	add_child(vfx)
	_fx = CombatFx.new(vfx, self)
	vfx.hit_stop_requested.connect(_on_hit_stop)
	vfx.shake_requested.connect(_on_shake)
	if _rig:
		vfx.prewarm(_rig.camera)
	_enable_glow()


## Freezes the sim clock (no tick consumed); ignored at ×4 (GDD §14, ROADMAP 7.4).
func _on_hit_stop(seconds: float) -> void:
	if _clock.request_hit_stop(seconds, speed()):
		hit_stops_applied += 1


func _on_shake(trauma: float) -> void:
	if _rig:
		_rig.add_shake(trauma)


## Glow for spell cores (docs/VFX.md 1.3, day values); restored after combat.
func _enable_glow() -> void:
	var worlds := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if worlds.is_empty():
		return
	_look = (worlds[0] as WorldEnvironment).get("environment")
	if _look == null:
		return
	for key in GLOW_KEYS:
		_look_saved[key] = _look.get(key)
	_look.glow_enabled = true
	_look.glow_intensity = 0.4
	_look.glow_strength = 1.0
	_look.glow_bloom = 0.0
	_look.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	_look.glow_hdr_threshold = 0.85


func _exit_tree() -> void:
	if _look:
		for key in _look_saved:
			_look.set(key, _look_saved[key])


func snapshot_unit(uid: String) -> Dictionary:
	for u in snapshot().get("units", []):
		if u["uid"] == uid:
			return u
	return {}


func speed() -> int:
	return SPEEDS[speed_index]


func cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	while speed() > _speed_cap:
		speed_index = (speed_index + 1) % SPEEDS.size()


func command(cmd: Dictionary) -> void:
	if sim and not _done:
		sim.command(cmd)


## World point -> sim ground coordinates (relative to the encounter anchor).
func to_sim(world: Vector3) -> Vector2:
	var local := _anchor.global_transform.affine_inverse() * world
	return Vector2(local.x, local.z)


func to_world(p: Array) -> Vector3:
	var w := _anchor.global_transform * Vector3(float(p[0]), 0.0, float(p[1]))
	return _snap_to_ground(w)


func actor(uid: String) -> Node3D:
	if uid.begins_with("p"):
		return _player
	return _actors.get(uid)


func snapshot() -> Dictionary:
	return sim.snapshot() if sim else {}


func _process(delta: float) -> void:
	if sim == null or _done:
		return
	for i in _clock.advance(delta, speed(), paused):
		if _done:
			break
		_step_once()
	_place_units(_clock.alpha())


func _step_once() -> void:
	var events := sim.step()
	ticks += 1
	_prev = _curr.duplicate()
	for u in sim.snapshot()["units"]:
		_curr[u["uid"]] = u
	for e in events:
		_handle(e)
		if _fx:
			_fx.handle(e)
		sim_event.emit(e)


func _handle(e: Dictionary) -> void:
	match e["type"]:
		"encounter_started":
			_speed_cap = int(e.get("speed_cap", 4))
			for u in e["units"]:
				_spawn_actor(u)
		"unit_spawned":
			_spawn_actor(e)
		"attack_started", "spell_cast":
			var a := actor(e["unit"])
			var generic := "attack" if e["type"] == "attack_started" else "cast"
			var clip := cast_clip(str(e.get("spell", "")), generic)
			if a is CombatActor:
				(a as CombatActor).play_once(clip, generic)
			elif a == _player and e["type"] == "spell_cast":
				_player.play_once(clip, generic)
		"damage_dealt":
			var t := actor(e["target"])
			if t is CombatActor and int(e.get("hp", 1)) > 0:
				(t as CombatActor).play_once("hit")
		"enemy_defeated":
			var d := actor(e["unit"])
			if d is CombatActor:
				(d as CombatActor).die()
		"character_defeated":
			_player.play_once("death")
		"encounter_completed":
			_done = true
			_player.combat_driven = false
			if e.get("result", "") == "victory":
				_player.play_once("victory")
			finished.emit(e)


## Clip a spell or ability asks its caster to play (its optional `anim` field), else `generic`.
static func cast_clip(spell_id: String, generic: String) -> String:
	if spell_id == "":
		return generic
	var anim: String = str(Content.get_entity(spell_id).get("anim", ""))
	return anim if anim != "" else generic


func _spawn_actor(u: Dictionary) -> void:
	var uid: String = u.get("uid", u.get("unit", ""))
	if u.get("side", "") != "enemy" or _actors.has(uid):
		return
	var a := CombatActor.new()
	a.name = uid
	add_child(a)
	a.setup(Content.get_entity(u["def_id"]), uid)
	a.global_position = to_world(u["position"])
	_actors[uid] = a


func _place_units(alpha: float) -> void:
	for uid in _curr:
		var now: Dictionary = _curr[uid]
		var before: Dictionary = _prev.get(uid, now)
		var node := actor(uid)
		if node == null:
			continue
		var a: Array = before["position"]
		var b: Array = now["position"]
		var p := [lerpf(a[0], b[0], alpha), lerpf(a[1], b[1], alpha)]
		node.global_position = to_world(p)
		var f: Array = now.get("facing", [0, -1])
		var dir := _anchor.global_transform.basis * Vector3(float(f[0]), 0.0, float(f[1]))
		if dir.length() > 0.01 and now.get("alive", true):
			node.rotation.y = atan2(-dir.x, -dir.z)
		var moving: bool = now.get("moving", false)
		if node is CombatActor:
			(node as CombatActor).play_base("run" if moving else "idle")
		elif node == _player:
			_player.play_base("run" if moving else "idle")


func _snap_to_ground(w: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(w + Vector3.UP * 20.0, w + Vector3.DOWN * 20.0, 1)
	var hit := space.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else w


## Unit uid under a screen point (enemies only), or "".
func pick_unit(cam: Camera3D, screen_point: Vector2) -> String:
	var from := cam.project_ray_origin(screen_point)
	var to := from + cam.project_ray_normal(screen_point) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to, CombatActor.CLICK_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	return str((hit["collider"] as Node).get_meta("uid", ""))
