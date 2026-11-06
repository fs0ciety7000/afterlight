class_name CombatAi
extends RefCounted
## Decisions of every unit, once per tick, after casts progressed.
## Party (GDD §7.2): manual move > dodge > queued player spell > tactics >
## auto-attack or approach. Shield spells may fire during another cast.
## Enemies (GDD §9.1): shared state machine aggro -> approach -> attack <->
## ability, profile from ai_profiles.json (target rule, kiting, priorities).

const WAIT_REASONS := ["casting", "moving", "cc", "out_of_range"]
const EXPIRING_REASONS := ["cooldown", "gcd"]

# --- Party --------------------------------------------------------------------


static func think_party(sim: CombatSim, u: Dictionary) -> void:
	if not u["alive"]:
		return
	u["moving"] = false
	_auto_shield(sim, u)
	_auto_consumable(sim, u)
	_try_queued(sim, u, true)
	if not u["cast"].is_empty() or CombatRules.is_cc(sim, u) or u["manual"]:
		# A spell asked during a cast, a stun or a move leaves right after it.
		if not u["queued"].is_empty():
			u["queued"]["expires"] = sim.tick + BalanceCombat.ticks(BalanceCombat.INPUT_BUFFER_S)
		if u["manual"] and u["cast"].is_empty() and not CombatRules.is_cc(sim, u):
			_manual_move(sim, u)
		return
	if _dodge(sim, u):
		return
	_update_target(sim, u)
	if _try_queued(sim, u, false):
		return
	if _auto_spells(sim, u):
		return
	_attack_or_approach(sim, u)


## Player spell waiting in the input buffer. `busy_only`: only spells that
## may start during another action (instant, off the global cooldown).
static func _try_queued(sim: CombatSim, u: Dictionary, busy_only: bool) -> bool:
	var q: Dictionary = u["queued"]
	if q.is_empty():
		return false
	var spell: Dictionary = sim.def(q["spell"])
	if busy_only and not (spell.get("ignores_gcd", false) and CombatActions.is_instant(spell)):
		return false
	var r := CombatActions.check_cast(sim, u, q["spell"], q["target"])
	var reason: String = r["reason"]
	if reason == "":
		u["queued"] = {}
		CombatActions.start_spell(sim, u, q["spell"], r["target"])
		return true
	if busy_only:
		return false
	if WAIT_REASONS.has(reason):
		q["expires"] = sim.tick + BalanceCombat.ticks(BalanceCombat.INPUT_BUFFER_S)
		if reason == "out_of_range" and r["target"] != "":
			var range_m := float(spell.get("range_m", 0.0))
			_approach(sim, u, sim.unit(r["target"]), range_m)
			return true
		return false
	if EXPIRING_REASONS.has(reason) and sim.tick <= int(q["expires"]):
		return false
	u["queued"] = {}
	sim.reject(u, "cast", q["spell"], "expired" if EXPIRING_REASONS.has(reason) else reason)
	return false


static func _manual_move(sim: CombatSim, u: Dictionary) -> void:
	var target := Vector2(u["move"]["x"], u["move"]["z"])
	var step := CombatRules.move_speed_of(sim, u) * BalanceCombat.TICK_SECONDS
	u["moving"] = true
	u["ai_state"] = "move"
	if CombatGeometry.step_towards(u, target, step):
		u["manual"] = false
		u["moving"] = false
		u["move"] = {}
		u["hold"] = BalanceCombat.ticks(BalanceCombat.REPOSITION_HOLD_S)
		u["ai_state"] = "hold"
		(
			sim
			. emit(
				"hold_started",
				{
					"unit": u["uid"],
					"position": [snappedf(u["x"], 0.01), snappedf(u["z"], 0.01)],
					"duration_s": BalanceCombat.REPOSITION_HOLD_S,
				}
			)
		)


