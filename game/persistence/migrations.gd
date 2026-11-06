class_name SaveMigrations
extends RefCounted
## Save format migrations: version n -> n + 1. Never edit a released step;
## add a new one and bump SaveCodec.CURRENT_VERSION.
##
## Each step gets a test in tests/unit/persistence/test_migrations.gd.


static func all() -> Dictionary:
	return {1: v1_to_v2, 2: v2_to_v3, 3: v3_to_v4}


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
