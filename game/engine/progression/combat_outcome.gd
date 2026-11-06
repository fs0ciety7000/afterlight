class_name CombatOutcome
extends RefCounted
## Applies the result of an encounter (the sim's encounter_completed event)
## to a game state. Pure: returns a new state and a summary for the UI.


static func apply(state: Dictionary, completed: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var summary := {
		"result": completed.get("result", ""),
		"xp": 0,
		"gold": 0,
		"materials": {},
		"levels_gained": 0,
		"level": 0,
		"wasted_xp": 0
	}
	var leader: String = next["party"][0]
	summary["level"] = next["characters"][leader]["level"]
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
		wallet["materials"][id] = int(wallet["materials"].get(id, 0)) + int(materials[id])
	var cleared: Dictionary = next["progress"]["cleared_encounters"]
	var encounter: String = completed.get("encounter", "")
	cleared[encounter] = int(cleared.get(encounter, 0)) + 1
	summary["xp"] = xp
	summary["gold"] = int(rewards.get("gold", 0))
	summary["materials"] = materials.duplicate()
	summary["levels_gained"] = leveled["levels_gained"]
	summary["level"] = leveled["level"]
	summary["wasted_xp"] = leveled["wasted"]
	return {"state": next, "summary": summary}
