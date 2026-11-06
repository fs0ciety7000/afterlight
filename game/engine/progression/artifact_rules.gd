class_name ArtifactRules
extends RefCounted
## Artifacts (GDD §10.5, GAME_BALANCE §18): owned artifacts have a level
## (1-5, raised with ashen essence and gold); a character wears up to two.
## Slot 1 opens with the clockmaker's quest (progress.unlocks token), slot 2 at
## ARTIFACT_SLOT_2_LEVEL.


## {type (effect_type), value (at the owned level), level}; level 0 if not owned.
static func effect(state: Dictionary, id: String, content: Dictionary) -> Dictionary:
	var def: Dictionary = content.get(id, {})
	var level := int(state["artifacts"].get(id, 0))
	if def.is_empty() or level < 1:
		return {"type": str(def.get("effect_type", "")), "value": 0.0, "level": 0}
	var values: Array = def["values_by_level"]
	return {
		"type": def["effect_type"],
		"value": float(values[mini(level, values.size()) - 1]),
		"level": level,
	}


## Effects of the artifacts a character wears: [{id, type, value, level}].
static func worn_effects(state: Dictionary, character: String, content: Dictionary) -> Array:
	var out := []
	for id in state["characters"][character].get("artifacts", []):
		if str(id) != "":
			var e := effect(state, id, content)
			e["id"] = id
			out.append(e)
	return out


## Bonus to OFFLINE_EFFICIENCY from worn artifacts (the cracked hourglass).
static func offline_efficiency_bonus(
	state: Dictionary, character: String, content: Dictionary
) -> float:
	var total := 0.0
	for e in worn_effects(state, character, content):
		if e["type"] == "offline_efficiency":
			total += float(e["value"])
	return total


static func slot_level(index: int) -> int:
	return int(BalanceEconomy.ARTIFACT_SLOT_LEVELS[index])


static func slot_open(state: Dictionary, character: String, index: int) -> bool:
	return slot_lock(state, character, index).is_empty()


## Refusal explaining why slot `index` is closed, or {} when it is open.
static func slot_lock(state: Dictionary, character: String, index: int) -> Dictionary:
	if index == 0:
		if state["progress"].get("unlocks", []).has(BalanceEconomy.ARTIFACT_SLOT_1_TOKEN):
			return {}
		return ActionResult.refuse(
			"error.artifact_slot_quest", {"quest": BalanceEconomy.ARTIFACT_SLOT_1_QUEST + ".name"}
		)
	var need := slot_level(index)
	if int(state["characters"].get(character, {}).get("level", 1)) < need:
		return ActionResult.refuse("error.artifact_slot_locked", {"level": need})
	return {}


## Wears an owned artifact in slot `index` (0 or 1). Result extra:
## {index, replaced}.
static func equip(state: Dictionary, character: String, index: int, id: String) -> Dictionary:
	if index < 0 or index >= BalanceEconomy.ARTIFACT_SLOT_LEVELS.size():
		return ActionResult.refuse("error.artifact_slot_empty")
	if not state["artifacts"].has(id) or not state["characters"].has(character):
		return ActionResult.refuse("error.artifact_not_owned", {"artifact": id + ".name"})
	var lock := slot_lock(state, character, index)
	if not lock.is_empty():
		return lock
	var slots: Array = state["characters"][character]["artifacts"]
	for i in slots.size():
		if i != index and slots[i] == id:
			return ActionResult.refuse(
				"error.artifact_already_equipped", {"artifact": id + ".name"}
			)
	var next := state.duplicate(true)
	var replaced: String = next["characters"][character]["artifacts"][index]
	next["characters"][character]["artifacts"][index] = id
	return ActionResult.success(next, {"index": index, "replaced": replaced})


static func unequip(state: Dictionary, character: String, index: int) -> Dictionary:
	if not state["characters"].has(character):
		return ActionResult.refuse("error.artifact_slot_empty")
	var slots: Array = state["characters"][character]["artifacts"]
	if index < 0 or index >= slots.size() or str(slots[index]) == "":
		return ActionResult.refuse("error.artifact_slot_empty")
	var next := state.duplicate(true)
	var removed: String = next["characters"][character]["artifacts"][index]
	next["characters"][character]["artifacts"][index] = ""
	return ActionResult.success(next, {"index": index, "artifact": removed})


## Next level of an owned artifact. Result extra: {artifact, from, to, gold,
## essence}.
static func level_quote(state: Dictionary, id: String) -> Dictionary:
	if not state["artifacts"].has(id):
		return ActionResult.refuse("error.artifact_not_owned", {"artifact": id + ".name"})
	var level := int(state["artifacts"][id])
	if level >= BalanceEconomy.ARTIFACT_MAX_LEVEL:
		return ActionResult.refuse(
			"error.artifact_max_level", {"max": BalanceEconomy.ARTIFACT_MAX_LEVEL}
		)
	var info := {
		"artifact": id,
		"from": level,
		"to": level + 1,
		"gold": BalanceEconomy.artifact_gold(level),
		"essence": BalanceEconomy.artifact_essence(level),
	}
	var lack := ActionResult.check_cost(state["wallet"], _cost(info))
	if not lack.is_empty():
		lack.merge(info)
		return lack
	return ActionResult.success(state, info)


static func level_up(state: Dictionary, id: String) -> Dictionary:
	var q := level_quote(state, id)
	if not q["ok"]:
		return q
	var next := state.duplicate(true)
	ActionResult.pay(next["wallet"], _cost(q))
	next["artifacts"][id] = int(q["to"])
	var extra: Dictionary = q.duplicate()
	extra.erase("state")
	return ActionResult.success(next, extra)


static func _cost(info: Dictionary) -> Dictionary:
	return {"gold": info["gold"], "materials": {BalanceEconomy.ESSENCE_ID: info["essence"]}}
