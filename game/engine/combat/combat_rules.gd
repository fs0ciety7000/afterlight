class_name CombatRules
extends RefCounted
## Hit resolution, statuses, shields, heals, deaths and boss phases. Every
## number comes from BalanceCombat / BalanceStatuses / content; every visible
## change emits an event through the simulation.

const CC_KINDS := ["cc"]
const HARMFUL_KINDS := ["cc", "dot", "debuff"]

# --- Effective stats ----------------------------------------------------------


## Sum of status modifiers on `stat` of `kind` ("percent" or "flat").
static func stat_mod(
	sim: CombatSim, u: Dictionary, stat: String, kind: String = "percent"
) -> float:
	var total := 0.0
	for id in u["statuses"]:
		var def: Dictionary = sim.def(id)
		for m in def.get("modifiers", []):
			if m["stat"] == stat and m["kind"] == kind:
				total += float(m["value"]) * int(u["statuses"][id]["stacks"])
	return total


static func power_of(sim: CombatSim, u: Dictionary) -> float:
	return maxf(
		0.0,
		(
			(float(u["stats"]["power"]) + stat_mod(sim, u, "power", "flat"))
			* (1.0 + stat_mod(sim, u, "power"))
		)
	)


static func defense_of(sim: CombatSim, u: Dictionary) -> float:
	return maxf(0.0, float(u["stats"]["defense"]) * (1.0 + stat_mod(sim, u, "defense")))


static func haste_of(u: Dictionary) -> float:
	return clampf(float(u["stats"]["haste"]) + float(u["haste_bonus"]), 0.0, BalanceStats.HASTE_CAP)


## Multiplier of the auto-attack rate from statuses (Chill, Frenzy).
static func attack_speed_of(sim: CombatSim, u: Dictionary) -> float:
	return maxf(0.1, 1.0 + stat_mod(sim, u, "attack_speed"))


static func move_speed_of(sim: CombatSim, u: Dictionary) -> float:
	return maxf(0.0, float(u["stats"]["move_speed"]) * (1.0 + stat_mod(sim, u, "move_speed")))


static func is_cc(sim: CombatSim, u: Dictionary) -> bool:
	for id in u["statuses"]:
		if CC_KINDS.has(sim.def(id).get("kind", "")):
			return true
	return false


## Damage taken reduction of a unit (bound lanterns), capped.
static func reduction_of(sim: CombatSim, u: Dictionary) -> float:
	var total := 0.0
	for other in sim.units:
		if other["alive"] and other["summoner"] == u["uid"]:
			total += float(other["link_reduction"])
	return minf(total, BalanceCombat.ENEMY_DAMAGE_REDUCTION_CAP)


static func affinity_of(u: Dictionary, element: String) -> float:
	return BalanceCombat.affinity_mult(str(u["affinities"].get(element, "neutral")))


# --- Hits ---------------------------------------------------------------------


## Frozen copy of everything a hit needs from its source, so a projectile
## still lands with the right numbers if its source dies meanwhile.
static func make_hit(
	sim: CombatSim, source: Dictionary, spell: Dictionary, effect: Dictionary, opts: Dictionary = {}
) -> Dictionary:
	var stats: Dictionary = source["stats"]
	var mods: Dictionary = source.get("mods", {}).get(spell["id"], {})
	var element: String = mods.get("element", spell.get("element", "arcane"))
	var bonus := (
		float(stats["damage_bonus"])
		+ float(stats.get("element_bonus_" + element, 0.0))
		+ float(mods.get("damage_bonus", 0.0))
		+ float(opts.get("bonus", 0.0))
	)
	var statuses := []
	for e in spell.get("effects", []):
		if e["type"] == "apply_status" and spell.get("kind", "") in ["attack", "auto"]:
			statuses.append({"status": e["status"], "chance": float(e.get("chance", 1.0))})
	if mods.has("status_chance") and BalanceStatuses.ELEMENT_STATUS.has(element):
		statuses.append(
			{"status": BalanceStatuses.ELEMENT_STATUS[element], "chance": mods["status_chance"]}
		)
	return {
		"source": source["uid"],
		"source_side": source["side"],
		"spell": spell["id"],
		"kind": spell.get("kind", ""),
		"power": power_of(sim, source),
		"level": int(source["level"]),
		"coeff": float(effect.get("coeff", 0.0)),
		"rank": int(source.get("ranks", {}).get(spell["id"], 1)),
		"bonus": bonus,
		"element": element,
		"crit_chance": float(stats["crit_chance"]),
		"crit_damage": float(stats["crit_damage"]),
		"crit_bonus": float(mods.get("crit_bonus", 0.0)),
		"can_crit": opts.get("can_crit", true),
		"variance": opts.get("variance", true),
		"reactions": opts.get("reactions", true),
		"interrupt": opts.get("interrupt", false),
		"statuses": statuses,
	}


