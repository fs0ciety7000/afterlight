class_name CombatFactory
extends RefCounted
## Builds the combatants of an encounter from content and party setup.
## A unit is a plain Dictionary (see docs/ARCHITECTURE.md, "Combat").


## Party member from a setup entry:
## {character, level, slot (1-4, default 3), flat, percent, stats (final
##  stats override), spells (unlocked ids override), spell_ranks, spell_mods,
##  ult_charge, hp_pct, mana_pct, position [x, z]}.
static func party_unit(entry: Dictionary, content: Dictionary) -> Dictionary:
	var def: Dictionary = content.get(str(entry.get("character", "")), {})
	if def.is_empty() or def.get("_type", "") != "character" or not def.get("playable", false):
		return {}
	var level := int(entry.get("level", 1))
	var slot := clampi(int(entry.get("slot", 3)), 1, 4)
	var stats: Dictionary
	if entry.has("stats"):
		stats = BalanceStats.derive(entry["stats"], {}, 1)
	else:
		stats = BalanceStats.derive(
			def["base_stats"], def["growth"], level, entry.get("flat", {}), entry.get("percent", {})
		)
	var front := slot <= 2
	if front:
		stats["defense"] *= 1.0 + BalanceCombat.FRONT_ROW_DEFENSE_BONUS
	var u := _base_unit("p%d" % slot, def["id"], "party", level, stats)
	u["slot"] = slot
	u["row"] = "front" if front else "back"
	u["hp"] = maxi(1, roundi(u["max_hp"] * clampf(float(entry.get("hp_pct", 1.0)), 0.0, 1.0)))
	u["mana"] = u["max_mana"] * clampf(float(entry.get("mana_pct", 1.0)), 0.0, 1.0)
	u["attack"] = def["auto_attack"]
	var spells: Array = entry.get("spells", _unlocked(def, level))
	u["spells"] = []
	for id in def["spells"]:
		if spells.has(id):
			u["spells"].append(id)
	u["ultimate"] = def["ultimate"] if spells.has(def["ultimate"]) else ""
	u["ranks"] = entry.get("spell_ranks", {}).duplicate()
	u["mods"] = entry.get("spell_mods", {}).duplicate(true)
	u["ult_charge"] = clampf(float(entry.get("ult_charge", 0.0)), 0.0, BalanceCombat.ULT_CHARGE_MAX)
	u["idle_ticks"] = BalanceCombat.ticks(BalanceCombat.VEILED_MANA_DELAY_S)
	u["consumables"] = {}
	u["consumable_cd"] = 0
	u["queued"] = {}
	u["manual"] = false
	u["hold"] = 0
	var row_z := BalanceCombat.FORMATION_FRONT_DISTANCE_M
	if not front:
		row_z += BalanceCombat.BACK_ROW_EXTRA_DISTANCE_M
	var col := -0.5 if slot % 2 == 1 else 0.5
	var start: Array = entry.get("position", [col * BalanceCombat.FORMATION_SLOT_SPACING_M, row_z])
	u["x"] = float(start[0])
	u["z"] = float(start[1])
	u["fx"] = 0.0
	u["fz"] = -1.0
	return u


## Spells unlocked at `level` (character `unlocks`; a spell without an
## unlock entry is always available).
static func _unlocked(def: Dictionary, level: int) -> Array:
	var gated := {}
	for u in def.get("unlocks", []):
		gated[u["ref"]] = int(u["level"])
	var out := []
	for id in def["spells"] + [def["ultimate"]]:
		if int(gated.get(id, 1)) <= level:
			out.append(id)
	return out


static func enemy_unit(
	uid: String, enemy_id: String, level: int, content: Dictionary, at: Vector2
) -> Dictionary:
	var def: Dictionary = content.get(enemy_id, {})
	if def.is_empty() or def.get("_type", "") != "enemy":
		return {}
	var s: Dictionary = def["stats_l1"]
	level = maxi(1, level)
	var stats := BalanceStats.derive({}, {}, 1)
	stats["max_hp"] = BalanceEnemies.hp(float(s["hp"]), level)
	stats["power"] = BalanceEnemies.power(float(s["power"]), level)
	stats["defense"] = BalanceEnemies.defense(float(s["def_ratio"]), level)
	stats["move_speed"] = float(s["move_speed"])
	stats["crit_chance"] = 0.0
	var u := _base_unit(uid, enemy_id, "enemy", level, stats)
	u["archetype"] = def["archetype"]
	u["is_boss"] = def["archetype"] == "boss"
	u["affinities"] = def["affinities"].duplicate()
	u["attack"] = def["attack"]
	u["base_abilities"] = def["abilities"].duplicate()
	u["phases"] = def["phases"]
	u["phase"] = 0
	u["enrage_s"] = float(def.get("enrage_s", 0.0))
	u["ai_profile"] = def["ai_profile"]
	u["xp_mult"] = float(def["xp_mult"])
	u["gold_mult"] = float(def["gold_mult"])
	u["cc_resist"] = float(def.get("cc_resist", 0.0))
	u["barrier_ratio"] = float(s["barrier_ratio"])
	u["x"] = at.x
	u["z"] = at.y
	u["fx"] = 0.0
	u["fz"] = 1.0
	return u


static func _base_unit(
	uid: String, def_id: String, side: String, level: int, stats: Dictionary
) -> Dictionary:
	return {
		"uid": uid,
		"def_id": def_id,
		"side": side,
		"level": level,
		"archetype": "",
		"is_boss": false,
		"row": "",
		"slot": 0,
		"stats": stats,
		"max_hp": maxi(1, roundi(stats["max_hp"])),
		"hp": maxi(1, roundi(stats["max_hp"])),
		"max_mana": float(stats["max_mana"]),
		"mana": float(stats["max_mana"]),
		"shield": 0.0,
		"barrier": 0.0,
		"barrier_max": 0.0,
		"barrier_timer": 0,
		"alive": true,
		"statuses": {},
		"immunities": {},
		"cooldowns": {},
		"gcd": 0,
		"attack_timer": 0,
		"cast": {},
		"target": "",
		"focus": "",
		"ai_state": "aggro",
		"move": {},
		"moving": false,
		"kiting": false,
		"haste_bonus": 0.0,
		"triggers": {},
		"summoner": "",
		"link_reduction": 0.0,
		"affinities": {},
		"base_abilities": [],
		"phases": [],
		"phase": 0,
		"retarget": true,
	}


## Spawn layout of the pack around the encounter centre: rows of up to four
## enemies, ENEMY_SPAWN_SPACING_M apart, the party standing toward +z.
static func pack_position(index: int, count: int) -> Vector2:
	var per_row := mini(count, 4)
	var row := floori(index / 4.0)
	var in_row := index % 4
	var row_count := mini(per_row, count - row * 4)
	var spacing := BalanceCombat.ENEMY_SPAWN_SPACING_M
	return Vector2((float(in_row) - float(row_count - 1) * 0.5) * spacing, -float(row) * spacing)
