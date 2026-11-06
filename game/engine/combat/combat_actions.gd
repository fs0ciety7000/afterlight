class_name CombatActions
extends RefCounted
## Spells, abilities, auto-attacks, telegraphs, projectiles and ground zones.
## Party spells pay their mana and start their cooldown when they resolve
## (a cast cancelled by moving costs nothing but the global cooldown); the
## ultimate spends its charge when its channel starts. Enemy abilities start
## their cooldown when they begin, so an interrupted cast is lost.

# --- Party spells -------------------------------------------------------------


static func spell_cost(u: Dictionary, spell: Dictionary) -> float:
	var mods: Dictionary = u.get("mods", {}).get(spell["id"], {})
	return BalanceCombat.mana_cost_eff(
		float(spell.get("mana_cost", 0.0)), float(mods.get("cost_reduction", 0.0))
	)


static func is_instant(spell: Dictionary) -> bool:
	return float(spell.get("cast_s", 0.0)) <= 0.0 and float(spell.get("channel_s", 0.0)) <= 0.0


## Whether `u` can start `spell_id` now. Returns {reason, target}; reason is
## "" when the spell can start, else one of: dead, locked, cc, no_charge,
## no_mana, cooldown, casting, gcd, moving, no_target, out_of_range.
static func check_cast(
	sim: CombatSim, u: Dictionary, spell_id: String, wanted_target: String = ""
) -> Dictionary:
	var spell: Dictionary = sim.def(spell_id)
	var is_ult: bool = spell_id != "" and spell_id == u.get("ultimate", "")
	var reason := ""
	var target := ""
	if not u["alive"]:
		reason = "dead"
	elif spell.is_empty() or not (u.get("spells", []).has(spell_id) or is_ult):
		reason = "locked"
	elif CombatRules.is_cc(sim, u):
		reason = "cc"
	elif is_ult and float(u["ult_charge"]) < float(spell.get("ult_charge_cost", 0)):
		reason = "no_charge"
	elif not is_ult and float(u["mana"]) + 0.000001 < spell_cost(u, spell):
		reason = "no_mana"
	elif int(u["cooldowns"].get(spell_id, 0)) > 0:
		reason = "cooldown"
	elif not u["cast"].is_empty() and not (spell.get("ignores_gcd", false) and is_instant(spell)):
		reason = "casting"
	elif int(u["gcd"]) > 0 and not spell.get("ignores_gcd", false):
		reason = "gcd"
	elif u.get("manual", false):
		reason = "moving"
	else:
		var t := spell_target(sim, u, spell, wanted_target)
		reason = t["reason"]
		target = t["target"]
	return {"reason": reason, "target": target}


## Target of a spell: self, the wanted / focused / current target, or the
## nearest enemy. Reports out_of_range with the target so the AI can close in.
static func spell_target(
	sim: CombatSim, u: Dictionary, spell: Dictionary, wanted: String
) -> Dictionary:
	if spell.get("targeting", "") == "self":
		return {"reason": "", "target": u["uid"]}
	var range_m := float(spell.get("range_m", 0.0))
	var t := ""
	for candidate in [wanted, u["focus"], u["target"]]:
		var c: Dictionary = sim.unit(candidate)
		if not c.is_empty() and c["alive"] and c["side"] != u["side"]:
			t = candidate
			break
	if t == "":
		var nearest := sim.nearest_hostile(u)
		if nearest.is_empty():
			return {"reason": "no_target", "target": ""}
		t = nearest["uid"]
	var in_range := CombatGeometry.dist(u, sim.unit(t)) <= range_m
	if spell.get("targeting", "") != "focus" and not in_range:
		in_range = not sim.hostiles_in_range(u, range_m).is_empty()
	return {"reason": "" if in_range else "out_of_range", "target": t}


