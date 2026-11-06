class_name NpcRules
extends RefCounted
## Talking to NPCs (docs/content/dialogues.md §1). An NPC lists
## {dialogue, condition, offers?, turns_in?}: the first entry whose condition
## holds is played. Its end sends talked_to (TalkedTo objectives), then
## activates the offered quest or hands in the completed one. Pure.


## The dialogue an NPC plays now: {npc_id, dialogue, offers, turns_in, role,
## lines: [{speaker, key}]}, or {} for an unknown NPC. Quests are measured
## first (shards held, discoveries made), on a copy.
static func select(state: Dictionary, npc_id: String, content: Dictionary) -> Dictionary:
	var npc: Dictionary = content.get(npc_id, {})
	if npc.get("_type", "") != "npc":
		return {}
	var fresh := state.duplicate(true)
	QuestRules.refresh_all(fresh, content, [])
	return _pick(fresh, npc, content)


static func _pick(state: Dictionary, npc: Dictionary, content: Dictionary) -> Dictionary:
	for entry in npc["dialogues"]:
		if entry["condition"].is_empty() or WorldRules.is_met(entry["condition"], state, content):
			return _selection(npc, entry, state, content)
	return {}


static func _selection(
	npc: Dictionary, entry: Dictionary, state: Dictionary, content: Dictionary
) -> Dictionary:
	var dialogue: Dictionary = content.get(entry["dialogue"], {})
	var lines := []
	for line in dialogue.get("lines", []):
		if line.has("condition") and not WorldRules.is_met(line["condition"], state, content):
			continue
		lines.append(
			{"speaker": line["speaker"], "key": "%s.%s" % [dialogue["id"], line["key_suffix"]]}
		)
	return {
		"npc_id": npc["id"],
		"dialogue": entry["dialogue"],
		"offers": entry["offers"],
		"turns_in": entry["turns_in"],
		"role": npc["role"],
		"lines": lines,
	}


## Quest marker over an NPC's head: "turn_in" (gold diamond), "offer" (full
## diamond), "active" (hollow diamond) or "".
static func marker(state: Dictionary, npc_id: String, content: Dictionary) -> String:
	var fresh := state.duplicate(true)
	QuestRules.refresh_all(fresh, content, [])
	var best := ""
	for id in content:
		var q: Dictionary = content[id]
		if q.get("_type", "") != "quest" or q.get("giver", "") != npc_id:
			continue
		var s := QuestRules.state_of(fresh, id, content)
		if s == QuestRules.COMPLETED or (s == QuestRules.ACTIVE and _only_talk_left(fresh, q)):
			return "turn_in"
		if s == QuestRules.AVAILABLE:
			best = "offer"
		elif s == QuestRules.ACTIVE and best == "":
			best = "active"
	return best


## An active quest whose current step only asks to talk to its giver.
static func _only_talk_left(state: Dictionary, q: Dictionary) -> bool:
	var e := QuestRules.entry(state, q["id"])
	var left := 0
	for o in q["objectives"]:
		if int(o["step"]) != int(e["step"]):
			continue
		if int(e["counts"].get(o["id"], 0)) >= int(o["count"]):
			continue
		if o["event"] != "TalkedTo" or o["target"] != q["giver"]:
			return false
		left += 1
	return left > 0


## End of a dialogue (played to the end or skipped: effects apply anyway).
## Result extra: {events, dialogue, offered, turned_in, rewards, next_dialogue
## (the NPC's next selection when it offers or hands in a quest: play it right
## after, e.g. the hand-in that follows a talk which completed the quest)}.
static func finish(
	state: Dictionary, npc_id: String, dialogue_id: String, content: Dictionary
) -> Dictionary:
	if content.get(npc_id, {}).get("_type", "") != "npc":
		return ActionResult.refuse("error.npc.unknown")
	var next := state.duplicate(true)
	var events := []
	QuestRules.refresh_all(next, content, events)
	var current := _pick(next, content[npc_id], content)
	if current.get("dialogue", "") != dialogue_id:
		return ActionResult.refuse("error.dialogue.mismatch")
	StoryEvents.feed(
		next, {"type": "talked_to", "npc_id": npc_id, "dialogue_id": dialogue_id}, content, events
	)
	var offered := ""
	var turned := ""
	var rewards := {}
	if (
		current["offers"] != ""
		and QuestRules.state_of(next, current["offers"], content) == "available"
	):
		QuestRules.activate(next, current["offers"], content, events)
		offered = current["offers"]
	var quest_id: String = current["turns_in"]
	if quest_id != "" and QuestRules.state_of(next, quest_id, content) == QuestRules.COMPLETED:
		rewards = QuestRules.hand_in(next, quest_id, content)
		events.append(rewards)
		turned = quest_id
		QuestRules.refresh_all(next, content, events)
	var follow := _pick(next, content[npc_id], content)
	var next_dialogue := ""
	if not follow.is_empty() and (follow["offers"] != "" or follow["turns_in"] != ""):
		var target: String = follow["offers"] if follow["offers"] != "" else follow["turns_in"]
		var wanted := QuestRules.AVAILABLE if follow["offers"] != "" else QuestRules.COMPLETED
		if (
			QuestRules.state_of(next, target, content) == wanted
			and follow["dialogue"] != dialogue_id
		):
			next_dialogue = follow["dialogue"]
	return (
		ActionResult
		. success(
			next,
			{
				"events": events,
				"dialogue": dialogue_id,
				"offered": offered,
				"turned_in": turned,
				"rewards": rewards,
				"next_dialogue": next_dialogue,
			}
		)
	)
