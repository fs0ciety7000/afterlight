class_name CombatFx
extends RefCounted
## Turns combat events into effects (docs/VFX.md §9). Rendering only: it
## reads events and plays recipes; the simulation already decided everything.

const BOSS_HIT_STOP_S := 0.06
const BOSS_SHAKE := 0.6
const CRIT_HIT_STOP_S := 0.045
const CRIT_SHAKE := 0.35

var vfx: Vfx
var view: CombatView
## uid -> VfxSequence of the cast in progress; telegraph id -> sequence;
## "uid|status" -> looping status sequence.
var _casts := {}
var _telegraphs := {}
var _statuses := {}


func _init(vfx_node: Vfx, combat: CombatView) -> void:
	vfx = vfx_node
	view = combat


func handle(e: Dictionary) -> void:
	match e["type"]:
		"spell_cast":
			_on_cast(e)
		"attack_started":
			_on_attack(e)
		"cast_interrupted":
			_cancel(_casts, e["unit"])
			_play("vfx.hit", {"target": view.actor(e["unit"]), "element": "arcane"})
		"telegraph_started":
			_on_telegraph(e)
		"telegraph_ended":
			_cancel(_telegraphs, e["id"])
		"damage_dealt":
			_on_damage(e)
		"character_healed":
			var t := view.actor(e["target"])
			_play("vfx.heal", {"target": t})
			if t:
				vfx.number(t, int(e["amount"]), "heal")
		"status_applied":
			var key: String = "%s|%s" % [e["target"], e["status"]]
			_cancel(_statuses, key)
			var recipe := "vfx.status_" + str(e["status"]).get_slice(".", 1)
			var seq := _play(
				recipe, {"target": view.actor(e["target"]), "duration": e.get("duration_s", 3.0)}
			)
			if seq:
				_statuses[key] = seq
		"status_expired":
			_cancel(_statuses, "%s|%s" % [e["target"], e["status"]])
		"enemy_defeated":
			var family: String = Content.get_entity(e.get("def_id", "")).get("family", "beast")
			var death := "vfx.death_ash" if family in ["demon", "construct"] else "vfx.death_mist"
			_play(death, {"target": view.actor(e["unit"])})
			_cancel(_casts, e["unit"])
		"encounter_completed":
			for d in [_casts, _telegraphs, _statuses]:
				for k in d.keys():
					_cancel(d, k)


func _on_cast(e: Dictionary) -> void:
	var spell := Content.get_entity(e["spell"])
	var recipe: String = spell.get("vfx", "")
	if recipe == "":
		return
	var caster := view.actor(e["unit"])
	var ctx := {
		"caster": caster,
		"element": spell.get("element", "arcane"),
		"cast_s": float(e.get("cast_s", 0.0)),
		"channel_s": float(e.get("channel_s", 0.0)),
		"seed": int(e.get("tick", 0)),
	}
	var targets := _targets(e)
	if targets.size() > 1:
		ctx["targets"] = targets
	elif targets.size() == 1:
		ctx["target"] = targets[0]
	_cancel(_casts, e["unit"])
	var seq := _play(recipe, ctx)
	if seq:
		_casts[e["unit"]] = seq


## Auto attacks with a projectile recipe (Fern's mana bolt, lantern bolt).
func _on_attack(e: Dictionary) -> void:
	var spell := Content.get_entity(e["spell"])
	var recipe: String = spell.get("vfx", "")
	if recipe == "" or float(e.get("travel_s", 0.0)) <= 0.0:
		return
	_play(
		recipe,
		{
			"caster": view.actor(e["unit"]),
			"target": view.actor(e["target"]),
			"element": spell.get("element", "arcane"),
			"seed": int(e.get("tick", 0)),
		}
	)


func _on_telegraph(e: Dictionary) -> void:
	var shape: String = e.get("shape", "circle")
	var size := float(e.get("size_m", 2.0))
	var overrides := {"telegraph": {}}
	if shape == "circle":
		overrides["telegraph"]["radius"] = size
	else:
		overrides["telegraph"]["length"] = size
		overrides["telegraph"]["width"] = float(e.get("width_m", 1.5))
	var at := view.to_world(e["position"])
	var dir: Array = e.get("direction", [0, -1])
	var ahead := view.to_world(
		[float(e["position"][0]) + float(dir[0]), float(e["position"][1]) + float(dir[1])]
	)
	var seq := _play(
		"vfx.telegraph_" + shape,
		{
			"caster": at,
			"target": ahead,
			"cast_s": float(e.get("duration_s", 0.6)),
			"overrides": overrides,
		}
	)
	if seq:
		_telegraphs[e["id"]] = seq


func _on_damage(e: Dictionary) -> void:
	var target := view.actor(e["target"])
	if target == null:
		return
	var amount := int(e.get("amount", 0))
	var absorbed := int(e.get("absorbed", 0))
	var crit: bool = e.get("crit", false)
	if int(e.get("hp_damage", amount)) <= 0 and absorbed > 0:
		vfx.number(target, absorbed, "absorbed")
		var shield := _casts.get(e["target"]) as VfxSequence
		if shield and shield.has_method("find_block") and shield.find_block("shield"):
			shield.find_block("shield").call(
				"hit",
				(
					view.actor(e["source"]).global_position
					if view.actor(e["source"])
					else target.global_position
				)
			)
		return
	vfx.number(target, amount, "crit" if crit else "normal")
	vfx.flash(target)
	var spell := Content.get_entity(e.get("spell", ""))
	var element: String = e.get("element", spell.get("element", "arcane"))
	if crit:
		_play("vfx.crit", {"target": target, "element": element})
		vfx.request_hit_stop(CRIT_HIT_STOP_S)
		vfx.request_shake(CRIT_SHAKE)
	elif spell.get("vfx", "") == "":
		_play("vfx.hit", {"target": target, "element": element})
	var source := view.snapshot_unit(e.get("source", ""))
	if source.get("is_boss", false):
		vfx.request_hit_stop(BOSS_HIT_STOP_S)
		vfx.request_shake(BOSS_SHAKE)


func _targets(e: Dictionary) -> Array:
	var out := []
	var t: String = str(e.get("target", ""))
	if t != "":
		var node := view.actor(t)
		if node:
			out.append(node)
	if out.is_empty():
		# Area or distributed spells: every living enemy of the caster.
		var caster := view.snapshot_unit(e["unit"])
		for u in view.snapshot().get("units", []):
			if u["alive"] and u["side"] != caster.get("side", "") and view.actor(u["uid"]):
				out.append(view.actor(u["uid"]))
	return out


func _play(recipe: String, ctx: Dictionary) -> VfxSequence:
	if not VfxRecipes.has(recipe):
		return null
	for key in ["caster", "target"]:
		if ctx.has(key) and ctx[key] == null:
			return null
	return vfx.play(recipe, ctx) as VfxSequence


func _cancel(store: Dictionary, key: Variant) -> void:
	var seq: Variant = store.get(key)
	if seq != null and is_instance_valid(seq):
		(seq as VfxSequence).cancel()
	store.erase(key)
