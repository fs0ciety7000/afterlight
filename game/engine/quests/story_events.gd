class_name StoryEvents
extends RefCounted
## Routes engine events to quests, contracts, the bestiary and the dungeon
## run. Pure; every function mutates `next` (a copy owned by the caller) and
## appends what changed to `events`.
##
## Only fights played in the scene come here (normal fights and "Chasser
## ici"): the offline claim (OfflineCalc) never does, so offline victories
## count for no quest, contract or bestiary entry (GDD decision 12).


## A played fight end to end: CombatOutcome (XP, gold, loot, clears) then
## on_combat. Returns {state, summary (CombatOutcome's, plus `events`)}.
static func apply_fight(
	state: Dictionary, completed: Dictionary, content: Dictionary
) -> Dictionary:
	var r := CombatOutcome.apply(state, completed, content)
	var next: Dictionary = r["state"]
	var events := []
	on_combat(next, completed, content, events)
	var summary: Dictionary = r["summary"]
	summary["events"] = events
	return {"state": next, "summary": summary}


## A played fight, after CombatOutcome applied it: CombatSim's
## encounter_completed {encounter, result, rewards, tally, leader, ...}.
static func on_combat(
	next: Dictionary, completed: Dictionary, content: Dictionary, events: Array
) -> void:
	Bestiary.record(next, completed, content, events)
	DungeonRun.on_combat(next, completed, content, events)
	QuestRules.on_event(next, completed, content, events)
	Contracts.on_event(next, completed, content, events)
	if completed.get("result", "") == "victory":
		var materials: Dictionary = completed.get("rewards", {}).get("materials", {})
		var ids := materials.keys()
		ids.sort()
		for id in ids:
			var collected := {"type": "item_collected", "item_id": id, "qty": int(materials[id])}
			QuestRules.on_event(next, collected, content, events)
	QuestRules.refresh_all(next, content, events)


## Any other engine event: talked_to {npc_id, dialogue_id}, location_visited
## {location_id}, discovery_found {discovery_id, location_id}, item_collected
## {item_id, qty}.
static func feed(next: Dictionary, event: Dictionary, content: Dictionary, events: Array) -> void:
	QuestRules.on_event(next, event, content, events)
	QuestRules.refresh_all(next, content, events)


## A location (or dungeon) was entered: the state objectives see it.
static func visited(next: Dictionary, place_id: String, content: Dictionary, events: Array) -> void:
	feed(next, {"type": "location_visited", "location_id": place_id}, content, events)


## Loading a save: quests re-measured from the state, dungeon run settled.
## Returns true when the state changed.
static func on_load(next: Dictionary, content: Dictionary) -> bool:
	var before := JSON.stringify(next["progress"])
	var events := []
	QuestRules.refresh_all(next, content, events)
	var moved := DungeonRun.settle_on_load(next, content)
	return moved or before != JSON.stringify(next["progress"])