## Resolves one hit on `target`: reaction, shock, crit, variance, absorb,
## damage, interrupt, statuses, overload. Emits damage_dealt.
static func apply_hit(sim: CombatSim, hit: Dictionary, target: Dictionary) -> void:
	if not target["alive"]:
		return
	var element: String = hit["element"]
	var reaction := ""
	var react_mult := 1.0
	var st: Dictionary = target["statuses"]
	if hit["reactions"]:
		if element == "fire" and st.has(BalanceStatuses.FROZEN):
			reaction = "melt"
			react_mult = BalanceCombat.REACTION_MELT_MULT
			remove_status(sim, target, BalanceStatuses.FROZEN, "reaction")
		elif element == "lightning" and st.has(BalanceStatuses.BURN):
			reaction = "overload"
		elif element == "frost" and st.has(BalanceStatuses.BURN):
			reaction = "extinguish"
			remove_status(sim, target, BalanceStatuses.BURN, "reaction")
	var shock := 0.0
	if st.has(BalanceStatuses.SHOCK) and element != "lightning":
		shock = BalanceCombat.SHOCK_BONUS
		remove_status(sim, target, BalanceStatuses.SHOCK, "consumed")
	var crit_roll := sim.rng.next_float()
	var var_roll := sim.rng.next_float()
	var crit: bool = (
		hit["can_crit"] and BalanceCombat.is_crit(crit_roll, hit["crit_chance"], hit["crit_bonus"])
	)
	var raw := BalanceCombat.raw_damage(hit["power"], hit["coeff"], hit["rank"], hit["bonus"])
	var final := BalanceCombat.final_damage(
		raw,
		BalanceCombat.mitigation(hit["level"], defense_of(sim, target)),
		affinity_of(target, element),
		react_mult,
		shock,
		float(hit["crit_damage"]) if crit else 1.0,
		BalanceCombat.variance_from_roll(var_roll) if hit["variance"] else 1.0,
		float(target["stats"]["resist_all"]),
		reduction_of(sim, target)
	)
	var dealt := deal_damage(sim, target, final, element, hit["source"])
	(
		sim
		. emit(
			"damage_dealt",
			{
				"source": hit["source"],
				"target": target["uid"],
				"spell": hit["spell"],
				"amount": dealt["amount"],
				"hp_damage": dealt["hp_damage"],
				"absorbed": dealt["absorbed"],
				"crit": crit,
				"element": element,
				"reaction": reaction,
				"shock": shock > 0.0,
				"hp": maxi(0, target["hp"] - dealt["hp_damage"]),
			}
		)
	)
	_after_hit(sim, hit, target, reaction, dealt)