## Steps out of a hostile telegraph (after ALLY_DODGE_REACTION_S, only if
## the exit is reachable before impact) or out of a hostile ground zone.
static func _dodge(sim: CombatSim, u: Dictionary) -> bool:
	var p := CombatGeometry.pos(u)
	var speed := CombatRules.move_speed_of(sim, u)
	var react := BalanceCombat.ticks(BalanceCombat.ALLY_DODGE_REACTION_S)
	if speed <= 0.0:
		return false
	for tg in sim.telegraphs:
		if tg["attached_to"] != "" or sim.unit(tg["source"]).get("side", "") == u["side"]:
			continue
		if int(tg["total"]) - int(tg["remaining"]) < react:
			continue
		if not CombatGeometry.shape_contains(tg, p):
			continue
		var exit := CombatGeometry.escape_point(tg, p)
		var need := p.distance_to(exit) / speed
		if need <= float(tg["remaining"]) * BalanceCombat.TICK_SECONDS + 0.000001:
			return _dodge_to(sim, u, exit, speed)
	for z in sim.zones:
		if z["side"] == u["side"] or int(z["total"]) - int(z["remaining"]) < react:
			continue
		var shape := {"shape": "circle", "size_m": z["radius_m"], "x": z["x"], "z": z["z"]}
		if CombatGeometry.shape_contains(shape, p):
			return _dodge_to(sim, u, CombatGeometry.escape_point(shape, p), speed)
	return false


static func _dodge_to(_sim: CombatSim, u: Dictionary, exit: Vector2, speed: float) -> bool:
	CombatGeometry.step_towards(u, exit, speed * BalanceCombat.TICK_SECONDS)
	u["moving"] = true
	u["ai_state"] = "dodge"
	return true


static func _update_target(sim: CombatSim, u: Dictionary) -> void:
	var focus: Dictionary = sim.unit(u["focus"])
	if not focus.is_empty() and focus["alive"]:
		u["target"] = u["focus"]
		return
	var current: Dictionary = sim.unit(u["target"])
	if not current.is_empty() and current["alive"] and not u.get("retarget", false):
		return
	u["retarget"] = false
	var best: Dictionary = {}
	var best_key := []
	var rule: String = sim.tactics["targeting"]
	for e in sim.hostiles(u):
		var d := CombatGeometry.dist(u, e)
		var key := [d]
		match rule:
			"lowest_hp":
				key = [e["hp"], d]
			"elites_first":
				key = [0 if e["archetype"] in ["elite", "boss"] else 1, d]
			"casters_first":
				key = [0 if e["archetype"] == "caster" else 1, d]
		if best.is_empty() or key < best_key:
			best = e
			best_key = key
	u["target"] = best.get("uid", "")


static func _reserve_ok(sim: CombatSim, u: Dictionary, spell: Dictionary) -> bool:
	var reserve := float(sim.tactics["mana_reserve"]) * float(u["max_mana"])
	return float(u["mana"]) - CombatActions.spell_cost(u, spell) >= reserve - 0.000001


static func _auto_shield(sim: CombatSim, u: Dictionary) -> void:
	for id in u["spells"]:
		var spell: Dictionary = sim.def(id)
		if CombatTactics.role_of(spell) != "shield":
			continue
		var mode: String = sim.tactics["spells"].get(id, "manual")
		var low_hp := float(u["hp"]) < float(sim.tactics["barrier_hp_pct"]) * float(u["max_hp"])
		var wanted := false
		match mode:
			"auto_hp_below":
				wanted = low_hp
			"auto_before_telegraph":
				wanted = incoming_big_hit(sim, u)
			"auto_telegraph_or_hp":
				wanted = incoming_big_hit(sim, u) or low_hp
		if wanted and CombatActions.check_cast(sim, u, id)["reason"] == "":
			CombatActions.start_spell(sim, u, id, u["uid"])


## Consumables on an automatic tactic: healing first, then mana (one shared
## cooldown). Only the leader carries consumables.
static func _auto_consumable(sim: CombatSim, u: Dictionary) -> void:
	var modes: Dictionary = sim.tactics.get("consumables", {})
	var low_hp := float(u["hp"]) < BalanceCombat.TACTIC_HEAL_HP_PCT * float(u["max_hp"])
	var low_mana := float(u["mana"]) < BalanceCombat.TACTIC_ELIXIR_MANA_PCT * float(u["max_mana"])
	for wanted in [["auto_low_hp", low_hp], ["auto_low_mana", low_mana]]:
		if not wanted[1]:
			continue
		var ids: Array = modes.keys()
		ids.sort()
		for id in ids:
			if modes[id] == wanted[0] and sim.can_use_consumable(u, id):
				sim.use_consumable(u, id)
				return


