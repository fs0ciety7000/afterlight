class_name CombatActor
extends Node3D
## Visual stand-in for one enemy in combat or idling in a location. It plays
## clips and follows positions given by the combat view; it decides nothing.

const CLICK_LAYER := 16
const ELITE_TINT := Color(0.72, 0.72, 0.8)

var uid := ""
var def_id := ""
var alive := true
var _anim: AnimationPlayer
var _model: Node3D
var _base_clip := "idle"
var _one_shot := false


func setup(enemy: Dictionary, unit_id: String) -> void:
	uid = unit_id
	def_id = enemy.get("id", "")
	var path: String = enemy.get("model", "")
	if ResourceLoader.exists(path):
		_model = (load(path) as PackedScene).instantiate()
	else:
		_model = _fallback_model()
	add_child(_model)
	var s := float(enemy.get("scale", 1.0))
	_model.scale = Vector3.ONE * s
	Toon.apply(_model)
	if enemy.get("archetype", "") == "elite":
		_tint(_model, ELITE_TINT)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		_anim.animation_finished.connect(_on_clip_finished)
		for clip in ["idle", "run"]:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_add_click_area(s)
	play_base("idle")


## Looping state clip (idle or run).
func play_base(clip: String) -> void:
	_base_clip = clip
	if not _one_shot:
		_play(clip)


## One-shot clip (attack, cast, hit, death); returns to the base clip after.
func play_once(clip: String) -> void:
	if not alive and clip != "death":
		return
	if _anim and _anim.has_animation(clip):
		_one_shot = true
		_anim.play(clip, 0.08)
		_anim.seek(0.0, true)


func die() -> void:
	alive = false
	play_once("death")
	var area := get_node_or_null("ClickArea")
	if area:
		area.queue_free()


func _play(clip: String) -> void:
	if _anim and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.15)


func _on_clip_finished(_clip: StringName) -> void:
	if not alive:
		return
	_one_shot = false
	_play(_base_clip)


func _add_click_area(s: float) -> void:
	var area := Area3D.new()
	area.name = "ClickArea"
	area.collision_layer = CLICK_LAYER
	area.collision_mask = 0
	area.input_ray_pickable = false
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.7 * s
	capsule.height = 2.0 * s
	shape.shape = capsule
	shape.position.y = capsule.height / 2.0
	area.add_child(shape)
	area.set_meta("uid", uid)
	add_child(area)


static func _tint(root: Node, tint: Color) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(i)
			if mat is ShaderMaterial:
				var c: Variant = (mat as ShaderMaterial).get_shader_parameter("albedo_tint")
				var base: Color = c if c is Color else Color.WHITE
				(mat as ShaderMaterial).set_shader_parameter("albedo_tint", base * tint)


static func _fallback_model() -> Node3D:
	var m := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.4
	m.mesh = capsule
	m.position.y = 0.7
	var root := Node3D.new()
	root.add_child(m)
	return root
