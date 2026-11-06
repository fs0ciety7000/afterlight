class_name OfflineModel
extends RefCounted
## Analytical fight model of the offline progression (docs/GAME_BALANCE.md
## §20.2-§20.3): hunting rotation under the default tactics, DPS, effective HP
## of the pack, clear time, incoming damage and survival. Never runs a combat
## tick.
##
## `entry` is a CombatSim party entry (PartyBuild.entry, or a bench entry with
## `stats`), so the model sees exactly the stats, spells, ranks and runes the
## simulation would use. An absent party always fights with the default
## tactics, even when the player saved others (GAME_BALANCE §20.1, GDD
## decision 25; CombatTactics.default_mode): damage and interrupt spells on
## cooldown, area spells while enough enemies stand, shields on their
## automatic mode, the ultimate on manual (never cast).


## Spell parts of a party member against a pack of `pack_size` enemies (§20.2):
## {interval, income, pool, sustained: [part], burst: [part], spend, open_cost,
## cast_rate}. A part is {spell, coeff (coeff × hits × rank × echo), rate
## (casts per second at full mana, 0 for a burst), element, bonus, crit}.
static func parts(unit: Dictionary, content: Dictionary, pack_size: int) -> Dictionary:
	var stats: Dictionary = unit["stats"]
	var haste := float(stats["haste"])
	var auto: Dictionary = content.get(unit["attack"], {})
	var interval := BalanceCombat.hasted(float(auto.get("interval_s", 1.0)), haste)
	var out := {
		"interval": interval,
		"income": BalanceCombat.mana_income(float(stats["mana_regen"]), interval),
		"pool": float(unit["max_mana"]) * BalanceOffline.fight_start_mana(),
		"auto": _part(unit, auto, _damage_coeff(auto), 1.0 / interval),
		"sustained": [],
		"burst": [],
		"spend": 0.0,
		"open_cost": 0.0,
		"cast_rate": 0.0,
	}
	for id in unit["spells"]:
		var spell: Dictionary = content.get(id, {})
		var mods: Dictionary = unit["mods"].get(id, {})
		var role := CombatTactics.role_of(spell)
		var cost := BalanceCombat.mana_cost_eff(
			float(spell.get("mana_cost", 0.0)), float(mods.get("cost_reduction", 0.0))
		)
		var cd := BalanceCombat.cooldown_eff(
			float(spell.get("cooldown_s", 0.0)), haste, float(mods.get("cooldown_reduction", 0.0))
		)
		var rate := 1.0 / maxf(cd, BalanceCombat.TICK_SECONDS)
		var coeff := (
			_damage_coeff(spell)
			* BalanceCombat.rank_mult(int(unit["ranks"].get(id, 1)))
			* (1.0 + float(mods.get("echo_chance", 0.0)) * BalanceOffline.ECHO_WEIGHT)
		)
		if role == "area":
			# auto_min_enemies: one opening cast while the whole pack stands.
			if pack_size >= BalanceCombat.TACTIC_MIN_ENEMIES_DEFAULT and coeff > 0.0:
				out["burst"].append(_part(unit, spell, coeff, 0.0))
				out["open_cost"] += cost
			continue
		out["spend"] += cost * rate
		out["cast_rate"] += rate
		if coeff > 0.0:
			out["sustained"].append(_part(unit, spell, coeff, rate))
	return out


## Mana ratio r over a fight of `fight_s` seconds started with the pool:
## r = min(1, (pool − open_cost + income × t) / (spend × t)).
static func mana_ratio(p: Dictionary, fight_s: float) -> float:
	var t := maxf(fight_s, BalanceCombat.TICK_SECONDS)
	if float(p["spend"]) <= 0.0:
		return 1.0
	var budget := float(p["pool"]) - float(p["open_cost"]) + float(p["income"]) * t
	return clampf(budget / (float(p["spend"]) * t), 0.0, 1.0)


## Veiled mana (passive, §5): when the actives cast on their own leave at
## least VEILED_MANA_DELAY_S between two casts, each damaging one gets
## VEILED_MANA_BONUS. mean gap = 1 / (Σ rate × r).
static func veiled_mult(p: Dictionary, ratio: float) -> float:
	var rate := float(p["cast_rate"]) * ratio
	if rate > 0.0 and 1.0 / rate >= BalanceCombat.VEILED_MANA_DELAY_S:
		return 1.0 + BalanceCombat.VEILED_MANA_BONUS
	return 1.0