static func _after_hit(
	sim: CombatSim, hit: Dictionary, target: Dictionary, reaction: String, dealt: Dictionary
) -> void:
	var source: Dictionary = sim.unit(hit["source"])
	if hit["kind"] == "auto" and not source.is_empty() and source["alive"]:
		source["mana"] = minf(source["max_mana"], source["mana"] + BalanceCombat.AUTO_MANA_RESTORE)
		add_ult_charge(source, BalanceCombat.ULT_CHARGE_PER_AUTO)
	lose_hp(sim, target, int(dealt["hp_damage"]), hit["source"], hit["spell"])
	if not target["alive"]:
		return
	if hit["interrupt"] and target["cast"].get("interruptible", false):
		interrupt(sim, target, hit["source"])
	if hit["element"] == "lightning" and hit["reactions"]:
		if target["statuses"].has(BalanceStatuses.SHOCK):
			apply_status(sim, target, BalanceStatuses.SHOCK, hit)
	for s in hit["statuses"]:
		if sim.rng.next_float() < float(s["chance"]):
			apply_status(sim, target, s["status"], hit)
	if reaction == "overload":
		_overload(sim, hit, target)


static func _overload(sim: CombatSim, hit: Dictionary, target: Dictionary) -> void:
	var burn: Dictionary = target["statuses"].get(BalanceStatuses.BURN, {})
	if not burn.is_empty():
		burn["stacks"] = int(burn["stacks"]) - 1
		if burn["stacks"] <= 0:
			remove_status(sim, target, BalanceStatuses.BURN, "reaction")
	var blast := hit.duplicate()
	blast["coeff"] = BalanceCombat.REACTION_OVERLOAD_COEFF
	blast["rank"] = 1
	blast["bonus"] = 0.0
	blast["can_crit"] = false
	blast["variance"] = false
	blast["reactions"] = false
	blast["interrupt"] = false
	blast["statuses"] = []
	blast["kind"] = "reaction"
	blast["spell"] = "reaction.overload"
	var center := CombatGeometry.pos(target)
	for u in sim.units.duplicate():
		if u["alive"] and u["side"] == target["side"]:
			if (
				CombatGeometry.pos(u).distance_to(center)
				<= BalanceCombat.REACTION_OVERLOAD_RADIUS_M
			):
				apply_hit(sim, blast, u)


## Splits `final` between shield or barrier and HP. Returns {amount (shown),
## hp_damage (int), absorbed (int)}. Arcane hits count double on barriers.
static func deal_damage(
	sim: CombatSim, target: Dictionary, final: float, element: String, source_uid: String
) -> Dictionary:
	var amount := BalanceCombat.round_damage(final)
	var absorbed := 0.0
	var hp_part := final
	if float(target["shield"]) > 0.0:
		var r := BalanceCombat.absorb(hp_part, target["shield"])
		absorbed += r["absorbed"]
		target["shield"] = r["layer_left"]
		hp_part = r["hp_damage"]
		if target["shield"] <= 0.0:
			remove_status(sim, target, BalanceStatuses.SHIELD, "depleted")
	if float(target["barrier"]) > 0.0:
		var mult := BalanceCombat.BARRIER_ARCANE_MULT if element == "arcane" else 1.0
		var r := BalanceCombat.absorb(hp_part, target["barrier"], mult)
		absorbed += r["absorbed"] / mult
		target["barrier"] = r["layer_left"]
		hp_part = r["hp_damage"]
		if target["barrier"] <= 0.0:
			sim.emit("barrier_broken", {"unit": target["uid"], "source": source_uid})
	if element == "arcane":
		target["barrier_timer"] = 0
	var hp_damage := amount if absorbed <= 0.0 else roundi(hp_part)
	return {"amount": amount, "hp_damage": hp_damage, "absorbed": roundi(absorbed)}


## Removes HP (already mitigated) and handles ultimate charge, death and
## boss phases.
static func lose_hp(
	sim: CombatSim, target: Dictionary, amount: int, source_uid: String, spell_id: String
) -> void:
	if amount <= 0 or not target["alive"]:
		return
	var before: int = target["hp"]
	target["hp"] = maxi(0, before - amount)
	if target["side"] == "party":
		add_ult_charge(
			target,
			BalanceCombat.ult_charge_from_damage(
				before - target["hp"], target["max_hp"], target["row"] == "front"
			)
		)
		sim.last_hit = {"source": source_uid, "spell": spell_id, "target": target["uid"]}
	if target["hp"] <= 0:
		kill(sim, target, source_uid)
	else:
		check_phase(sim, target)