static func start_spell(sim: CombatSim, u: Dictionary, spell_id: String, target: String) -> void:
	var spell: Dictionary = sim.def(spell_id)
	var is_ult: bool = spell_id == u.get("ultimate", "")
	var haste := CombatRules.haste_of(u)
	var cast_s := BalanceCombat.hasted(float(spell.get("cast_s", 0.0)), haste)
	var channel_s := BalanceCombat.hasted(float(spell.get("channel_s", 0.0)), haste)
	var veiled := int(u["idle_ticks"]) >= BalanceCombat.ticks(BalanceCombat.VEILED_MANA_DELAY_S)
	if not spell.get("ignores_gcd", false):
		u["gcd"] = BalanceCombat.ticks(BalanceCombat.GLOBAL_COOLDOWN_S)
	if is_ult:
		u["ult_charge"] = float(u["ult_charge"]) - float(spell["ult_charge_cost"])
	var t: Dictionary = sim.unit(target)
	if not t.is_empty() and target != u["uid"]:
		CombatGeometry.face(u, CombatGeometry.pos(t))
	(
		sim
		. emit(
			"spell_cast",
			{
				"unit": u["uid"],
				"spell": spell_id,
				"target": target,
				"kind": spell.get("kind", ""),
				"cast_s": snappedf(cast_s, 0.01),
				"channel_s": snappedf(channel_s, 0.01),
			}
		)
	)
	if is_instant(spell):
		complete_spell(sim, u, spell, target, veiled)
		return
	var phase := "channel" if channel_s > 0.0 else "cast"
	u["cast"] = {
		"spell": spell_id,
		"phase": phase,
		"total": maxi(1, BalanceCombat.ticks(channel_s if phase == "channel" else cast_s)),
		"elapsed": 0,
		"target": target,
		"interruptible": spell.get("interruptible", false),
		"veiled": veiled,
		"hits_done": 0,
		"hits": _damage_hits(spell),
		"telegraph": "",
	}
	_emit_cast_started(sim, u)
	if is_ult:
		_after_active(u, spell, veiled)


static func _damage_hits(spell: Dictionary) -> int:
	for e in spell.get("effects", []):
		if e["type"] == "damage":
			return int(e.get("hits", 1))
	return 0


static func _emit_cast_started(sim: CombatSim, u: Dictionary) -> void:
	var c: Dictionary = u["cast"]
	(
		sim
		. emit(
			"cast_started",
			{
				"unit": u["uid"],
				"spell": c["spell"],
				"phase": c["phase"],
				"duration_s": snappedf(c["total"] * BalanceCombat.TICK_SECONDS, 0.01),
				"interruptible": c["interruptible"],
				"target": c["target"],
			}
		)
	)


## Resets the veiled-mana timer and grants the per-active ultimate charge.
static func _after_active(u: Dictionary, spell: Dictionary, _veiled: bool) -> void:
	u["idle_ticks"] = 0
	if spell.get("kind", "") == "active":
		CombatRules.add_ult_charge(u, BalanceCombat.ULT_CHARGE_PER_ACTIVE)


## Resolves a party spell: pays, starts the cooldown, applies its effects.
static func complete_spell(
	sim: CombatSim, u: Dictionary, spell: Dictionary, target: String, veiled: bool
) -> void:
	var is_ult: bool = spell["id"] == u.get("ultimate", "")
	if not is_ult:
		var cost := spell_cost(u, spell)
		if float(u["mana"]) + 0.000001 < cost:
			sim.emit(
				"cast_interrupted",
				{"unit": u["uid"], "spell": spell["id"], "by": u["uid"], "reason": "no_mana"}
			)
			return
		u["mana"] = maxf(0.0, float(u["mana"]) - cost)
		var mods: Dictionary = u.get("mods", {}).get(spell["id"], {})
		u["cooldowns"][spell["id"]] = BalanceCombat.ticks(
			BalanceCombat.cooldown_eff(
				float(spell.get("cooldown_s", 0.0)),
				CombatRules.haste_of(u),
				float(mods.get("cooldown_reduction", 0.0))
			)
		)
		_after_active(u, spell, veiled)
	var bonus := BalanceCombat.VEILED_MANA_BONUS if veiled else 0.0
	for effect in spell["effects"]:
		match effect["type"]:
			"damage":
				if not is_ult:
					_party_damage(sim, u, spell, effect, target, bonus)
			"shield":
				var amount := BalanceCombat.shield_amount(
					float(u["stats"]["max_hp"]),
					CombatRules.power_of(sim, u),
					int(u.get("ranks", {}).get(spell["id"], 1)),
					float(u["stats"]["shield_bonus"])
				)
				CombatRules.apply_shield(sim, u, amount, BalanceCombat.SHIELD_DURATION_S, u["uid"])
			"cleanse":
				CombatRules.cleanse(sim, u, int(effect.get("count", 1)))
			"heal":
				CombatRules.heal(
					sim, u, float(effect.get("coeff", 0.0)) * u["max_hp"], u["uid"], spell["id"]
				)


