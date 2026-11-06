class_name QuestRules
extends RefCounted
## Quest state machine (docs/content/quests.md §1). Pure: works on plain state
## and content dictionaries.
##
## progress.quests[quest_id] = {state, step, counts: {objective_id: n}, order}
##   state: "active" -> "completed" (objectives met, not handed in) ->
##   "turned_in" (rewards credited once). Without an entry a quest is
##   "available" (prerequisites met) or "locked".
## Objectives carry a `step`; objectives of a step advance together, a later
## step waits. Counter objectives only move on engine events received while
## the quest is active; state objectives (DiscoveryFound, LocationVisited,
## ItemDelivered, ItemCollected of a unique item) are measured from the state
## at activation, on every event and at load.
##
## Events (plain dictionaries, appended to the caller's list):
##   quest_activated {quest}, quest_progress {quest, objective, count, target},
##   quest_step_advanced {quest, step}, quest_completed {quest},
##   quest_reopened {quest}, quest_turned_in {quest, xp, gold, materials, runes,
##   artifacts, unlocks, levels_gained, level}.

const LOCKED := "locked"
const AVAILABLE := "available"
const ACTIVE := "active"
const COMPLETED := "completed"
const TURNED_IN := "turned_in"
const STATE_EVENTS := ["DiscoveryFound", "LocationVisited", "ItemDelivered"]


static func entry(state: Dictionary, quest_id: String) -> Dictionary:
	return state["progress"]["quests"].get(quest_id, {})


## "locked", "available", "active", "completed" or "turned_in".
static func state_of(state: Dictionary, quest_id: String, content: Dictionary) -> String:
	var e := entry(state, quest_id)
	if not e.is_empty():
		return str(e["state"])
	var q: Dictionary = content.get(quest_id, {})
	if q.is_empty() or q.get("kind", "") == "daily":
		return LOCKED
	return AVAILABLE if prerequisites_met(state, q, content) else LOCKED


static func prerequisites_met(state: Dictionary, q: Dictionary, content: Dictionary) -> bool:
	for c in q.get("prerequisites", []):
		if not WorldRules.is_met(c, state, content):
			return false
	return true


## True when the quest's objective `objective_id` is met.
static func objective_done(
	state: Dictionary, quest_id: String, objective_id: String, content: Dictionary
) -> bool:
	var e := entry(state, quest_id)
	if e.is_empty():
		return false
	if str(e["state"]) in [COMPLETED, TURNED_IN]:
		return true
	for o in content.get(quest_id, {}).get("objectives", []):
		if o["id"] == objective_id:
			return int(e["counts"].get(objective_id, 0)) >= int(o["count"])
	return false


## Whether an objective is measured from the state rather than counted.
static func is_state_objective(o: Dictionary, content: Dictionary) -> bool:
	if STATE_EVENTS.has(o["event"]):
		return true
	if o["event"] == "ItemCollected":
		var target: Dictionary = content.get(o["target"], {})
		return target.get("_type", "") == "artifact" or int(target.get("stack_max", 0)) == 1
	return false


## Current value of a state objective (uncapped).
static func measure(o: Dictionary, state: Dictionary) -> int:
	var target: String = o["target"]
	match o["event"]:
		"DiscoveryFound":
			return 1 if state["progress"]["discoveries"].has(target) else 0
		"LocationVisited":
			return 1 if state["world"]["discovered_locations"].has(target) else 0
		"ItemCollected", "ItemDelivered":
			if target.begins_with("artifact."):
				return 1 if state["artifacts"].has(target) else 0
			return int(state["wallet"]["materials"].get(target, 0))
	return 0