static func add_ult_charge(u: Dictionary, amount: float) -> void:
	if u.has("ult_charge") and u.get("ultimate", "") != "":
		u["ult_charge"] = minf(BalanceCombat.ULT_CHARGE_MAX, float(u["ult_charge"]) + amount)


static func kill(sim: CombatSim, u: Dictionary, killer: String) -> void:
	u["alive"] = false
	u["hp"] = 0
	u["shield"] = 0.0
	u["barrier"] = 0.0
	if not u["cast"].is_empty():
		CombatActions.cancel_cast(sim, u, "death", killer)
	u["statuses"] = {}
	u["moving"] = false
	u["ai_state"] = "dead"
	var event := "enemy_defeated" if u["side"] == "enemy" else "character_defeated"
	sim.emit(event, {"unit": u["uid"], "def_id": u["def_id"], "killer": killer})
	if u["side"] == "enemy":
		sim.kills.append(u["uid"])
	sim.roster_changed = true
	for other in sim.units:
		if other["focus"] == u["uid"]:
			other["focus"] = ""
		if other["target"] == u["uid"]:
			other["target"] = ""


static func interrupt(sim: CombatSim, target: Dictionary, by: String) -> void:
	CombatActions.cancel_cast(sim, target, "interrupt", by)
	apply_status(sim, target, BalanceStatuses.STUN, {"source": by, "power": 0.0, "level": 1})


static func heal(
	sim: CombatSim, target: Dictionary, amount: float, source_uid: String, spell_id: String
) -> void:
	if not target["alive"]:
		return
	var value := maxi(0, roundi(amount))
	var before: int = target["hp"]
	target["hp"] = mini(target["max_hp"], before + value)
	(
		sim
		. emit(
			"character_healed",
			{
				"source": source_uid,
				"target": target["uid"],
				"spell": spell_id,
				"amount": target["hp"] - before,
				"overheal": value - (target["hp"] - before),
				"hp": target["hp"],
			}
		)
	)


## Shield on a party member: a bigger shield replaces the current one,
## a smaller one only refreshes its duration (§8).
static func apply_shield(
	sim: CombatSim, target: Dictionary, amount: float, duration_s: float, source_uid: String
) -> void:
	target["shield"] = maxf(float(target["shield"]), amount)
	var entry := {"stacks": 1, "remaining": BalanceCombat.ticks(duration_s), "source": source_uid}
	var is_new: bool = not target["statuses"].has(BalanceStatuses.SHIELD)
	target["statuses"][BalanceStatuses.SHIELD] = entry
	(
		sim
		. emit(
			"shield_applied",
			{
				"source": source_uid,
				"target": target["uid"],
				"kind": "shield",
				"amount": snappedf(amount, 0.1),
				"total": snappedf(target["shield"], 0.1),
				"duration_s": duration_s,
			}
		)
	)
	if is_new:
		sim.emit(
			"status_applied",
			{
				"target": target["uid"],
				"status": BalanceStatuses.SHIELD,
				"stacks": 1,
				"duration_s": duration_s,
				"source": source_uid
			}
		)


## Enemy barrier (sentinel, Morvaine's veil): comes back full.
static func restore_barrier(sim: CombatSim, u: Dictionary) -> void:
	u["barrier_max"] = BalanceEnemies.barrier(u["barrier_ratio"], u["max_hp"])
	if u["barrier_max"] <= 0.0:
		return
	u["barrier"] = u["barrier_max"]
	u["barrier_timer"] = 0
	(
		sim
		. emit(
			"shield_applied",
			{
				"source": u["uid"],
				"target": u["uid"],
				"kind": "barrier",
				"amount": snappedf(u["barrier"], 0.1),
				"total": snappedf(u["barrier"], 0.1),
				"duration_s": 0.0,
			}
		)
	)


# --- Statuses -----------------------------------------------------------------


