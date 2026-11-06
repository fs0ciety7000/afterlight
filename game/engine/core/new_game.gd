class_name NewGame
extends RefCounted
## Builds the initial state of a new game from content. Pure: the seed and
## the current time are parameters.


## `start` is the content's start definition (see game/data/*/start.json):
## {party: [character ids], region, location, gold, materials}.
static func create(
	start: Dictionary, seed_value: int, now_unix: int, content: Dictionary = {}
) -> Dictionary:
	var party: Array = []
	var characters := {}
	for i in StateSchema.PARTY_SLOTS:
		var member: String = start["party"][i] if i < start["party"].size() else ""
		party.append(member)
		if member != "":
			characters[member] = _new_character()
	var state := {
		"meta":
		{"seed": seed_value, "created_at": now_unix, "last_active_at": now_unix, "play_time": 0.0},
		"party": party,
		"characters": characters,
		"wallet":
		{"gold": int(start.get("gold", 0)), "materials": start.get("materials", {}).duplicate()},
		"inventory": [],
		"runes": {},
		"consumables": {},
		"artifacts": {},
		"world":
		{
			"region_id": start["region"],
			"location_id": start["location"],
			"unlocked_regions": [start["region"]],
			"discovered_locations": [start["location"]],
			"revealed_locations": [start["location"]],
			"spawn": "default",
		},
		"progress": {"cleared_encounters": {}, "quests": {}, "bestiary": {}, "discoveries": []},
		"farming": "",
		"offline": {"pending": []},
		"rng": {},
	}
	if not content.is_empty():
		WorldRules.visit(start["location"], state, content)
	return state


static func _new_character() -> Dictionary:
	var equipment := {}
	for slot in StateSchema.EQUIPMENT_SLOTS:
		equipment[slot] = ""
	var artifacts := []
	for i in StateSchema.ARTIFACT_SLOTS:
		artifacts.append("")
	return {
		"level": 1,
		"xp": 0,
		"equipment": equipment,
		"spells": {},
		"loadout": [],
		"runes": {},
		"artifacts": artifacts,
	}