## How much an engine event moves a counter objective. Events:
##   encounter_completed {encounter, result, tally, ...} (CombatSim payload),
##   talked_to {npc_id, dialogue_id}, item_collected {item_id, qty}.
## The tally counts kills, interrupts and statuses of the fight (summons
## included); a lost fight still counts its kills, never the encounter.
static func gain(o: Dictionary, event: Dictionary, content: Dictionary) -> int:
	var target: String = o["target"]
	match [str(event.get("type", "")), str(o["event"])]:
		["encounter_completed", "EncounterCompleted"]:
			if event.get("result", "") != "victory":
				return 0
			var encounter: String = event.get("encounter", "")
			if encounter == target:
				return 1
			var place: Dictionary = content.get(target, {})
			if place.get("_type", "") == "location" and place["encounters"].has(encounter):
				return 1
		["encounter_completed", "EnemyDefeated"]:
			return int(event.get("tally", {}).get("defeated", {}).get(target, 0))
		["encounter_completed", "CastInterrupted"]:
			return int(event.get("tally", {}).get("interrupts", {}).get(target, 0))
		["encounter_completed", "StatusApplied"]:
			var by_source: Dictionary = event.get("tally", {}).get("statuses", {}).get(target, {})
			if str(o.get("source", "")) != "":
				return int(by_source.get(o["source"], 0))
			var total := 0
			for k in by_source:
				total += int(by_source[k])
			return total
		["talked_to", "TalkedTo"]:
			return 1 if event.get("npc_id", "") == target else 0
		["item_collected", "ItemCollected"]:
			return int(event.get("qty", 0)) if event.get("item_id", "") == target else 0
	return 0


# --- Transitions (mutate `next`, a copy owned by the caller) --------------------


## Starts a quest: active, step 1, then the state objectives are measured.
static func activate(
	next: Dictionary, quest_id: String, content: Dictionary, events: Array
) -> void:
	var order := 0
	for id in next["progress"]["quests"]:
		order = maxi(order, int(next["progress"]["quests"][id].get("order", 0)))
	next["progress"]["quests"][quest_id] = {
		"state": ACTIVE, "step": 1, "counts": {}, "order": order + 1
	}
	events.append({"type": "quest_activated", "quest": quest_id})
	refresh(next, quest_id, content, events)


## Measures the state objectives, advances steps and flips active/completed.
static func refresh(next: Dictionary, quest_id: String, content: Dictionary, events: Array) -> void:
	var e := entry(next, quest_id)
	var q: Dictionary = content.get(quest_id, {})
	if e.is_empty() or q.is_empty() or e["state"] == TURNED_IN:
		return
	var objectives: Array = q["objectives"]
	var last_step := 1
	for o in objectives:
		last_step = maxi(last_step, int(o["step"]))
	if e["state"] == COMPLETED:
		for o in objectives:
			if is_state_objective(o, content):
				_measure_into(e, o, next, quest_id, events)
			if not _done(e, o):
				e["state"] = ACTIVE
				e["step"] = int(o["step"])
				events.append({"type": "quest_reopened", "quest": quest_id})
				break
		if e["state"] == COMPLETED:
			return
	while true:
		var step := int(e["step"])
		var all_done := true
		for o in objectives:
			if int(o["step"]) > step:
				continue
			if is_state_objective(o, content):
				_measure_into(e, o, next, quest_id, events)
			if int(o["step"]) == step and not _done(e, o):
				all_done = false
		if not all_done:
			return
		if step >= last_step:
			e["state"] = COMPLETED
			events.append({"type": "quest_completed", "quest": quest_id})
			return
		e["step"] = step + 1
		events.append({"type": "quest_step_advanced", "quest": quest_id, "step": step + 1})


static func _done(e: Dictionary, o: Dictionary) -> bool:
	return int(e["counts"].get(o["id"], 0)) >= int(o["count"])


static func _measure_into(
	e: Dictionary, o: Dictionary, state: Dictionary, quest_id: String, events: Array
) -> void:
	var value := mini(measure(o, state), int(o["count"]))
	if value != int(e["counts"].get(o["id"], 0)):
		e["counts"][o["id"]] = value
		events.append(_progress_event(quest_id, o, value))


static func _progress_event(quest_id: String, o: Dictionary, value: int) -> Dictionary:
	return {
		"type": "quest_progress",
		"quest": quest_id,
		"objective": o["id"],
		"count": value,
		"target": int(o["count"]),
	}


