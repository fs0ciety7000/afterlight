class_name WorldRules
extends RefCounted
## Unlock conditions, fog of war and travel. Pure: works on plain state and
## content dictionaries (see docs/GDD.md §5.1, docs/CONTENT_PIPELINE.md §5.3).
##
## A location is, for the player:
##   "hidden"    under the fog (never revealed),
##   "locked"    revealed but its unlock condition is not met,
##   "available" revealed and unlocked: the player can travel there.

const HIDDEN := "hidden"
const LOCKED := "locked"
const AVAILABLE := "available"


## True when `condition` holds for `state`. `content` maps id -> entity.
static func is_met(condition: Dictionary, state: Dictionary, content: Dictionary) -> bool:
	if condition.is_empty():
		return true
	var key: String = condition.keys()[0]
	var value: Variant = condition[key]
	match key:
		"start":
			return value == true
		"level_at_least":
			return leader_level(state) >= int(value)
		"quest_completed":
			return (
				state["progress"]["quests"].get(str(value), {}).get("state", "")
				== QuestRules.TURNED_IN
			)
		"quest_state":
			var quest_state: String = QuestRules.state_of(state, str(value["id"]), content)
			if value["state"] == "not_started":
				return quest_state in [QuestRules.AVAILABLE, QuestRules.LOCKED]
			return quest_state == value["state"]
		"objective":
			var done: bool = QuestRules.objective_done(
				state, str(value["quest"]), str(value["id"]), content
			)
			return done == bool(value["done"])
		"discovery_found":
			return state["progress"]["discoveries"].has(str(value))
		"location_cleared":
			return _location_cleared(str(value), state, content)
		"item_owned":
			for item in state["inventory"]:
				if item["item_id"] == value:
					return true
			return false
		"all":
			for sub in value:
				if not is_met(sub, state, content):
					return false
			return true
	return false


## Translation key and parameters explaining why `condition` is not met.
## The UI formats it with tr(key).format(params).
static func reason(condition: Dictionary, state: Dictionary, content: Dictionary) -> Dictionary:
	var key: String = condition.keys()[0] if not condition.is_empty() else ""
	var value: Variant = condition.get(key)
	match key:
		"level_at_least":
			return {"key": "ui.lock.level", "params": {"level": int(value)}}
		"quest_completed":
			return {
				"key": "ui.lock.quest",
				"params": {"quest": content.get(str(value), {}).get("name_key", str(value))}
			}
		"location_cleared":
			return {
				"key": "ui.lock.location_cleared",
				"params": {"location": content.get(str(value), {}).get("name_key", str(value))}
			}
		"item_owned":
			return {
				"key": "ui.lock.item",
				"params": {"item": content.get(str(value), {}).get("name_key", str(value))}
			}
		"all":
			for sub in value:
				if not is_met(sub, state, content):
					return reason(sub, state, content)
	return {"key": "ui.lock.unknown", "params": {}}


static func leader_level(state: Dictionary) -> int:
	var leader: String = state["party"][0]
	return int(state["characters"].get(leader, {}).get("level", 1))


static func status(location_id: String, state: Dictionary, content: Dictionary) -> String:
	var world: Dictionary = state["world"]
	if not world["revealed_locations"].has(location_id):
		return HIDDEN
	var location: Dictionary = content.get(location_id, {})
	if location.is_empty() or not is_met(location["unlock"], state, content):
		return LOCKED
	return AVAILABLE


## Lifts the fog over a location or dungeon (a quest unlock, a discovery).
## Mutates `state`.
static func reveal(state: Dictionary, place_id: String) -> void:
	_add_unique(state["world"]["revealed_locations"], place_id)


## Marks a location visited: discovered, and the locations it reveals lose
## their fog. Mutates and returns `state`.
static func visit(location_id: String, state: Dictionary, content: Dictionary) -> Dictionary:
	var world: Dictionary = state["world"]
	_add_unique(world["discovered_locations"], location_id)
	_add_unique(world["revealed_locations"], location_id)
	for other in content.get(location_id, {}).get("fog_reveal", []):
		_add_unique(world["revealed_locations"], other)
	return state


## Moves the party to `location_id` at `spawn`. Returns {ok, state, error}.
## Errors: "unknown_location", "not_available", "same_location".
static func travel(
	location_id: String, spawn: String, state: Dictionary, content: Dictionary
) -> Dictionary:
	if not content.has(location_id) or content[location_id]["_type"] != "location":
		return {"ok": false, "state": state, "error": "unknown_location"}
	if status(location_id, state, content) != AVAILABLE:
		return {"ok": false, "state": state, "error": "not_available"}
	var next := state.duplicate(true)
	var world: Dictionary = next["world"]
	world["location_id"] = location_id
	world["region_id"] = content[location_id]["region"]
	world["spawn"] = spawn
	visit(location_id, next, content)
	return {"ok": true, "state": next, "error": ""}


static func _location_cleared(location_id: String, state: Dictionary, content: Dictionary) -> bool:
	var encounters: Array = content.get(location_id, {}).get("encounters", [])
	if encounters.is_empty():
		return state["world"]["discovered_locations"].has(location_id)
	for e in encounters:
		if int(state["progress"]["cleared_encounters"].get(e, 0)) < 1:
			return false
	return true


static func _add_unique(list: Array, value: String) -> void:
	if not list.has(value):
		list.append(value)