static func _party_damage(
	sim: CombatSim,
	u: Dictionary,
	spell: Dictionary,
	effect: Dictionary,
	target: String,
	bonus: float
) -> void:
	var hit := CombatRules.make_hit(
		sim, u, spell, effect, {"bonus": bonus, "interrupt": spell.get("interrupts", false)}
	)
	var hits := int(effect.get("hits", 1))
	var targets: Array = []
	if spell.get("targeting", "") == "distributed":
		targets = distributed_targets(sim, u, target, float(spell.get("range_m", 0.0)))
	elif not sim.unit(target).is_empty():
		targets = [sim.unit(target)]
	if targets.is_empty():
		return
	for i in hits:
		var t: Dictionary = targets[i % targets.size()]
		deliver(sim, u, spell, hit, t)


## Up to 5 enemies within range: the focused one first, then by distance.
static func distributed_targets(
	sim: CombatSim, u: Dictionary, first: String, range_m: float
) -> Array:
	var out := []
	var f: Dictionary = sim.unit(first)
	if not f.is_empty() and f["alive"] and CombatGeometry.dist(u, f) <= range_m:
		out.append(f)
	for e in sim.hostiles_in_range(u, range_m):
		if out.size() >= 5:
			break
		if not out.has(e):
			out.append(e)
	return out


## Instant hit, or a projectile when the spell is tagged "projectile".
static func deliver(
	sim: CombatSim, source: Dictionary, spell: Dictionary, hit: Dictionary, target: Dictionary
) -> void:
	if spell.get("tags", []).has("projectile"):
		var d := CombatGeometry.dist(source, target)
		var travel := maxi(1, BalanceCombat.ticks(d / BalanceCombat.PROJECTILE_SPEED_MPS))
		(
			sim
			. projectiles
			. append(
				{
					"id": sim.next_id("pr"),
					"source": source["uid"],
					"target": target["uid"],
					"spell": spell["id"],
					"hit": hit,
					"total": travel,
					"remaining": travel,
					"x": source["x"],
					"z": source["z"],
				}
			)
		)
	else:
		CombatRules.apply_hit(sim, hit, target)


# --- Auto-attacks -------------------------------------------------------------


static func attack_interval_s(sim: CombatSim, u: Dictionary) -> float:
	var atk: Dictionary = sim.def(u["attack"])
	return (
		BalanceCombat.hasted(float(atk["interval_s"]), CombatRules.haste_of(u))
		/ CombatRules.attack_speed_of(sim, u)
	)


static func perform_attack(sim: CombatSim, u: Dictionary, target: Dictionary) -> void:
	var atk: Dictionary = sim.def(u["attack"])
	u["attack_timer"] = maxi(1, BalanceCombat.ticks(attack_interval_s(sim, u)))
	CombatGeometry.face(u, CombatGeometry.pos(target))
	var projectile: bool = atk.get("tags", []).has("projectile")
	(
		sim
		. emit(
			"attack_started",
			{
				"unit": u["uid"],
				"spell": atk["id"],
				"target": target["uid"],
				"travel_s":
				(
					snappedf(
						CombatGeometry.dist(u, target) / BalanceCombat.PROJECTILE_SPEED_MPS, 0.01
					)
					if projectile
					else 0.0
				),
			}
		)
	)
	for effect in atk["effects"]:
		if effect["type"] == "damage":
			var hit := CombatRules.make_hit(sim, u, atk, effect)
			for i in int(effect.get("hits", 1)):
				deliver(sim, u, atk, hit, target)


# --- Enemy abilities ----------------------------------------------------------


## Opening cooldown of an ability when it becomes available (fight start or
## phase entry). Triggered and barrier abilities have none.
static func open_cooldown(sim: CombatSim, u: Dictionary, ability_id: String) -> void:
	var ab: Dictionary = sim.def(ability_id)
	if ab.get("tags", []).has("barrier") or not ab.get("trigger", {}).is_empty():
		u["cooldowns"][ability_id] = 0
		return
	u["cooldowns"][ability_id] = BalanceCombat.ticks(
		float(ab.get("cooldown_s", 0.0)) * BalanceEnemies.ENEMY_OPENING_CD_FRACTION
	)