## Applies a status following its stack rule. `source` is a hit (or any
## dictionary with source, power, level).
static func apply_status(
	sim: CombatSim, target: Dictionary, id: String, source: Dictionary
) -> void:
	var def: Dictionary = sim.def(id)
	if def.is_empty() or not target["alive"]:
		return
	if target["immunities"].has(id) or (target["is_boss"] and id == BalanceStatuses.FROZEN):
		return
	var duration := float(def["duration_s"])
	if target["is_boss"]:
		duration *= float(def.get("boss_duration_mult", 1.0))
	if def["kind"] == "cc":
		duration *= 1.0 - float(target.get("cc_resist", 0.0))
	var max_stacks := int(def["max_stacks"])
	if target["is_boss"] and id == BalanceStatuses.CHILL:
		max_stacks = mini(max_stacks, BalanceStatuses.BOSS_CHILL_MAX_STACKS)
	var st: Dictionary = target["statuses"]
	var existing: Dictionary = st.get(id, {})
	if not existing.is_empty() and def["stack_rule"] == "none":
		return
	var stacks := 1
	if def["stack_rule"] == "add_refresh" and not existing.is_empty():
		stacks = mini(max_stacks, int(existing["stacks"]) + 1)
	st[id] = {
		"stacks": stacks,
		"remaining": BalanceCombat.ticks(duration),
		"source": str(source.get("source", "")),
		"power": float(source.get("power", 0.0)),
		"level": int(source.get("level", 1)),
		"tick_timer": int(existing.get("tick_timer", 0)),
	}
	(
		sim
		. emit(
			"status_applied",
			{
				"target": target["uid"],
				"status": id,
				"stacks": stacks,
				"duration_s": snappedf(duration, 0.01),
				"source": str(source.get("source", "")),
			}
		)
	)
	if def["kind"] == "cc" and target["cast"].get("interruptible", false):
		CombatActions.cancel_cast(sim, target, "cc", str(source.get("source", "")))
	var conv: Dictionary = def.get("converts_to", {})
	if not conv.is_empty() and stacks >= int(conv["at_stacks"]):
		var into: String = conv["status"]
		if (
			not target["immunities"].has(into)
			and not (target["is_boss"] and into == BalanceStatuses.FROZEN)
		):
			remove_status(sim, target, id, "converted")
			apply_status(sim, target, into, source)


static func remove_status(sim: CombatSim, target: Dictionary, id: String, reason: String) -> void:
	if not target["statuses"].has(id):
		return
	target["statuses"].erase(id)
	if id == BalanceStatuses.SHIELD:
		target["shield"] = 0.0
	sim.emit("status_expired", {"target": target["uid"], "status": id, "reason": reason})
	var def: Dictionary = sim.def(id)
	if def.has("immunity_after_s") and reason == "expired":
		target["immunities"][id] = BalanceCombat.ticks(float(def["immunity_after_s"]))


## Removes up to `count` harmful statuses (crowd control first, then damage
## over time, then debuffs; ties by id).
static func cleanse(sim: CombatSim, target: Dictionary, count: int) -> void:
	for i in count:
		var best := ""
		var best_rank := 99
		var ids: Array = target["statuses"].keys()
		ids.sort()
		for id in ids:
			var rank := HARMFUL_KINDS.find(sim.def(id).get("kind", ""))
			if rank >= 0 and rank < best_rank:
				best = id
				best_rank = rank
		if best == "":
			return
		remove_status(sim, target, best, "cleansed")


## One tick of every status on `u`: damage over time, expiry, immunities.
static func tick_statuses(sim: CombatSim, u: Dictionary) -> void:
	for id in u["immunities"].keys():
		u["immunities"][id] -= 1
		if u["immunities"][id] <= 0:
			u["immunities"].erase(id)
	for id in u["statuses"].keys():
		if not u["alive"]:
			return
		var entry: Dictionary = u["statuses"].get(id, {})
		if entry.is_empty():
			continue
		var def: Dictionary = sim.def(id)
		if def.get("kind", "") == "dot":
			entry["tick_timer"] += 1
			var every := BalanceCombat.ticks(float(def["tick_s"]))
			if entry["tick_timer"] >= every:
				entry["tick_timer"] = 0
				_dot_tick(sim, u, id, entry, float(def["tick_s"]))
		entry["remaining"] -= 1
		if entry["remaining"] <= 0 and u["statuses"].has(id):
			remove_status(sim, u, id, "expired")