## A hostile telegraph that will hit `u` within TACTIC_BARRIER_PRECAST_S:
## attached to it, or a zone it stands in and cannot leave in time.
static func incoming_big_hit(sim: CombatSim, u: Dictionary) -> bool:
	var window := BalanceCombat.ticks(BalanceCombat.TACTIC_BARRIER_PRECAST_S)
	var p := CombatGeometry.pos(u)
	for tg in sim.telegraphs:
		if sim.unit(tg["source"]).get("side", "") == u["side"] or int(tg["remaining"]) > window:
			continue
		if tg["attached_to"] == u["uid"]:
			return true
		if tg["attached_to"] == "" and CombatGeometry.shape_contains(tg, p):
			var exit := CombatGeometry.escape_point(tg, p)
			var speed := maxf(0.01, CombatRules.move_speed_of(sim, u))
			if p.distance_to(exit) / speed > float(tg["remaining"]) * BalanceCombat.TICK_SECONDS:
				return true
	return false


static func _auto_spells(sim: CombatSim, u: Dictionary) -> bool:
	var ids: Array = u["spells"].duplicate()
	if u["ultimate"] != "":
		ids.append(u["ultimate"])
	for id in ids:
		var spell: Dictionary = sim.def(id)
		var mode: String = sim.tactics["spells"].get(id, "manual")
		if mode == "manual" or CombatTactics.role_of(spell) == "shield":
			continue
		var is_ult: bool = id == u["ultimate"]
		if not is_ult and not _reserve_ok(sim, u, spell):
			continue
		var target := _auto_target(sim, u, spell, mode)
		if target == "":
			continue
		var r := CombatActions.check_cast(sim, u, id, target)
		if r["reason"] == "":
			CombatActions.start_spell(sim, u, id, r["target"])
			return true
		if r["reason"] == "out_of_range" and mode == "auto_interrupt":
			_approach(sim, u, sim.unit(target), float(spell.get("range_m", 0.0)))
			return true
	return false


## Target an automatic spell would use in `mode`, or "" to skip it.
static func _auto_target(sim: CombatSim, u: Dictionary, spell: Dictionary, mode: String) -> String:
	var current: Dictionary = sim.unit(u["target"])
	var out := ""
	match mode:
		"auto", "auto_full":
			out = u["target"]
			if mode == "auto" and spell.get("interrupts", false):
				var caster := _interrupt_target(sim, u, spell)
				out = caster if caster != "" else out
		"auto_elite_boss":
			if not current.is_empty() and current["archetype"] in ["elite", "boss"]:
				out = u["target"]
		"auto_min_enemies":
			var n := sim.hostiles_in_range(u, float(spell.get("range_m", 0.0))).size()
			if n >= int(sim.tactics["min_enemies"]):
				out = u["target"]
		"auto_interrupt":
			out = _interrupt_target(sim, u, spell)
	return out


## Nearest enemy casting something interruptible that would still be
## casting when this spell lands.
static func _interrupt_target(sim: CombatSim, u: Dictionary, spell: Dictionary) -> String:
	var cast_ticks := BalanceCombat.ticks(
		BalanceCombat.hasted(float(spell.get("cast_s", 0.0)), CombatRules.haste_of(u))
	)
	var best := ""
	var best_d := INF
	for e in sim.hostiles(u):
		var c: Dictionary = e["cast"]
		if c.is_empty() or not c.get("interruptible", false):
			continue
		if int(c["total"]) - int(c["elapsed"]) <= cast_ticks:
			continue
		var d := CombatGeometry.dist(u, e)
		if d < best_d:
			best = e["uid"]
			best_d = d
	return best