## Whether an enemy may begin `ability_id` against `target` now.
static func ability_ready(
	sim: CombatSim, u: Dictionary, ability_id: String, target: Dictionary
) -> bool:
	var ab: Dictionary = sim.def(ability_id)
	if ab.is_empty() or ab.get("tags", []).has("barrier"):
		return false
	if int(u["cooldowns"].get(ability_id, 0)) > 0:
		return false
	var trigger: Dictionary = ab.get("trigger", {})
	if trigger.has("hp_below"):
		var thresholds: Array = (
			trigger["hp_below"] if trigger["hp_below"] is Array else [trigger["hp_below"]]
		)
		var crossed := 0
		for t in thresholds:
			if float(u["hp"]) <= float(t) * float(u["max_hp"]):
				crossed += 1
		if int(u["triggers"].get(ability_id, 0)) >= crossed:
			return false
	if trigger.has("on_time_s") and sim.time_s() < float(trigger["on_time_s"]):
		return false
	if _summon_room(sim, u, ab) == 0:
		return false
	if ab.get("targeting", "") != "self" and ab.has("range_m"):
		return target["alive"] and CombatGeometry.dist(u, target) <= float(ab["range_m"])
	return true


## How many more summons `ab` may bring (-1 when it summons nothing).
static func _summon_room(sim: CombatSim, u: Dictionary, ab: Dictionary) -> int:
	for e in ab.get("effects", []):
		if e["type"] == "summon":
			var alive := 0
			for other in sim.units:
				if other["alive"] and other["summoner"] == u["uid"]:
					alive += 1
			return maxi(0, BalanceEnemies.SUMMON_ALIVE_CAP - alive)
	return -1


static func begin_ability(
	sim: CombatSim, u: Dictionary, ability_id: String, target: Dictionary
) -> void:
	var ab: Dictionary = sim.def(ability_id)
	var haste := CombatRules.haste_of(u)
	u["cooldowns"][ability_id] = BalanceCombat.ticks(
		BalanceCombat.cooldown_eff(float(ab.get("cooldown_s", 0.0)), haste)
	)
	if ab.get("trigger", {}).has("hp_below"):
		u["triggers"][ability_id] = int(u["triggers"].get(ability_id, 0)) + 1
	var target_uid: String = target["uid"] if ab.get("targeting", "") != "self" else u["uid"]
	if target_uid != u["uid"]:
		CombatGeometry.face(u, CombatGeometry.pos(target))
	var cast_s := BalanceCombat.hasted(float(ab.get("cast_s", 0.0)), haste)
	var channel_s := BalanceCombat.hasted(float(ab.get("channel_s", 0.0)), haste)
	(
		sim
		. emit(
			"spell_cast",
			{
				"unit": u["uid"],
				"spell": ability_id,
				"target": target_uid,
				"kind": ab.get("kind", ""),
				"cast_s": snappedf(cast_s, 0.01),
				"channel_s": snappedf(channel_s, 0.01),
			}
		)
	)
	u["ai_state"] = "ability"
	if ab.has("telegraph"):
		u["cast"] = {
			"spell": ability_id,
			"phase": "telegraph",
			"total": 0,
			"elapsed": 0,
			"target": target_uid,
			"interruptible": ab.get("interruptible", false),
			"hits_done": 0,
			"hits": maxi(1, _damage_hits(ab)),
			"telegraph": "",
		}
		_start_telegraph(sim, u, ab)
	elif cast_s > 0.0 or channel_s > 0.0:
		var phase := "channel" if channel_s > 0.0 else "cast"
		u["cast"] = {
			"spell": ability_id,
			"phase": phase,
			"total": maxi(1, BalanceCombat.ticks(channel_s if phase == "channel" else cast_s)),
			"elapsed": 0,
			"target": target_uid,
			"interruptible": ab.get("interruptible", false),
			"hits_done": 0,
			"hits": 0,
			"telegraph": "",
		}
		_emit_cast_started(sim, u)
	else:
		resolve_ability(sim, u, ab, target_uid)