## Burn: BURN_COEFF × power_source per second and per stack, mitigated and
## multiplied by the fire affinity, never critical.
static func _dot_tick(
	sim: CombatSim, u: Dictionary, id: String, entry: Dictionary, tick_s: float
) -> void:
	if not u["alive"]:
		return
	var raw := BalanceStatuses.burn_tick_raw(entry["power"], entry["stacks"], tick_s)
	var final := BalanceCombat.final_damage(
		raw,
		BalanceCombat.mitigation(entry["level"], defense_of(sim, u)),
		affinity_of(u, "fire"),
		1.0,
		0.0,
		1.0,
		1.0,
		float(u["stats"]["resist_all"]),
		reduction_of(sim, u)
	)
	var dealt := deal_damage(sim, u, final, "fire", entry["source"])
	(
		sim
		. emit(
			"damage_dealt",
			{
				"source": entry["source"],
				"target": u["uid"],
				"spell": id,
				"amount": dealt["amount"],
				"hp_damage": dealt["hp_damage"],
				"absorbed": dealt["absorbed"],
				"crit": false,
				"element": "fire",
				"reaction": "",
				"shock": false,
				"hp": maxi(0, u["hp"] - dealt["hp_damage"]),
			}
		)
	)
	lose_hp(sim, u, dealt["hp_damage"], entry["source"], id)


# --- Boss phases --------------------------------------------------------------


## Enters every phase whose threshold the unit's HP has crossed.
static func check_phase(sim: CombatSim, u: Dictionary) -> void:
	var phases: Array = u["phases"]
	while int(u["phase"]) + 1 < phases.size():
		var next: Dictionary = phases[int(u["phase"]) + 1]
		var threshold := float(next["hp_threshold"])
		if float(u["hp"]) > threshold * float(u["max_hp"]):
			return
		enter_phase(sim, u, int(u["phase"]) + 1)


static func enter_phase(sim: CombatSim, u: Dictionary, index: int) -> void:
	var had_barrier := has_barrier_ability(sim, u)
	u["phase"] = index
	var phase: Dictionary = u["phases"][index]
	u["haste_bonus"] = float(phase.get("haste", 0.0))
	for id in phase["abilities"]:
		CombatActions.open_cooldown(sim, u, id)
	(
		sim
		. emit(
			"boss_phase_changed",
			{
				"unit": u["uid"],
				"phase": index + 1,
				"phase_id": phase["id"],
				"hp_pct": snappedf(float(u["hp"]) / float(u["max_hp"]), 0.001),
			}
		)
	)
	if has_barrier_ability(sim, u):
		restore_barrier(sim, u)
	elif had_barrier and u["barrier"] > 0.0:
		u["barrier"] = 0.0
		sim.emit("barrier_broken", {"unit": u["uid"], "source": u["uid"]})
	for effect in phase.get("on_enter", []):
		if effect["type"] == "apply_status":
			apply_status(sim, u, effect["status"], {"source": u["uid"], "power": 0.0})


## Abilities the unit can use now (base list + current phase).
static func abilities_of(u: Dictionary) -> Array:
	var out: Array = u["base_abilities"].duplicate()
	if not u["phases"].is_empty():
		out.append_array(u["phases"][int(u["phase"])]["abilities"])
	return out


static func barrier_ability(sim: CombatSim, u: Dictionary) -> String:
	for id in abilities_of(u):
		if sim.def(id).get("tags", []).has("barrier"):
			return id
	return ""


static func has_barrier_ability(sim: CombatSim, u: Dictionary) -> bool:
	return barrier_ability(sim, u) != ""
