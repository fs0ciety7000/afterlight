class_name CombatView
extends Node3D
## Runs one encounter on the spot: steps the deterministic CombatSim at the
## chosen speed, mirrors units with actors, and forwards events to the HUD
## and effects. The sim decides everything; this node only shows it.

signal sim_event(event: Dictionary)
signal finished(completed: Dictionary)

const MAX_STEPS_PER_FRAME := 40
const SPEEDS := [1, 2, 4]

var sim: CombatSim
var paused := false
var speed_index := 0
var encounter_id := ""
var ticks := 0
var _anchor: Node3D
var _player: ExplorePlayer
var _actors := {}
var _prev := {}
var _curr := {}
var _acc := 0.0
var _done := false
var _speed_cap := 4


## Builds the sim from the game state. Returns "" or an error message.
func start(id: String, anchor: Node3D, player: ExplorePlayer, setup: Dictionary) -> String:
	encounter_id = id
	_anchor = anchor
	_player = player
	var full := setup.duplicate(true)
	full["encounter"] = id
	sim = CombatSim.create(full, Content.index())
	if sim.error != "":
		return sim.error
	_player.combat_driven = true
	_step_once()
	return ""


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
	if not paused:
		_acc += delta * speed()
		var steps := 0
		while _acc >= BalanceCombat.TICK_SECONDS and steps < MAX_STEPS_PER_FRAME and not _done:
			_step_once()
			_acc -= BalanceCombat.TICK_SECONDS
			steps += 1
		if steps >= MAX_STEPS_PER_FRAME:
			_acc = 0.0
	_place_units(clampf(_acc / BalanceCombat.TICK_SECONDS, 0.0, 1.0))


func _step_once() -> void:
	var events := sim.step()
	ticks += 1
	_prev = _curr.duplicate()
	for u in sim.snapshot()["units"]:
		_curr[u["uid"]] = u
	for e in events:
		_handle(e)
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
			if a is CombatActor:
				(a as CombatActor).play_once("attack" if e["type"] == "attack_started" else "cast")
			elif a == _player and e["type"] == "spell_cast":
				_player.play_once("cast")
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
