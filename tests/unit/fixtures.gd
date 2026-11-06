class_name Fixtures
extends RefCounted
## Shared test data.

const START := {
	"party": ["character.fern", "", "", ""],
	"region": "region.test_vale",
	"location": "location.test_village",
	"gold": 100,
	"materials": {"material.mana_dust": 3},
}


static func new_state(seed_value: int = 1234, now: int = 1_800_000_000) -> Dictionary:
	return NewGame.create(START, seed_value, now)