## Telegraph of the next hit of the current ability (re-aimed at each hit).
static func _start_telegraph(sim: CombatSim, u: Dictionary, ab: Dictionary) -> void:
	var c: Dictionary = u["cast"]
	var target: Dictionary = sim.unit(c["target"])
	if target.is_empty() or not target["alive"]:
		target = sim.nearest_hostile(u)
		if target.is_empty():
			u["cast"] = {}
			return
		c["target"] = target["uid"]
	var tg: Dictionary = ab["telegraph"]
	var duration := maxf(
		BalanceCombat.TELEGRAPH_MIN_S,
		BalanceCombat.hasted(float(tg["duration_s"]), CombatRules.haste_of(u))
	)
	var unavoidable: bool = ab.get("tags", []).has("unavoidable")
	var origin := CombatGeometry.pos(u)
	var aim := CombatGeometry.pos(target)
	var dir := aim - origin
	dir = dir.normalized() if dir.length_squared() > 0.000001 else Vector2(u["fx"], u["fz"])
	var at := origin if tg["shape"] in ["line", "cone"] else aim
	var shape := {
		"id": sim.next_id("tg"),
		"source": u["uid"],
		"spell": ab["id"],
		"shape": tg["shape"],
		"size_m": float(tg["size_m"]),
		"width_m": BalanceCombat.TELEGRAPH_LINE_WIDTH_M,
		"x": at.x,
		"z": at.y,
		"dx": dir.x,
		"dz": dir.y,
		"total": BalanceCombat.ticks(duration),
		"remaining": BalanceCombat.ticks(duration),
		"attached_to": target["uid"] if unavoidable else "",
		"aim_dist": origin.distance_to(aim),
	}
	sim.telegraphs.append(shape)
	c["telegraph"] = shape["id"]
	c["total"] = shape["total"]
	c["elapsed"] = 0
	CombatGeometry.face(u, aim)
	(
		sim
		. emit(
			"telegraph_started",
			{
				"id": shape["id"],
				"unit": u["uid"],
				"spell": ab["id"],
				"shape": shape["shape"],
				"size_m": shape["size_m"],
				"width_m": shape["width_m"],
				"position": [snappedf(at.x, 0.01), snappedf(at.y, 0.01)],
				"direction": [snappedf(dir.x, 0.001), snappedf(dir.y, 0.001)],
				"duration_s": snappedf(duration, 0.01),
				"attached_to": shape["attached_to"],
				"interruptible": c["interruptible"],
				"hit": int(c["hits_done"]) + 1,
				"hits": c["hits"],
			}
		)
	)
	_emit_cast_started(sim, u)


## One tick of the unit's current cast, channel or telegraph.
static func progress_cast(sim: CombatSim, u: Dictionary) -> void:
	var c: Dictionary = u["cast"]
	if c.is_empty():
		return
	c["elapsed"] += 1
	var tg := sim.telegraph(c["telegraph"])
	if not tg.is_empty():
		tg["remaining"] = int(c["total"]) - int(c["elapsed"])
		var holder: Dictionary = sim.unit(tg["attached_to"])
		if not holder.is_empty():
			tg["x"] = holder["x"]
			tg["z"] = holder["z"]
	if c["phase"] == "channel" and u["side"] == "party" and int(c["hits"]) > 0:
		var due := floori(float(c["elapsed"]) * float(c["hits"]) / float(c["total"]))
		while int(c["hits_done"]) < mini(due, int(c["hits"])) and u["alive"]:
			c["hits_done"] += 1
			_ult_ray(sim, u, c)
	if int(c["elapsed"]) >= int(c["total"]):
		_complete_cast(sim, u)


static func _ult_ray(sim: CombatSim, u: Dictionary, c: Dictionary) -> void:
	var spell: Dictionary = sim.def(c["spell"])
	var range_m := float(spell.get("range_m", 0.0))
	var pool := sim.hostiles_in_range(u, range_m)
	if pool.is_empty():
		return
	var focus: Dictionary = sim.unit(u["focus"] if u["focus"] != "" else c["target"])
	var target: Dictionary = {}
	var roll := sim.rng.next_float()
	if not focus.is_empty() and pool.has(focus) and roll < BalanceCombat.ULT_FOCUS_SHARE:
		target = focus
	else:
		target = pool[sim.rng.range_int(0, pool.size() - 1)]
	var effect: Dictionary = {}
	for e in spell["effects"]:
		if e["type"] == "damage":
			effect = e
	var bonus := BalanceCombat.VEILED_MANA_BONUS if c.get("veiled", false) else 0.0
	CombatRules.apply_hit(
		sim, CombatRules.make_hit(sim, u, spell, effect, {"bonus": bonus}), target
	)