## Rotation at mana ratio `ratio` (§20.2): {rot (sustained coeff per second),
## burst (opening coeff), crit_rot, crit_burst (crit and bonus folded in),
## elements: {element: share of sustained damage over `fight_s` + burst}}.
static func rotation(p: Dictionary, ratio: float, fight_s: float) -> Dictionary:
	var veiled := veiled_mult(p, ratio)
	var terms := [[p["auto"], 1.0 / float(p["interval"])]]
	for part in p["sustained"]:
		terms.append([part, float(part["rate"]) * ratio * veiled])
	var rot := 0.0
	var crit_rot := 0.0
	var by_element := {}
	var t := maxf(fight_s, BalanceCombat.TICK_SECONDS)
	for pair in terms:
		var part: Dictionary = pair[0]
		var value := float(part["coeff"]) * float(pair[1])
		rot += value
		crit_rot += value * float(part["bonus"]) * float(part["crit"])
		_add(by_element, part["element"], value * float(part["bonus"]) * t)
	var burst := 0.0
	var crit_burst := 0.0
	for part in p["burst"]:
		burst += float(part["coeff"])
		crit_burst += float(part["coeff"]) * float(part["bonus"]) * float(part["crit"])
		_add(by_element, part["element"], float(part["coeff"]) * float(part["bonus"]))
	var total := 0.0
	for element in by_element:
		total += by_element[element]
	var shares := {}
	for element in by_element:
		shares[element] = by_element[element] / total if total > 0.0 else 0.0
	return {
		"rot": rot,
		"burst": burst,
		"crit_rot": crit_rot,
		"crit_burst": crit_burst,
		"elements": shares,
		"veiled": veiled > 1.0,
	}


static func _add(map: Dictionary, key: String, value: float) -> void:
	map[key] = float(map.get(key, 0.0)) + value


## One damage part: its element (rune conversion), additive bonus layer
## (1 + damage_bonus + element_bonus_<element> + rune damage_bonus, as in
## CombatRules.make_hit) and crit factor (with the Acuity crit bonus).
static func _part(unit: Dictionary, spell: Dictionary, coeff: float, rate: float) -> Dictionary:
	var stats: Dictionary = unit["stats"]
	var mods: Dictionary = unit["mods"].get(spell.get("id", ""), {})
	var element: String = mods.get("element", spell.get("element", "arcane"))
	return {
		"spell": spell.get("id", ""),
		"coeff": coeff,
		"rate": rate,
		"element": element,
		"bonus":
		(
			1.0
			+ float(stats["damage_bonus"])
			+ float(stats.get("element_bonus_" + element, 0.0))
			+ float(mods.get("damage_bonus", 0.0))
		),
		"crit":
		BalanceOffline.crit_factor(
			float(stats["crit_chance"]) + float(mods.get("crit_bonus", 0.0)),
			float(stats["crit_damage"])
		),
	}


## Σ coeff × hits of the damage effects of a spell or ability.
static func _damage_coeff(spell: Dictionary) -> float:
	var total := 0.0
	for e in spell.get("effects", []):
		if e.get("type", "") == "damage":
			total += float(e.get("coeff", 0.0)) * float(e.get("hits", 1))
	return total


## Enemies of an encounter, summons excluded: [{enemy, level, def}].
static func pack(encounter: Dictionary, content: Dictionary) -> Array:
	var out := []
	for group in encounter.get("enemies", []):
		var def: Dictionary = content.get(group["enemy"], {})
		var level := maxi(1, int(encounter["level"]) + int(group.get("level_offset", 0)))
		for i in int(group.get("count", 1)):
			out.append({"enemy": group["enemy"], "level": level, "def": def})
	return out


## Affinity of an enemy against the rotation: mean of its affinities weighted
## by the share of each element in the damage.
static func affinity(def: Dictionary, elements: Dictionary) -> float:
	if elements.is_empty():
		return 1.0
	var total := 0.0
	for element in elements:
		var a := str(def.get("affinities", {}).get(element, "neutral"))
		total += float(elements[element]) * BalanceCombat.affinity_mult(a)
	return total


## Σ PV_effectifs of the pack for a rotation's element shares.
static func pack_ehp(enemies: Array, level: int, elements: Dictionary) -> float:
	var arcane := float(elements.get("arcane", 0.0))
	var barrier_mult := 1.0 + (BalanceCombat.BARRIER_ARCANE_MULT - 1.0) * arcane
	var ehp := 0.0
	for e in enemies:
		var s: Dictionary = e["def"].get("stats_l1", {})
		var hp := BalanceEnemies.hp(float(s.get("hp", 0.0)), e["level"])
		var mitigation := BalanceCombat.mitigation(
			level, BalanceEnemies.defense(float(s.get("def_ratio", 0.0)), e["level"])
		)
		ehp += BalanceEnemies.effective_hp(
			hp,
			BalanceEnemies.barrier(float(s.get("barrier_ratio", 0.0)), hp),
			mitigation,
			affinity(e["def"], elements),
			barrier_mult
		)
	return ehp


