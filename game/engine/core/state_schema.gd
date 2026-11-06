class_name StateSchema
extends RefCounted
## Shape of a game state (save format v3). See docs/ARCHITECTURE.md.

const PARTY_SLOTS := 4
const EQUIPMENT_SLOTS := ["weapon", "head", "chest", "hands", "feet", "amulet"]
const ARTIFACT_SLOTS := 2
const RUNE_TIERS := 5

const ID := {"type": "string", "pattern": Schema.ID_PATTERN}
const UNIX := {"type": "int", "min": 0}
const COUNT := {"type": "int", "min": 0}


static func spec() -> Dictionary:
	var equipment_fields := {}
	for slot in EQUIPMENT_SLOTS:
		equipment_fields[slot] = {"type": "string", "optional": true, "default": ""}
	var character := {
		"type": "dict",
		"fields":
		{
			"level": {"type": "int", "min": 1, "max": 999},
			"xp": COUNT,
			"equipment": {"type": "dict", "fields": equipment_fields},
			"spells": {"type": "dict", "values": {"type": "int", "min": 0}},
			"loadout": {"type": "array", "items": ID, "max": 8},
			"runes":
			{
				"type": "dict",
				"keys": ID,
				"values":
				{
					"type": "array",
					"items":
					{
						"type": "dict",
						"fields": {"id": ID, "tier": {"type": "int", "min": 1, "max": RUNE_TIERS}},
					},
				},
			},
			"artifacts":
			{
				"type": "array",
				"min": ARTIFACT_SLOTS,
				"max": ARTIFACT_SLOTS,
				"items": {"type": "string"},
			},
		},
	}
	var item_instance := {
		"type": "dict",
		"fields":
		{
			"uid": {"type": "string", "min": 1},
			"item_id": ID,
			"rarity":
			{"type": "string", "enum": ["common", "uncommon", "rare", "epic", "legendary"]},
			"item_level": {"type": "int", "min": 1},
			"affixes":
			{
				"type": "array",
				"items": {"type": "dict", "fields": {"id": ID, "value": {"type": "number"}}},
			},
			"legendary": {"type": "string"},
			"enhance": {"type": "int", "min": 0},
			"enhance_attempts": COUNT,
			"pity": COUNT,
		},
	}
	return {
		"type": "dict",
		"fields":
		{
			"meta":
			{
				"type": "dict",
				"fields":
				{
					"seed": {"type": "int", "min": 0, "max": 2147483647},
					"created_at": UNIX,
					"last_active_at": UNIX,
					"play_time": {"type": "number", "min": 0},
				},
			},
			"party":
			{
				"type": "array",
				"min": PARTY_SLOTS,
				"max": PARTY_SLOTS,
				"items": {"type": "string"},
			},
			"characters": {"type": "dict", "keys": ID, "values": character},
			"wallet":
			{
				"type": "dict",
				"fields": {"gold": COUNT, "materials": {"type": "dict", "values": COUNT}},
			},
			"inventory": {"type": "array", "items": item_instance},
			"runes":
			{
				"type": "dict",
				"keys": ID,
				"values": {"type": "array", "min": RUNE_TIERS, "max": RUNE_TIERS, "items": COUNT},
			},
			"consumables": {"type": "dict", "keys": ID, "values": COUNT},
			"artifacts": {"type": "dict", "keys": ID, "values": {"type": "int", "min": 1}},
			"world":
			{
				"type": "dict",
				"fields":
				{
					"region_id": ID,
					"location_id": ID,
					"unlocked_regions": {"type": "array", "items": ID},
					"discovered_locations": {"type": "array", "items": ID},
					"revealed_locations": {"type": "array", "items": ID},
					"spawn": {"type": "string", "min": 1},
				},
			},
			"progress":
			{
				"type": "dict",
				"fields":
				{
					"cleared_encounters": {"type": "dict", "values": COUNT},
					"quests": {"type": "dict", "values": {"type": "dict"}},
					"bestiary": {"type": "dict", "values": COUNT},
					"discoveries": {"type": "array", "items": ID},
				},
			},
			"farming": {"type": "string"},
			"rng": {"type": "dict", "values": COUNT},
		},
	}


## Validates and normalizes a state. Returns Schema.validate()'s result, plus
## party-specific checks (a character in the party must exist in characters).
static func validate(state: Variant) -> Dictionary:
	var result := Schema.validate(state, spec())
	if result["errors"].is_empty():
		var value: Dictionary = result["value"]
		var errors: PackedStringArray = result["errors"]
		for i in PARTY_SLOTS:
			var member: String = value["party"][i]
			if member != "" and not value["characters"].has(member):
				errors.append("$.party[%d]: '%s' is not in characters" % [i, member])
		result["errors"] = errors
	return result
