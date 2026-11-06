class_name ExplorePlayer
extends CharacterBody3D
## Fern on foot. Reads movement from keys (physical WASD = ZQSD on AZERTY,
## arrows), a virtual joystick vector, or a click-to-move target. Speed comes
## from content (base_stats.move_speed); feel constants stay here.

const MODEL := "res://assets/models/characters/fern/fern.glb"
const ACCEL_TIME := 0.1
const TURN_SPEED_DEG := 720.0
const ARRIVE_DISTANCE := 0.25
const STUCK_SECONDS := 0.6
const RUN_THRESHOLD := 0.8

var move_speed := 5.0
## True while a CombatView drives Fern from the simulation.
var combat_driven := false
## Set by the HUD joystick, in screen space (x right, y down), length <= 1.
var joystick := Vector2.ZERO
var _target: Variant = null
var _path: PackedVector3Array = []
var _stuck_time := 0.0
var _anim: AnimationPlayer
var _model: Node3D
var _base_clip := "idle"
var _one_shot := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	shape.shape = capsule
	shape.position.y = 0.8
	add_child(shape)
	_model = (load(MODEL) as PackedScene).instantiate()
	add_child(_model)
	Toon.apply(_model)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for clip in ["idle", "walk", "run"]:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_anim.animation_finished.connect(_on_clip_finished)
		_play("idle")


func move_to(point: Vector3) -> void:
	follow_path(PackedVector3Array([point]))


## Walks through `points` in order (a navigation path).
func follow_path(points: PackedVector3Array) -> void:
	_path = points
	_stuck_time = 0.0
	_next_waypoint()


func stop() -> void:
	_target = null
	_path = []


func _next_waypoint() -> void:
	if _path.is_empty():
		_target = null
		return
	var p := _path[0]
	_path.remove_at(0)
	_target = Vector3(p.x, global_position.y, p.z)


func is_moving_to_target() -> bool:
	return _target != null


func _physics_process(delta: float) -> void:
	if combat_driven:
		return
	var wish := _input_direction()
	if wish != Vector3.ZERO:
		stop()
	elif _target != null:
		var to: Vector3 = (_target as Vector3) - global_position
		to.y = 0.0
		if to.length() <= ARRIVE_DISTANCE:
			_next_waypoint()
		if _target != null:
			to = (_target as Vector3) - global_position
			to.y = 0.0
			wish = to.normalized()
	var desired := wish * move_speed
	var accel := move_speed / ACCEL_TIME
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	var before := global_position
	move_and_slide()
	if _target != null:
		var moved := (global_position - before).length()
		_stuck_time = _stuck_time + delta if moved < move_speed * delta * 0.2 else 0.0
		if _stuck_time > STUCK_SECONDS:
			stop()
	if horizontal.length() > 0.1:
		var yaw := atan2(-horizontal.x, -horizontal.z)
		rotation.y = rotate_toward(rotation.y, yaw, deg_to_rad(TURN_SPEED_DEG) * delta)
	var speed_ratio := horizontal.length() / maxf(move_speed, 0.01)
	if speed_ratio < 0.1:
		_play("idle")
	elif speed_ratio < RUN_THRESHOLD:
		_play("walk")
	else:
		_play("run")


## The camera looks toward -Z, so "up" on screen is -Z in the world.
func _input_direction() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v == Vector2.ZERO:
		v = joystick
	return Vector3(v.x, 0.0, v.y).limit_length(1.0)


## Looping state clip chosen by combat (idle or run).
func play_base(clip: String) -> void:
	_base_clip = clip
	if not _one_shot:
		_play(clip)


## One-shot clip (cast, hit, death, victory).
func play_once(clip: String) -> void:
	if _anim and _anim.has_animation(clip):
		_one_shot = true
		_anim.play(clip, 0.08)
		_anim.seek(0.0, true)


func _on_clip_finished(clip: StringName) -> void:
	if clip in [&"death", &"victory"]:
		return
	_one_shot = false
	_play(_base_clip)


func _play(clip: String) -> void:
	if _one_shot and not combat_driven and clip != _base_clip:
		_one_shot = false
	if _anim and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.15)
