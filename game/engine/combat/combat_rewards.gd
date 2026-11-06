class_name CombatRewards
extends RefCounted
## Rewards of a won encounter (GAME_BALANCE §12-§14, §17): XP and gold per
## enemy of the encounter (summons give nothing, so stalling a boss for its
## adds pays nothing); materials, items, runes, artifacts and consumables from
## the loot table, plus the encounter's first_clear_rewards (materials and
## items) on a first victory. Draws use the "loot" stream, so the combat sequence never shifts
## them. Items have no uid yet: CombatOutcome assigns it.


static func compute(sim: CombatSim) -> Dictionary:
	var leader: Dictionary = sim.units[0]
	var table: Dictionary = sim.def(sim.encounter["loot_table"])
	var gold_find := float(leader["stats"]["gold_find"])
	var xp := 0.0
	var gold := 0
	var materials := {}
	var items := []
	var runes := []
	var artifacts := []
	var consumables := {}
	var rewarded := []
	for uid in sim.kills:
		var e: Dictionary = sim.unit(uid)
		if e["summoner"] == "":
			rewarded.append(e)
	if rewarded.is_empty():
		return empty()
	for e in rewarded:
		xp += (
			BalanceEnemies.enemy_xp(e["level"], e["xp_mult"])
			* BalanceEnemies.xp_penalty(leader["level"], e["level"])
		)
	var profile := loot_profile(table, sim.first_clear)
	var ilvl := BalanceItems.item_level(int(sim.encounter["level"]), sim.encounter["kind"])
	for entry in table.get("entries", []):
		if not applies(entry, sim.first_clear):
			continue
		var rolls := rewarded.size() if entry["per"] == "enemy" else 1
		for i in rolls:
			if not sim.loot_rng.chance(float(entry["chance"])):
				continue
			if entry["kind"] == "gold":
				var e: Dictionary = rewarded[i] if entry["per"] == "enemy" else rewarded[0]
				var roll := sim.loot_rng.range_float(
					BalanceEnemies.GOLD_ROLL_MIN, BalanceEnemies.GOLD_ROLL_MAX
				)
				gold += roundi(
					BalanceEnemies.enemy_gold(e["level"], e["gold_mult"], roll, gold_find)
				)
				continue
			var qty := sim.loot_rng.range_int(int(entry["qty"][0]), int(entry["qty"][1]))
			var ref: String = entry.get("ref", "")
			match entry["kind"]:
				"material":
					materials[ref] = int(materials.get(ref, 0)) + qty
				"consumable":
					consumables[ref] = int(consumables.get(ref, 0)) + qty
				"artifact":
					if not artifacts.has(ref):
						artifacts.append(ref)
				"item":
					for n in qty:
						var item := (
							ItemFactory.make_item(
								sim.loot_rng,
								sim.content,
								ref,
								ItemFactory.roll_rarity(sim.loot_rng, profile),
								ilvl
							)
							if ref != ""
							else ItemFactory.roll_item(sim.loot_rng, sim.content, profile, ilvl)
						)
						if not item.is_empty():
							items.append(item)
				"rune":
					for n in qty:
						var rune := (
							{
								"id": ref,
								"tier":
								int(
									sim.loot_rng.pick_weighted(
										BalanceGrimoire.RUNE_TIER_WEIGHTS[profile]
									)
								)
							}
							if ref != ""
							else ItemFactory.roll_rune(sim.loot_rng, sim.content, profile)
						)
						if not rune.is_empty():
							runes.append(rune)
	if sim.first_clear:
		xp *= BalanceEnemies.FIRST_CLEAR_XP_MULT
		# Encounter-specific first victory rewards (the cloister key, the
		# guaranteed staff of GDD decision 29). Items: given rarity, ilvl of the
		# encounter, affixes rolled after the table so its draws never shift.
		var first: Dictionary = sim.encounter.get("first_clear_rewards", {})
		var extra: Dictionary = first.get("materials", {})
		for id in extra:
			materials[id] = int(materials.get(id, 0)) + int(extra[id])
		for entry in first.get("items", []):
			var item := ItemFactory.make_item(
				sim.loot_rng, sim.content, entry["base"], entry["rarity"], ilvl
			)
			if not item.is_empty():
				items.append(item)
	return {
		"xp": floori(xp),
		"gold": gold,
		"materials": materials,
		"items": items,
		"runes": runes,
		"artifacts": artifacts,
		"consumables": consumables,
	}


static func empty() -> Dictionary:
	return {
		"xp": 0,
		"gold": 0,
		"materials": {},
		"items": [],
		"runes": [],
		"artifacts": [],
		"consumables": {},
	}


## Rarity profile of a table; the first kill of a boss upgrades it (§14.1).
static func loot_profile(table: Dictionary, first_clear: bool) -> String:
	var profile: String = table.get("rarity_profile", "normal")
	if first_clear and BalanceItems.FIRST_KILL_PROFILE.has(profile):
		return BalanceItems.FIRST_KILL_PROFILE[profile]
	return profile


## Loot entry filter: `when` is "always", "first_clear" or "repeat".
static func applies(entry: Dictionary, first_clear: bool) -> bool:
	match str(entry.get("when", "always")):
		"first_clear":
			return first_clear
		"repeat":
			return not first_clear
	return true
