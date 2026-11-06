class_name Vfx
extends Node3D
## Spell and combat VFX for the 3D combat scene (rendering layer: draws what it is told,
## decides nothing). Add one Vfx node to the combat scene, then map engine events to calls:
##
##   vfx.play("vfx.beam_precise", {"caster": fern, "tip": staff_tip, "target": enemy,
##       "element": "arcane", "cast_s": 0.3})        # a recipe -> VfxSequence
##   vfx.play("burst", {"position": p, "crit": true})  # a single block -> VfxBlock
##   vfx.number(enemy, 412, "crit")                     # floating damage number
##   vfx.flash(enemy)                                   # 60 ms white hit flash
##
## Game feel requests are signals (the scene owns time and camera): hit_stop_requested,
## shake_requested. Neither is requested when reduce_motion is on (DESIGN.md "Mouvement").
## Catalogue, parameters and the event -> effect table: docs/VFX.md.

signal hit_stop_requested(duration_s: float)
signal shake_requested(trauma: float)

const BLOCKS := {
	"cast_circle": preload("res://game/combat/vfx/blocks/cast_circle.gd"),
	"charge_orb": preload("res://game/combat/vfx/blocks/charge_orb.gd"),
	"projectile": preload("res://game/combat/vfx/blocks/projectile.gd"),
	"beam": preload("res://game/combat/vfx/blocks/beam.gd"),
	"burst": preload("res://game/combat/vfx/blocks/burst.gd"),
	"shockwave": preload("res://game/combat/vfx/blocks/shockwave.gd"),
	"scorch": preload("res://game/combat/vfx/blocks/scorch.gd"),
	"slash_arc": preload("res://game/combat/vfx/blocks/slash_arc.gd"),
	"rune_orbit": preload("res://game/combat/vfx/blocks/rune_orbit.gd"),
	"shield": preload("res://game/combat/vfx/blocks/shield.gd"),
	"aura": preload("res://game/combat/vfx/blocks/aura.gd"),
	"telegraph": preload("res://game/combat/vfx/blocks/telegraph.gd"),
	"status": preload("res://game/combat/vfx/blocks/status.gd"),
	"death": preload("res://game/combat/vfx/blocks/death.gd"),
}

## Night palette (additive glow) or day palette (effects cover part of the bright ground).
@export var night := false
## DESIGN.md "Réduire les animations": no shake, half the particles, no spin / bounce.
@export var reduce_motion := false
## GraphicsQuality level (0 low, 1 medium, 2 high): low halves the particles too.
@export_range(0, 2) var quality := 2
## Upper bound of live blocks; the oldest finishes early beyond it (protects weak devices).
@export var max_live_blocks := 64

var numbers: VfxDamageNumbers


func _ready() -> void:
	numbers = VfxDamageNumbers.new()
	numbers.name = "Numbers"
	add_child(numbers)


## Plays a recipe ("vfx.<name>", returns a VfxSequence) or a single block (returns a VfxBlock).
## Recipe context keys: caster, tip, target or targets (Node3D or Vector3), from, element,
## cast_s, channel_s, duration, scale, intensity, crit, seed, target_height.
func play(effect_id: String, params: Dictionary = {}) -> Node3D:
	if effect_id.begins_with("vfx."):
		return play_recipe(effect_id, params)
	return spawn_block(effect_id, params)


func play_recipe(recipe_id: String, context: Dictionary = {}) -> VfxSequence:
	var r := VfxRecipes.get_recipe(recipe_id)
	if r.is_empty():
		return null
	var seq := VfxSequence.new().setup(r, context, self)
	seq.name = recipe_id.replace(".", "_")
	add_child(seq)
	return seq


func spawn_block(block_id: String, params: Dictionary = {}) -> VfxBlock:
	var script: GDScript = BLOCKS.get(block_id)
	if script == null:
		push_error("Unknown VFX block: %s" % block_id)
		return null
	_enforce_budget()
	var block := (script.new() as VfxBlock).configure(params, self)
	block.name = block_id
	add_child(block)
	return block


## Floating number anchored on a target. kind: "normal", "crit", "heal", "absorbed".
func number(target: Variant, amount: int, kind: String = "normal") -> void:
	numbers.show_number(target, amount, kind, reduce_motion)


## 60 ms white flash on every mesh under `target`.
func flash(target: Node, color: Color = Color.WHITE, duration_s: float = 0.06) -> void:
	VfxHitFlash.flash(target, color, duration_s)


func particle_scale() -> float:
	return particle_factor(reduce_motion, quality)


## Particle budget factor: halved by reduced motion, halved again at low quality.
static func particle_factor(reduced: bool, level: int) -> float:
	var k := 1.0
	if reduced:
		k *= 0.5
	if level <= 0:
		k *= 0.5
	return k


func request_hit_stop(duration_s: float) -> void:
	if duration_s > 0.0 and not reduce_motion:
		hit_stop_requested.emit(duration_s)


func request_shake(trauma: float) -> void:
	if trauma > 0.0 and not reduce_motion:
		shake_requested.emit(trauma)


## Stops every live effect (end of encounter, scene change).
func stop_all() -> void:
	for c in get_children():
		if c is VfxSequence:
			(c as VfxSequence).cancel()
		elif c is VfxBlock:
			(c as VfxBlock).stop()


## Live blocks and their particle count (for the performance overlay of the preview).
func stats() -> Dictionary:
	var blocks := 0
	var parts := 0
	var meshes := 0
	for c in get_children():
		if c is VfxBlock:
			blocks += 1
			for n in c.find_children("*", "GeometryInstance3D", true, false):
				if n is CPUParticles3D:
					parts += (n as CPUParticles3D).amount
				meshes += 1
	return {"blocks": blocks, "particles": parts, "layers": meshes}


## Draws every VFX shader once, invisibly, in front of `camera` so the first real cast does not
## stall on shader compilation (WebGL compiles on first use).
func prewarm(camera: Camera3D) -> void:
	var at := camera.global_position - camera.global_basis.z * 3.0
	var ids := ["burst", "beam", "cast_circle", "shield", "telegraph", "status", "projectile"]
	for id: String in ids:
		var params := {"position": at, "from": at, "to": at + Vector3.RIGHT, "intensity": 0.0}
		params["kind"] = "shock"
		params["duration"] = 0.05
		var b := spawn_block(id, params)
		if b:
			b.life = 0.05


func _enforce_budget() -> void:
	var live: Array[VfxBlock] = []
	for c in get_children():
		if c is VfxBlock and not (c as VfxBlock).is_stopping():
			live.append(c)
	if live.size() >= max_live_blocks:
		live[0].stop()