static func _attack_or_approach(sim: CombatSim, u: Dictionary) -> void:
	var t: Dictionary = sim.unit(u["target"])
	if t.is_empty() or not t["alive"]:
		u["ai_state"] = "idle"
		return
	var range_m := float(sim.def(u["attack"]).get("range_m", 0.0))
	if int(u["hold"]) > 0 and CombatGeometry.dist(u, t) > range_m:
		var near := sim.hostiles_in_range(u, range_m)
		if near.is_empty():
			u["hold"] = 0
		else:
			t = near[0]
			u["target"] = t["uid"]
	if CombatGeometry.dist(u, t) <= range_m:
		if int(u["attack_timer"]) <= 0:
			CombatActions.perform_attack(sim, u, t)
		u["ai_state"] = "hold" if int(u["hold"]) > 0 else "attack"
		return
	_approach(sim, u, t, range_m)


static func _approach(sim: CombatSim, u: Dictionary, t: Dictionary, range_m: float) -> void:
	if t.is_empty():
		return
	var goal := CombatGeometry.point_at_distance(
		CombatGeometry.pos(t),
		CombatGeometry.pos(u),
		maxf(0.0, range_m - BalanceCombat.RANGE_MARGIN_M)
	)
	CombatGeometry.step_towards(
		u, goal, CombatRules.move_speed_of(sim, u) * BalanceCombat.TICK_SECONDS
	)
	u["moving"] = true
	u["ai_state"] = "approach"


# --- Enemies ------------------------------------------------------------------


static func think_enemy(sim: CombatSim, u: Dictionary) -> void:
	if not u["alive"]:
		return
	u["moving"] = false
	if not u["cast"].is_empty() or CombatRules.is_cc(sim, u):
		return
	var profile: Dictionary = sim.def(u["ai_profile"])
	var t := _enemy_target(sim, u, str(profile.get("target_rule", "nearest")))
	if t.is_empty():
		u["ai_state"] = "idle"
		return
	u["target"] = t["uid"]
	var available := CombatRules.abilities_of(u)
	var order: Array = profile.get("ability_priority", []).duplicate()
	for id in available:
		if not order.has(id):
			order.append(id)
	for id in order:
		if available.has(id) and CombatActions.ability_ready(sim, u, id, t):
			CombatActions.begin_ability(sim, u, id, t)
			return
	var range_m := float(sim.def(u["attack"]).get("range_m", 0.0))
	var d := CombatGeometry.dist(u, t)
	var keep := float(profile.get("keep_distance_m", 0.0))
	var flee := float(profile.get("flee_below_m", 0.0))
	var speed := CombatRules.move_speed_of(sim, u) * BalanceCombat.TICK_SECONDS
	if flee > 0.0 and d < flee:
		u["kiting"] = true
	if u["kiting"]:
		if d >= keep:
			u["kiting"] = false
		else:
			var away := CombatGeometry.point_at_distance(
				CombatGeometry.pos(t), CombatGeometry.pos(u), keep
			)
			CombatGeometry.step_towards(u, away, speed)
			u["moving"] = true
			u["ai_state"] = "kite"
			return
	if d > range_m:
		var stand := range_m - BalanceCombat.RANGE_MARGIN_M
		if keep > 0.0:
			stand = minf(stand, keep)
		var goal := CombatGeometry.point_at_distance(
			CombatGeometry.pos(t), CombatGeometry.pos(u), maxf(0.0, stand)
		)
		CombatGeometry.step_towards(u, goal, speed)
		u["moving"] = true
		u["ai_state"] = "approach"
		return
	u["ai_state"] = "attack"
	if int(u["attack_timer"]) <= 0:
		CombatActions.perform_attack(sim, u, t)


static func _enemy_target(sim: CombatSim, u: Dictionary, rule: String) -> Dictionary:
	var best: Dictionary = {}
	var best_key := []
	for p in sim.hostiles(u):
		var d := CombatGeometry.dist(u, p)
		var key := [d]
		match rule:
			"lowest_hp":
				key = [p["hp"], d]
			"furthest":
				key = [-d]
			"front_row":
				key = [0 if p["row"] == "front" else 1, d]
		if best.is_empty() or key < best_key:
			best = p
			best_key = key
	return best