## Full analytical estimate of a party member against an encounter.
## Returns {error ("" or a reason), level, gold_find, dps (sustained), rot,
## burst, burst_damage, mana_ratio, veiled, ehp, clear_time_s, cycle_s,
## incoming_dps, reserve, survival_s, required_s, survives}.
## The fight time and the mana ratio depend on each other: a few fixed-point
## steps from r = 1 settle them (BalanceOffline.FIXED_POINT_STEPS).
static func estimate(entry: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var encounter: Dictionary = content.get(encounter_id, {})
	if encounter.get("_type", "") != "encounter":
		return {"error": "unknown_encounter"}
	var unit := CombatFactory.party_unit(entry, content)
	if unit.is_empty():
		return {"error": "unknown_party"}
	var stats: Dictionary = unit["stats"]
	var level := int(unit["level"])
	var enemies := pack(encounter, content)
	var p := parts(unit, content, enemies.size())
	var scale := float(stats["power"]) * BalanceOffline.OFFLINE_DPS_CALIBRATION
	var ratio := 1.0
	var fight := 0.0
	var rot := rotation(p, ratio, BalanceOffline.CLEAR_TIME_MIN_S)
	var ehp := 0.0
	for i in BalanceOffline.FIXED_POINT_STEPS:
		ehp = pack_ehp(enemies, level, rot["elements"])
		fight = BalanceOffline.fight_time(
			ehp, scale * float(rot["crit_burst"]), scale * float(rot["crit_rot"])
		)
		ratio = mana_ratio(p, fight)
		rot = rotation(p, ratio, fight)
	ehp = pack_ehp(enemies, level, rot["elements"])
	var dps := scale * float(rot["crit_rot"])
	var burst_damage := scale * float(rot["crit_burst"])
	var clear := BalanceOffline.clear_time(ehp, burst_damage, dps)
	var incoming := 0.0
	for e in enemies:
		var s: Dictionary = e["def"].get("stats_l1", {})
		incoming += (
			BalanceEnemies.power(float(s.get("power", 0.0)), e["level"])
			* incoming_coeff(e["def"], content)
			* BalanceCombat.mitigation(e["level"], float(stats["defense"]))
			* BalanceOffline.OFFLINE_INCOMING_ALIVE_FACTOR
		)
	var reserve := float(unit["max_hp"]) + _shield_reserve(unit, content, clear)
	return {
		"error": "",
		"level": level,
		"gold_find": float(stats["gold_find"]),
		"dps": dps,
		"rot": rot["rot"],
		"burst": rot["burst"],
		"burst_damage": burst_damage,
		"mana_ratio": ratio,
		"veiled": rot["veiled"],
		"ehp": ehp,
		"clear_time_s": clear,
		"cycle_s": BalanceOffline.cycle(clear),
		"incoming_dps": incoming,
		"reserve": reserve,
		"survival_s": INF if incoming <= 0.0 else reserve / incoming,
		"required_s": BalanceOffline.OFFLINE_SAFETY_FACTOR * clear,
		"survives": BalanceOffline.survives(reserve, incoming, clear),
	}


## Coefficient per second an enemy deals: its attack (coeff × hits / interval)
## plus its damaging abilities (coeff × hits / cooldown). Ground zones (an
## effect with `duration_s`, which the party steps out of), triggered
## abilities and statuses are left out (§20.3, provisional, jalon 5).
static func incoming_coeff(def: Dictionary, content: Dictionary) -> float:
	var attack: Dictionary = content.get(def.get("attack", ""), {})
	var total := 0.0
	var interval := float(attack.get("interval_s", 0.0))
	if interval > 0.0:
		total += _damage_coeff(attack) / interval
	for id in def.get("abilities", []):
		var ab: Dictionary = content.get(id, {})
		var cd := float(ab.get("cooldown_s", 0.0))
		if cd <= 0.0 or ab.has("trigger"):
			continue
		for e in ab.get("effects", []):
			if e.get("type", "") == "damage" and not e.has("duration_s"):
				total += float(e.get("coeff", 0.0)) * float(e.get("hits", 1)) / cd
	return total


## shield × (clear_time / recharge_barrière_eff + 1) for each shield spell.
static func _shield_reserve(unit: Dictionary, content: Dictionary, clear_s: float) -> float:
	var stats: Dictionary = unit["stats"]
	var total := 0.0
	for id in unit["spells"]:
		var spell: Dictionary = content.get(id, {})
		if CombatTactics.role_of(spell) != "shield":
			continue
		var mods: Dictionary = unit["mods"].get(id, {})
		var cd := BalanceCombat.cooldown_eff(
			float(spell.get("cooldown_s", 0.0)),
			float(stats["haste"]),
			float(mods.get("cooldown_reduction", 0.0))
		)
		var amount := BalanceCombat.shield_amount(
			float(unit["max_hp"]),
			float(stats["power"]),
			int(unit["ranks"].get(id, 1)),
			float(stats["shield_bonus"])
		)
		total += amount * (clear_s / maxf(cd, BalanceCombat.TICK_SECONDS) + 1.0)
	return total