static func _complete_cast(sim: CombatSim, u: Dictionary) -> void:
	var c: Dictionary = u["cast"]
	var spell: Dictionary = sim.def(c["spell"])
	if c["phase"] == "telegraph":
		_telegraph_impact(sim, u, spell, c)
		return
	u["cast"] = {}
	sim.emit("cast_completed", {"unit": u["uid"], "spell": c["spell"]})
	if u["side"] == "party":
		if spell["id"] != u.get("ultimate", ""):
			complete_spell(sim, u, spell, c["target"], c.get("veiled", false))
	else:
		resolve_ability(sim, u, spell, c["target"])


static func _telegraph_impact(sim: CombatSim, u: Dictionary, ab: Dictionary, c: Dictionary) -> void:
	var tg := sim.telegraph(c["telegraph"])
	sim.remove_telegraph(c["telegraph"], "impact")
	var victims: Array = []
	if tg["attached_to"] != "":
		var holder: Dictionary = sim.unit(tg["attached_to"])
		if not holder.is_empty() and holder["alive"]:
			victims.append(holder)
	else:
		for h in sim.hostiles(u):
			if CombatGeometry.shape_contains(tg, CombatGeometry.pos(h)):
				victims.append(h)
	if tg["shape"] == "line":
		var dash := maxf(
			0.0, minf(tg["size_m"], tg["aim_dist"] - BalanceCombat.UNIT_RADIUS_M * 2.0)
		)
		var p := Vector2(tg["x"], tg["z"]) + Vector2(tg["dx"], tg["dz"]) * dash
		CombatGeometry.set_pos(u, p)
	for effect in ab["effects"]:
		if effect["type"] == "damage":
			var hit := CombatRules.make_hit(sim, u, ab, effect)
			for v in victims:
				CombatRules.apply_hit(sim, hit, v)
		elif effect["type"] == "apply_status":
			for v in victims:
				CombatRules.apply_status(
					sim, v, effect["status"], CombatRules.make_hit(sim, u, ab, {})
				)
	c["hits_done"] += 1
	if u["alive"] and int(c["hits_done"]) < int(c["hits"]) and not u["cast"].is_empty():
		_start_telegraph(sim, u, ab)
	elif not u["cast"].is_empty():
		u["cast"] = {}
		sim.emit("cast_completed", {"unit": u["uid"], "spell": ab["id"]})


## Effects of an enemy ability that has no telegraph (after its cast or
## channel, or at once): ground zones, summons, statuses, plain hits.
static func resolve_ability(
	sim: CombatSim, u: Dictionary, ab: Dictionary, target_uid: String
) -> void:
	var target: Dictionary = sim.unit(target_uid)
	var summons: Array = []
	for effect in ab["effects"]:
		match effect["type"]:
			"damage":
				if effect.has("duration_s") and effect.has("radius_m"):
					if not target.is_empty():
						_spawn_zone(sim, u, ab, effect, CombatGeometry.pos(target))
				elif not target.is_empty() and target["alive"]:
					deliver(sim, u, ab, CombatRules.make_hit(sim, u, ab, effect), target)
			"apply_status":
				_ability_status(sim, u, ab, effect, target)
			"summon":
				summons = _summon(sim, u, ab, effect)
			"damage_reduction":
				for s in summons:
					s["link_reduction"] = float(effect.get("coeff", 0.0))
			"shield":
				CombatRules.restore_barrier(sim, u)
			"heal":
				CombatRules.heal(
					sim, u, float(effect.get("coeff", 0.0)) * u["max_hp"], u["uid"], ab["id"]
				)
	if u["ai_state"] == "ability":
		u["ai_state"] = "attack"


