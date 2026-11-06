class_name CombatOutcome
extends RefCounted
## Applies the result of an encounter (the sim's encounter_completed event)
## to a game state. Pure: returns a new state and a summary for the UI.
##
## summary: {result, xp, gold, materials, levels_gained, level, wasted_xp,
##  items: [uid], auto_salvaged: [...], salvage_dust, runes: [{id, tier}],
##  artifacts: [id], consumables: {id: n}, consumables_used: {id: n},
##  lines: [{key, params}]} (see Inventory.receive for the loot fields).


static func apply(state: Dictionary, completed: Dictionary, content: Dictionary = {}) -> Dictionary:
	var next := state.duplicate(true)
	var summary := {
		"result": completed.get("result", ""),
		"xp": 0,
		"gold": 0,
		"materials": {},
		"levels_gained": 0,
		"level": 0,
		"wasted_xp": 0,
		"items": [],
		"auto_salvaged": [],
		"salvage_dust": 0,
		"runes": [],
		"artifacts": [],
		"consumables": {},
		"consumables_used": {},
		"lines": [],
	}
	var leader: String = next["party"][0]
	summary["level"] = next["characters"][leader]["level"]
	var used: Dictionary = completed.get("consumables_used", {})
	for id in used:
		var left := int(next["consumables"].get(id, 0)) - int(used[id])
		if left > 0:
			next["consumables"][id] = left
		else:
			next["consumables"].erase(id)
	summary["consumables_used"] = used.duplicate()
	if completed.get("result", "") != "victory":
		return {"state": next, "summary": summary}
	var rewards: Dictionary = completed.get("rewards", {})
	var xp := int(rewards.get("xp", 0))
	var hero: Dictionary = next["characters"][leader]
	var leveled := BalanceProgression.grant_xp(hero["level"], hero["xp"], xp)
	hero["level"] = leveled["level"]
	hero["xp"] = leveled["xp"]
	var wallet: Dictionary = next["wallet"]
	wallet["gold"] = int(wallet["gold"]) + int(rewards.get("gold", 0))
	var materials: Dictionary = rewards.get("materials", {})
	for id in materials:
		Inventory.add_material(next, id, int(materials[id]))
	var cleared: Dictionary = next["progress"]["cleared_encounters"]
	var encounter: String = completed.get("encounter", "")
	cleared[encounter] = int(cleared.get(encounter, 0)) + 1
	summary["xp"] = xp
	summary["gold"] = int(rewards.get("gold", 0))
	summary["materials"] = materials.duplicate()
	summary["levels_gained"] = leveled["levels_gained"]
	summary["level"] = leveled["level"]
	summary["wasted_xp"] = leveled["wasted"]
	if int(leveled["wasted"]) > 0:
		summary["lines"].append({"key": "log.xp_wasted", "params": {"xp": leveled["wasted"]}})
	var loot := Inventory.receive(next, rewards, content)
	for key in loot:
		if key == "lines":
			summary["lines"].append_array(loot["lines"])
		else:
			summary[key] = loot[key]
	return {"state": next, "summary": summary}