## Feeds an engine event to every active quest (current step only).
static func on_event(
	next: Dictionary, event: Dictionary, content: Dictionary, events: Array
) -> void:
	var ids: Array = next["progress"]["quests"].keys()
	ids.sort()
	for quest_id in ids:
		var e: Dictionary = next["progress"]["quests"][quest_id]
		var q: Dictionary = content.get(quest_id, {})
		if e["state"] != ACTIVE or q.is_empty() or q["kind"] == "daily":
			continue
		for o in q["objectives"]:
			if int(o["step"]) != int(e["step"]) or is_state_objective(o, content):
				continue
			var add := gain(o, event, content)
			var have := int(e["counts"].get(o["id"], 0))
			if add > 0 and have < int(o["count"]):
				var value := mini(int(o["count"]), have + add)
				e["counts"][o["id"]] = value
				events.append(_progress_event(quest_id, o, value))
		refresh(next, quest_id, content, events)


## Re-measures every open quest (after any state change, and at load).
static func refresh_all(next: Dictionary, content: Dictionary, events: Array) -> void:
	var ids: Array = next["progress"]["quests"].keys()
	ids.sort()
	for quest_id in ids:
		refresh(next, quest_id, content, events)


## Activates the quests flagged active_at_start (new game).
static func start_quests(next: Dictionary, content: Dictionary, events: Array) -> void:
	var ids: Array = []
	for id in content:
		var q: Dictionary = content[id]
		if q.get("_type", "") == "quest" and q.get("active_at_start", false):
			ids.append(id)
	ids.sort()
	for id in ids:
		if entry(next, id).is_empty() and prerequisites_met(next, content[id], content):
			activate(next, id, content, events)


## Credits a completed quest once: XP, gold, materials, runes, artifacts and
## unlocks; delivered items are taken. Returns the quest_turned_in event.
static func hand_in(next: Dictionary, quest_id: String, content: Dictionary) -> Dictionary:
	var q: Dictionary = content[quest_id]
	var rewards: Dictionary = q["rewards"]
	for o in q["objectives"]:
		if o["event"] == "ItemDelivered":
			var have := int(next["wallet"]["materials"].get(o["target"], 0))
			next["wallet"]["materials"][o["target"]] = maxi(0, have - int(o["count"]))
	var leader: String = next["party"][0]
	var hero: Dictionary = next["characters"][leader]
	var xp := BalanceStory.quest_xp(
		q["kind"], int(q.get("level", hero["level"])), float(rewards.get("xp_factor", -1.0))
	)
	var leveled := BalanceProgression.grant_xp(hero["level"], hero["xp"], xp)
	hero["level"] = leveled["level"]
	hero["xp"] = leveled["xp"]
	next["wallet"]["gold"] = int(next["wallet"]["gold"]) + int(rewards["gold"])
	for id in rewards["materials"]:
		Inventory.add_material(next, id, int(rewards["materials"][id]))
	var artifacts := []
	for id in rewards["artifacts"]:
		if not next["artifacts"].has(id):
			next["artifacts"][id] = 1
			artifacts.append(id)
	for rune in rewards["runes"]:
		Inventory.add_rune(next, rune["id"], int(rune["tier"]))
	for token in rewards["unlocks"]:
		if content.has(token):
			WorldRules.reveal(next, str(token))
		elif not next["progress"]["unlocks"].has(token):
			next["progress"]["unlocks"].append(token)
	next["progress"]["quests"][quest_id]["state"] = TURNED_IN
	return {
		"type": "quest_turned_in",
		"quest": quest_id,
		"xp": xp,
		"gold": int(rewards["gold"]),
		"materials": rewards["materials"].duplicate(),
		"runes": rewards["runes"].duplicate(true),
		"artifacts": artifacts,
		"unlocks": rewards["unlocks"].duplicate(),
		"levels_gained": leveled["levels_gained"],
		"level": leveled["level"],
		"memory": bool(rewards.get("memory", false)),
	}


# --- Actions (ActionResult; the input state is never mutated) -------------------


## Accepts an available quest (end of the giver's offer dialogue).
static func accept(state: Dictionary, quest_id: String, content: Dictionary) -> Dictionary:
	if content.get(quest_id, {}).get("_type", "") != "quest":
		return ActionResult.refuse("error.quest.unknown")
	match state_of(state, quest_id, content):
		AVAILABLE:
			pass
		LOCKED:
			return ActionResult.refuse("error.quest.not_available")
		_:
			return ActionResult.refuse("error.quest.already_started")
	var next := state.duplicate(true)
	var events := []
	activate(next, quest_id, content, events)
	return ActionResult.success(next, {"quest": quest_id, "events": events})


