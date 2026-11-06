class_name StoryFixtures
extends RefCounted
## Helpers for the milestone 6 tests: a new game on the shipped content and
## hand-made encounter_completed events (CombatSim's payload).

const FERN := "character.fern"
const NOW := 1_800_000_000


static func content() -> Dictionary:
	return CombatBench.content()


## New game on the shipped start (main_01 active), Fern at `level`.
static func state(level: int = 1, seed_value: int = 77) -> Dictionary:
	var c := content()
	var s := NewGame.create(c["start.default"], seed_value, NOW, c)
	s["characters"][FERN]["level"] = level
	return s


## A fight as the sim reports it. `defeated` = {enemy id: n}; by default every
## enemy of the encounter died (victory) or none did (defeat).
static func fight(
	encounter_id: String,
	victory: bool = true,
	defeated: Variant = null,
	materials: Dictionary = {},
	extra_tally: Dictionary = {}
) -> Dictionary:
	var kills := {}
	if defeated != null:
		kills = defeated
	elif victory:
		for group in content()[encounter_id]["enemies"]:
			kills[group["enemy"]] = int(kills.get(group["enemy"], 0)) + int(group["count"])
	var tally := {"defeated": kills, "interrupts": {}, "statuses": {}}
	tally.merge(extra_tally, true)
	return {
		"type": "encounter_completed",
		"encounter": encounter_id,
		"result": "victory" if victory else "defeat",
		"duration_s": 20.0,
		"ticks": 400,
		"rewards":
		{
			"xp": 0,
			"gold": 0,
			"materials": materials,
			"items": [],
			"runes": [],
			"artifacts": [],
			"consumables": {}
		},
		"consumables_used": {},
		"first_clear": false,
		"last_hit": {},
		"location": content()[encounter_id]["location"],
		"tally": tally,
		"leader": {"hp_pct": 0.6, "mana_pct": 0.4, "ult_charge": 30.0},
	}


## Applies a fight like GameState does; returns the new state.
static func play(s: Dictionary, completed: Dictionary) -> Dictionary:
	return StoryEvents.apply_fight(s, completed, content())["state"]


## Plays an NPC's current dialogue to its end; returns the finish result.
static func talk(s: Dictionary, npc_id: String) -> Dictionary:
	var pick := NpcRules.select(s, npc_id, content())
	return NpcRules.finish(s, npc_id, pick["dialogue"], content())


## Marks a quest turned in without playing it.
static func turned_in(s: Dictionary, quest_id: String) -> void:
	s["progress"]["quests"][quest_id] = {"state": "turned_in", "step": 1, "counts": {}, "order": 0}


## JSON round trip through the save schema (a reload).
static func reloaded(s: Dictionary) -> Dictionary:
	var text := SaveCodec.encode(s, NOW)
	var r := SaveCodec.decode(text, SaveMigrations.all())
	assert(r["ok"], "%s %s" % [r["error"], r["detail"]])
	return r["state"]
