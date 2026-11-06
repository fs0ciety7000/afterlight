class_name SaveMigrations
extends RefCounted
## Save format migrations: version n -> n + 1. Never edit a released step;
## add a new one and bump SaveCodec.CURRENT_VERSION.
##
## Each step gets a test in tests/unit/persistence/test_migrations.gd.

## Ids removed from the content through a migration (V20: a reference save may
## still hold them). Empty so far.
const RETIRED_IDS := {}


static func all() -> Dictionary:
	return {1: v1_to_v2, 2: v2_to_v3, 3: v3_to_v4, 4: v4_to_v5, 5: v5_to_v6}


## v2 (Milestone 2): fog of war and spawn point.
## revealed_locations starts as the discovered ones; spawn is "default".
static func v1_to_v2(state: Dictionary) -> Dictionary:
	var world: Dictionary = state["world"]
	world["revealed_locations"] = (world["discovered_locations"] as Array).duplicate()
	world["spawn"] = "default"
	return state


## v3 (Milestone 4): progression. Items gain legendary, enhance_attempts and
## pity (sockets moved to spells); characters gain socketed runes and artifact
## slots; rune, consumable and artifact stocks start empty.
static func v2_to_v3(state: Dictionary) -> Dictionary:
	for item in state.get("inventory", []):
		item.erase("sockets")
		item["legendary"] = ""
		item["enhance_attempts"] = 0
		item["pity"] = 0
	for id in state.get("characters", {}):
		var c: Dictionary = state["characters"][id]
		c["runes"] = {}
		c["artifacts"] = ["", ""]
	state["runes"] = {}
	state["consumables"] = {}
	state["artifacts"] = {}
	return state


## v4 (Milestone 5): offline progression. No pending offline summary yet; the
## offline hunt keeps living in `farming`.
static func v3_to_v4(state: Dictionary) -> Dictionary:
	state["offline"] = {"pending": []}
	return state


## v5 (Milestone 6): quests, contracts, dungeon run, unlock tokens. Quests
## restart from the beginning: main_01 is active, or already handed in (no
## reward) when the player has been to the Lantern Mire, which it now unlocks;
## the same for main_02 and the Watch Ruins. A character at level 6 or more
## keeps artifact slot 1 (it now opens with the clockmaker's quest). Contracts
## roll at the first load.
static func v4_to_v5(state: Dictionary) -> Dictionary:
	var progress: Dictionary = state["progress"]
	var visited: Array = state["world"]["discovered_locations"]
	var quests := {}
	var steps := [
		["quest.main_01", "location.lantern_mire"], ["quest.main_02", "location.watch_ruins"]
	]
	for i in steps.size():
		var done: bool = visited.has(steps[i][1])
		if done or i == 0:
			quests[steps[i][0]] = {
				"state": "turned_in" if done else "active", "step": 1, "counts": {}, "order": i + 1
			}
		if not done:
			break
	progress["quests"] = quests
	progress["contracts"] = {"day_index": -1, "offers": []}
	progress["dungeon_run"] = {}
	var unlocks := []
	var leader: String = state["party"][0]
	var hero: Dictionary = state["characters"].get(leader, {})
	var worn: Array = hero.get("artifacts", [])
	if int(hero.get("level", 1)) >= 6 or (worn.size() > 0 and str(worn[0]) != ""):
		unlocks.append("artifact_slot_1")
	progress["unlocks"] = unlocks
	return state


## v6 (Milestone 6, tactics): saved tactics per character (deltas from the
## defaults, none yet) and the tips already shown (none: a v5 player sees
## each tip once).
static func v5_to_v6(state: Dictionary) -> Dictionary:
	for id in state.get("characters", {}):
		state["characters"][id]["tactics"] = {}
	state["progress"]["tips_seen"] = []
	return state