## Hands in a completed quest: rewards once, then the quest is turned in.
static func turn_in(state: Dictionary, quest_id: String, content: Dictionary) -> Dictionary:
	if content.get(quest_id, {}).get("_type", "") != "quest":
		return ActionResult.refuse("error.quest.unknown")
	var next := state.duplicate(true)
	var events := []
	refresh(next, quest_id, content, events)
	if state_of(next, quest_id, content) != COMPLETED:
		return ActionResult.refuse("error.quest.not_completed")
	var done := hand_in(next, quest_id, content)
	events.append(done)
	refresh_all(next, content, events)
	return ActionResult.success(next, {"quest": quest_id, "events": events, "rewards": done})


# --- Views ----------------------------------------------------------------------


## Quest log: every started quest (not the dailies), main quests first, then
## by acceptance. [{id, kind, state, step, giver, level, order, objectives:
## [{id, step, event, target, key, count, needed, done, visible}]}]
static func log_view(state: Dictionary, content: Dictionary) -> Array:
	var out := []
	for quest_id in state["progress"]["quests"]:
		var q: Dictionary = content.get(quest_id, {})
		if q.is_empty() or q["kind"] == "daily":
			continue
		var e: Dictionary = state["progress"]["quests"][quest_id]
		var objectives := []
		for o in q["objectives"]:
			var finished: bool = e["state"] != ACTIVE
			var count := int(o["count"]) if finished else int(e["counts"].get(o["id"], 0))
			(
				objectives
				. append(
					{
						"id": o["id"],
						"step": int(o["step"]),
						"event": o["event"],
						"target": o["target"],
						"key": "%s.objective_%s" % [quest_id, o["id"]],
						"count": count,
						"needed": int(o["count"]),
						"done": count >= int(o["count"]),
						"visible": finished or int(o["step"]) <= int(e["step"]),
					}
				)
			)
		(
			out
			. append(
				{
					"id": quest_id,
					"kind": q["kind"],
					"state": e["state"],
					"step": int(e["step"]),
					"giver": q.get("giver", ""),
					"level": int(q.get("level", 1)),
					"order": int(e.get("order", 0)),
					"objectives": objectives,
				}
			)
		)
	out.sort_custom(_log_before)
	return out


static func _log_before(a: Dictionary, b: Dictionary) -> bool:
	if (a["kind"] == "main") != (b["kind"] == "main"):
		return a["kind"] == "main"
	return a["order"] < b["order"]


## Quest followed by the HUD: the open main quest, else the last side quest
## accepted that is still open; "" if none.
static func tracked(state: Dictionary, content: Dictionary) -> String:
	var best := ""
	var best_order := -1
	for quest_id in state["progress"]["quests"]:
		var e: Dictionary = state["progress"]["quests"][quest_id]
		var q: Dictionary = content.get(quest_id, {})
		if q.is_empty() or e["state"] == TURNED_IN or q["kind"] == "daily":
			continue
		if q["kind"] == "main":
			return quest_id
		if int(e.get("order", 0)) > best_order:
			best_order = int(e.get("order", 0))
			best = quest_id
	return best


## Rewards a quest would give now: {xp, gold, materials, runes, artifacts,
## unlocks, memory} (journal and offer preview).
static func reward_preview(state: Dictionary, quest_id: String, content: Dictionary) -> Dictionary:
	var q: Dictionary = content.get(quest_id, {})
	if q.is_empty():
		return {}
	var rewards: Dictionary = q["rewards"]
	var hero: Dictionary = state["characters"][state["party"][0]]
	return {
		"xp":
		BalanceStory.quest_xp(
			q["kind"], int(q.get("level", hero["level"])), float(rewards.get("xp_factor", -1.0))
		),
		"gold": int(rewards["gold"]),
		"materials": rewards["materials"].duplicate(),
		"runes": rewards["runes"].duplicate(true),
		"artifacts": rewards["artifacts"].duplicate(),
		"unlocks": rewards["unlocks"].duplicate(),
		"memory": bool(rewards.get("memory", false)),
	}
