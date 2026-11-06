class_name PartyBuild
extends RefCounted
## Turns the saved state of a character into a CombatSim party entry:
## equipment and artifact modifiers (flat / percent), spell ranks, rune
## modifiers per spell and carried consumables (docs/ARCHITECTURE.md,
## "Piloter la simulation").


static func entry(
	state: Dictionary, character: String, content: Dictionary, slot: int = 3
) -> Dictionary:
	var hero: Dictionary = state["characters"][character]
	var b := Equipment.bonuses(state, character, content)
	return {
		"character": character,
		"level": int(hero["level"]),
		"slot": slot,
		"flat": b["flat"],
		"percent": b["percent"],
		"spell_ranks": hero.get("spells", {}).duplicate(),
		"spell_mods": Grimoire.spell_mods(state, character, content),
	}


## Setup fields of CombatSim.create for the saved party (leader only in the
## vertical slice): {party: [entry], consumables: {id: n}}.
static func setup(state: Dictionary, content: Dictionary) -> Dictionary:
	var leader: String = state["party"][0]
	return {
		"party": [entry(state, leader, content)],
		"consumables": state.get("consumables", {}).duplicate(),
	}
