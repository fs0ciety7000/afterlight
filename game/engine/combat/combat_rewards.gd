class_name CombatRewards
extends RefCounted
## Rewards of a won encounter (GAME_BALANCE §12-§13): XP and gold per enemy
## of the encounter (summons give nothing, so stalling a boss for its adds
## pays nothing), materials from the loot table. Draws use the "loot" stream,
## so the combat sequence never shifts them. Items and runes: Milestone 4.


static func compute(sim: CombatSim) -> Dictionary:
	var leader: Dictionary = sim.units[0]
	var table: Dictionary = sim.def(sim.encounter["loot_table"])
	var gold_find := float(leader["stats"]["gold_find"])
	var xp := 0.0
	var gold := 0
	var materials := {}
	var rewarded := []
	for uid in sim.kills:
		var e: Dictionary = sim.unit(uid)
		if e["summoner"] == "":
			rewarded.append(e)
	if rewarded.is_empty():
		return {"xp": 0, "gold": 0, "materials": {}}
	for e in rewarded:
		xp += (
			BalanceEnemies.enemy_xp(e["level"], e["xp_mult"])
			* BalanceEnemies.xp_penalty(leader["level"], e["level"])
		)
	for entry in table.get("entries", []):
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
			elif entry["kind"] == "material":
				var qty := sim.loot_rng.range_int(int(entry["qty"][0]), int(entry["qty"][1]))
				materials[entry["ref"]] = int(materials.get(entry["ref"], 0)) + qty
	if sim.first_clear:
		xp *= BalanceEnemies.FIRST_CLEAR_XP_MULT
	return {"xp": floori(xp), "gold": gold, "materials": materials}