static func _ability_status(
	sim: CombatSim, u: Dictionary, ab: Dictionary, effect: Dictionary, target: Dictionary
) -> void:
	var def: Dictionary = sim.def(effect["status"])
	var source := CombatRules.make_hit(sim, u, ab, {})
	if def.get("kind", "") == "buff":
		var radius := float(effect.get("radius_m", 0.0))
		for ally in sim.units.duplicate():
			if ally["alive"] and ally["side"] == u["side"]:
				if ally == u or CombatGeometry.dist(u, ally) <= radius:
					CombatRules.apply_status(sim, ally, effect["status"], source)
	elif not target.is_empty() and target["alive"]:
		if sim.rng.next_float() < float(effect.get("chance", 1.0)):
			CombatRules.apply_status(sim, target, effect["status"], source)


static func _summon(sim: CombatSim, u: Dictionary, ab: Dictionary, effect: Dictionary) -> Array:
	var room := _summon_room(sim, u, ab)
	var count := mini(int(effect.get("count", 1)), room)
	var out := []
	for i in count:
		var angle := TAU * float(i) / float(maxi(count, 1)) + PI * 0.5
		var at := CombatGeometry.pos(u) + Vector2(cos(angle), sin(angle)) * 2.0
		var level := int(u["level"]) + int(effect.get("level_offset", 0))
		var s := sim.spawn_enemy(effect["summon"], level, at, u["uid"])
		if not s.is_empty():
			out.append(s)
	return out


static func _spawn_zone(
	sim: CombatSim, u: Dictionary, ab: Dictionary, effect: Dictionary, at: Vector2
) -> void:
	var hits := maxi(1, int(effect.get("hits", 1)))
	var duration := float(effect["duration_s"])
	var zone := {
		"id": sim.next_id("zn"),
		"source": u["uid"],
		"side": u["side"],
		"spell": ab["id"],
		"element": ab.get("element", "arcane"),
		"x": at.x,
		"z": at.y,
		"radius_m": float(effect["radius_m"]),
		"total": BalanceCombat.ticks(duration),
		"remaining": BalanceCombat.ticks(duration),
		"every": maxi(1, BalanceCombat.ticks(duration / float(hits))),
		"timer": 0,
		"hit": CombatRules.make_hit(sim, u, ab, effect, {"can_crit": false}),
	}
	sim.zones.append(zone)
	(
		sim
		. emit(
			"zone_spawned",
			{
				"id": zone["id"],
				"unit": u["uid"],
				"spell": ab["id"],
				"element": zone["element"],
				"shape": "circle",
				"size_m": zone["radius_m"],
				"position": [snappedf(at.x, 0.01), snappedf(at.y, 0.01)],
				"duration_s": duration,
			}
		)
	)


static func cancel_cast(sim: CombatSim, u: Dictionary, reason: String, by: String) -> void:
	var c: Dictionary = u["cast"]
	if c.is_empty():
		return
	if c.get("telegraph", "") != "":
		sim.remove_telegraph(c["telegraph"], "cancelled")
	u["cast"] = {}
	if u["ai_state"] == "ability":
		u["ai_state"] = "attack"
	sim.emit(
		"cast_interrupted", {"unit": u["uid"], "spell": c["spell"], "by": by, "reason": reason}
	)


# --- Projectiles and zones ----------------------------------------------------


static func tick_projectiles(sim: CombatSim) -> void:
	var landed := []
	for p in sim.projectiles:
		p["remaining"] -= 1
		if p["remaining"] <= 0:
			landed.append(p)
	for p in landed:
		sim.projectiles.erase(p)
		var target: Dictionary = sim.unit(p["target"])
		if not target.is_empty() and target["alive"]:
			CombatRules.apply_hit(sim, p["hit"], target)


static func tick_zones(sim: CombatSim) -> void:
	for z in sim.zones.duplicate():
		z["timer"] += 1
		if z["timer"] >= z["every"]:
			z["timer"] = 0
			var center := Vector2(z["x"], z["z"])
			for u in sim.units.duplicate():
				if u["alive"] and u["side"] != z["side"]:
					var reach: float = z["radius_m"] + BalanceCombat.UNIT_RADIUS_M
					if CombatGeometry.pos(u).distance_to(center) <= reach:
						CombatRules.apply_hit(sim, z["hit"], u)
		z["remaining"] -= 1
		if z["remaining"] <= 0:
			sim.zones.erase(z)
			sim.emit("zone_expired", {"id": z["id"]})
