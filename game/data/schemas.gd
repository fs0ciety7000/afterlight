class_name ContentSchemas
extends RefCounted
## Content entity specs, as defined in docs/CONTENT_PIPELINE.md §5.
## Structural rules live here; cross-entity rules in ContentRules.

const SCHEMA_VERSION := 1
const ELEMENTS := ["arcane", "fire", "frost", "lightning"]
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const SLOTS := ["weapon", "head", "chest", "hands", "feet", "amulet"]
const STATS := [
	"max_hp",
	"max_mana",
	"mana_regen",
	"power",
	"defense",
	"crit_chance",
	"crit_damage",
	"haste",
	"damage_bonus",
	"element_bonus_arcane",
	"element_bonus_fire",
	"element_bonus_frost",
	"element_bonus_lightning",
	"resist_all",
	"shield_bonus",
	"gold_find",
	"move_speed",
]
## Per-spell modifiers a modifier rune grants (combat spell_mods keys).
const RUNE_MODS := [
	"crit_bonus", "cost_reduction", "cooldown_reduction", "echo_chance", "damage_bonus"
]
## Artifact effects: a STATS id is a flat stat bonus; the others are rules.
## One-shot clips a spell or ability may ask its caster to play (optional `anim` field; default: the
## caster's generic "cast" or "attack" clip). Models without the clip fall back to the generic one.
const ANIM_CLIPS := ["attack", "cast", "cast_beam", "cast_volley", "cast_guard", "cast_ultimate"]
const ARTIFACT_EFFECTS := ["offline_efficiency", "low_hp_heal", "gold_find", "active_bonus_damage"]
## Quest objective events (CONTENT_PIPELINE §5.4) and the entity types each
## one may target (rule V15).
const OBJECTIVE_TARGETS := {
	"EnemyDefeated": ["enemy"],
	"EncounterCompleted": ["encounter", "location"],
	"TalkedTo": ["npc"],
	"DiscoveryFound": ["discovery"],
	"ItemCollected": ["material", "artifact"],
	"ItemDelivered": ["material"],
	"LocationVisited": ["location", "dungeon"],
	"CastInterrupted": ["character"],
	"StatusApplied": ["status"],
}
const QUEST_STATES := ["available", "active", "completed", "turned_in", "not_started"]

## File name (without .json) -> declared type, and the entity types its
## entries may hold (decided by each id's prefix).
const FILES := {
	"start": ["start", ["start"]],
	"characters": ["character", ["character"]],
	"spells": ["spell", ["spell", "passive"]],
	"abilities": ["ability", ["ability"]],
	"statuses": ["status", ["status"]],
	"enemies": ["enemy", ["enemy"]],
	"ai_profiles": ["ai_profile", ["ai_profile"]],
	"equipment": ["item", ["item"]],
	"affixes": ["affix", ["affix"]],
	"legendaries": ["legendary", ["legendary"]],
	"runes": ["rune", ["rune"]],
	"artifacts": ["artifact", ["artifact"]],
	"consumables": ["consumable", ["consumable"]],
	"materials": ["material", ["material", "currency"]],
	"regions": ["region", ["region"]],
	"locations": ["location", ["location"]],
	"dungeons": ["dungeon", ["dungeon"]],
	"encounters": ["encounter", ["encounter"]],
	"loot_tables": ["loot_table", ["loot_table"]],
	"quests": ["quest", ["quest"]],
	"npcs": ["npc", ["npc"]],
	"dialogues": ["dialogue", ["dialogue"]],
	"discoveries": ["discovery", ["discovery"]],
	"lore": ["lore", ["lore"]],
	"shops": ["shop", ["shop"]],
	"tactics_presets": ["tactics_preset", ["tactics_preset"]],
	"tips": ["tip", ["tip"]],
}

const PREFIX_TO_TYPE := {
	"start": "start",
	"character": "character",
	"spell": "spell",
	"passive": "passive",
	"ability": "ability",
	"status": "status",
	"enemy": "enemy",
	"ai": "ai_profile",
	"item": "item",
	"affix": "affix",
	"legendary": "legendary",
	"rune": "rune",
	"artifact": "artifact",
	"consumable": "consumable",
	"material": "material",
	"currency": "currency",
	"region": "region",
	"location": "location",
	"dungeon": "dungeon",
	"encounter": "encounter",
	"loot": "loot_table",
	"quest": "quest",
	"npc": "npc",
	"dialogue": "dialogue",
	"discovery": "discovery",
	"lore": "lore",
	"shop": "shop",
	"tactics_preset": "tactics_preset",
	"tip": "tip",
}

## Types whose entries must carry desc_key (§3).
const NEEDS_DESC := ["spell", "passive", "item", "rune", "artifact", "quest", "legendary"]
## When a tip may show (GDD decision 27; TacticsRules.next_tip context).
const TIP_TRIGGERS := ["level_reached", "first_campfire", "boss_cast", "defeat"]
const TIP_DISPLAYS := ["toast", "panel", "banner", "defeat"]
const TIP_ACTIONS := ["apply_preset", "open_tactics", "later", "close"]

const ID_PATTERN := "^[a-z][a-z_]*\\.[a-z0-9_]+$"


static func ref(types: Variant, optional: bool = false) -> Dictionary:
	var spec := {"type": "string", "ref": types}
	if optional:
		spec["optional"] = true
		spec["default"] = ""
	return spec


static func refs(types: Variant, min_items: int = 0) -> Dictionary:
	return {
		"type": "array",
		"items": ref(types),
		"min": min_items,
		"optional": min_items == 0,
		"default": []
	}


static func opt(spec: Dictionary, default_value: Variant = null) -> Dictionary:
	var s := spec.duplicate(true)
	s["optional"] = true
	if default_value != null:
		s["default"] = default_value
	return s


static func num(min_value: float = 0.0, max_value: float = INF) -> Dictionary:
	var s := {"type": "number", "min": min_value}
	if max_value != INF:
		s["max"] = max_value
	return s


static func pos_int(min_value: int = 1) -> Dictionary:
	return {"type": "int", "min": min_value}


static func enum_of(values: Array) -> Dictionary:
	return {"type": "string", "enum": values}


static func stat_map() -> Dictionary:
	return {"type": "dict", "keys": enum_of(STATS), "values": {"type": "number"}}


static func condition() -> Dictionary:
	# Checked in depth by ContentRules (one of start, quest_completed, ...).
	return {"type": "dict"}


static func effect() -> Dictionary:
	return {
		"type": "dict",
		"fields":
		{
			"type":
			enum_of(
				[
					"damage",
					"heal",
					"shield",
					"apply_status",
					"summon",
					"interrupt",
					"cleanse",
					"damage_reduction",
					"restore_mana",
				]
			),
			"coeff": opt(num()),
			"hits": opt(pos_int()),
			"radius_m": opt(num()),
			"status": ref("status", true),
			"chance": opt(num(0.0, 1.0)),
			"duration_s": opt(num()),
			"summon": ref("enemy", true),
			"count": opt(pos_int()),
			"level_offset": opt({"type": "int"}),
		},
	}


static func _spell_fields(kinds: Array) -> Dictionary:
	return {
		"kind": enum_of(kinds),
		"element": opt(enum_of(ELEMENTS), ""),
		"mana_cost": opt(num()),
		"cooldown_s": opt(num()),
		"interval_s": opt(num(0.001)),
		"cast_s": opt(num()),
		"channel_s": opt(num()),
		"telegraph":
		opt(
			{
				"type": "dict",
				"fields":
				{
					"shape": enum_of(["circle", "line", "cone"]),
					"size_m": num(0.001),
					"duration_s": num(),
				},
			}
		),
		"interruptible": opt({"type": "bool"}, false),
		"interrupts": opt({"type": "bool"}, false),
		"ignores_gcd": opt({"type": "bool"}, false),
		"range_m": opt(num(0.001)),
		"targeting":
		opt(
			enum_of(["focus", "nearest", "distributed", "random_weighted_focus", "self", "area"]),
			""
		),
		"effects": {"type": "array", "min": 1, "items": effect()},
		"ult_charge_cost": opt(pos_int()),
		"ranks":
		opt(
			{
				"type": "array",
				"min": 5,
				"max": 5,
				"items":
				{
					"type": "dict",
					"fields": {"rank": pos_int(), "modifier": opt({"type": "string"}, "")}
				},
			}
		),
		"trigger": opt({"type": "dict"}),
		"vfx": opt({"type": "string"}, ""),
		"sfx": opt({"type": "string"}, ""),
		"icon": opt({"type": "string"}, ""),
		"anim": opt(enum_of(ANIM_CLIPS), ""),
	}


static func fields_for(type_name: String) -> Dictionary:
	match type_name:
		"start":
			return {
				"party": {"type": "array", "min": 1, "max": 4, "items": ref("character")},
				"region": ref("region"),
				"location": ref("location"),
				"gold": pos_int(0),
				"materials": opt({"type": "dict", "values": pos_int(0)}, {}),
			}
		"character":
			return {
				"playable": {"type": "bool"},
				"role": opt(enum_of(["caster", "tank", "fighter", "support"]), ""),
				"base_stats": opt(stat_map(), {}),
				"growth": opt(stat_map(), {}),
				"auto_attack": ref("spell", true),
				"spells": refs("spell"),
				"ultimate": ref("spell", true),
				"passive": ref("passive", true),
				"unlocks":
				opt(
					{
						"type": "array",
						"items":
						{
							"type": "dict",
							"fields":
							{
								"level": pos_int(),
								"ref": {"type": "string", "ref": ["spell", "passive", "item"]}
							}
						}
					},
					[]
				),
				"model": opt({"type": "string"}, ""),
				"portrait": opt({"type": "string"}, ""),
			}
		"spell":
			return _spell_fields(["auto", "active", "ultimate", "passive"])
		"ability":
			return _spell_fields(["attack", "skill", "phase"])
		"passive":
			return {
				"effects": {"type": "array", "min": 1, "items": {"type": "dict"}},
				"icon": opt({"type": "string"}, "")
			}
		"status":
			return {
				"kind": enum_of(["buff", "debuff", "dot", "cc", "shield"]),
				"duration_s": num(0.001),
				"max_stacks": pos_int(),
				"stack_rule": enum_of(["refresh", "add_refresh", "keep_highest", "none"]),
				"tick_s": opt(num(0.001)),
				"modifiers":
				opt(
					{
						"type": "array",
						"items":
						{
							"type": "dict",
							"fields":
							{
								"stat": {"type": "string"},
								"kind": enum_of(["flat", "percent"]),
								"value": {"type": "number"}
							}
						}
					},
					[]
				),
				"boss_duration_mult": opt(num()),
				"immunity_after_s": opt(num()),
				"converts_to":
				opt({"type": "dict", "fields": {"at_stacks": pos_int(), "status": ref("status")}}),
				"icon": {"type": "string", "min": 1},
			}
		"enemy":
			var affinity := enum_of(["weak", "neutral", "resist"])
			return {
				"archetype": enum_of(["rusher", "caster", "bulwark", "elite", "boss"]),
				"family": enum_of(["beast", "spirit", "construct", "demon"]),
				"stats_l1":
				{
					"type": "dict",
					"fields":
					{
						"hp": num(1),
						"power": num(),
						"def_ratio": num(0, 1),
						"barrier_ratio": num(0, 1),
						"move_speed": num(),
						"aggro_m": num(),
					},
				},
				"affinities":
				{
					"type": "dict",
					"fields":
					{"arcane": affinity, "fire": affinity, "frost": affinity, "lightning": affinity}
				},
				"attack": ref("ability"),
				"abilities": refs("ability"),
				"phases":
				opt(
					{
						"type": "array",
						"items":
						{
							"type": "dict",
							"fields":
							{
								"id": {"type": "string", "min": 1},
								"hp_threshold": num(0, 1),
								"abilities": refs("ability"),
								"on_enter": opt({"type": "array", "items": effect()}, []),
								"haste": opt(num()),
							},
						},
					},
					[]
				),
				"enrage_s": opt(num(0.001)),
				"ai_profile": ref("ai_profile"),
				"xp_mult": num(0.001),
				"gold_mult": num(0.001),
				"cc_resist": opt(num(0, 1)),
				"model": {"type": "string"},
				"scale": opt(num(0.001)),
				"bestiary_thresholds": opt({"type": "array", "items": pos_int()}, [1, 5, 25]),
			}
		"ai_profile":
			return {
				"states":
				{
					"type": "array",
					"min": 1,
					"items":
					enum_of(
						["idle", "patrol", "aggro", "approach", "attack", "ability", "kite", "dead"]
					)
				},
				"target_rule": enum_of(["nearest", "lowest_hp", "furthest", "front_row"]),
				"keep_distance_m": opt(num()),
				"flee_below_m": opt(num()),
				"ability_priority": refs("ability"),
				"repath_s": opt(num(0.001), 0.5),
			}
		"item":
			return {
				"slot": enum_of(SLOTS),
				"implicit":
				{
					"type": "array",
					"items":
					{"type": "dict", "fields": {"stat": enum_of(STATS), "base": {"type": "number"}}}
				},
				"min_ilvl": pos_int(),
				"affix_pools": refs("affix"),
				"icon": opt({"type": "string"}, ""),
				"model": opt({"type": "string"}, ""),
			}
		"affix":
			return {
				"stat": enum_of(STATS),
				"scaling": enum_of(["flat", "pct"]),
				"min": {"type": "number"},
				"max": {"type": "number"},
				"slots": {"type": "array", "min": 1, "items": enum_of(SLOTS)},
				"weight": num(0.000001),
				"group": {"type": "string", "min": 1},
				"layer": opt(enum_of(["flat", "percent"]), "flat"),
			}
		"legendary":
			return {"slot": enum_of(SLOTS), "effect": {"type": "any"}, "weight": num(0.000001)}
		"rune":
			return {
				"group": enum_of(["conversion", "modifier"]),
				"element": opt(enum_of(ELEMENTS), ""),
				"values_by_tier": {"type": "array", "items": {"type": "number"}},
				"stat": opt(enum_of(RUNE_MODS), ""),
				"weight": num(0.000001),
				"icon": opt({"type": "string"}, ""),
			}
		"artifact":
			return {
				"max_level": pos_int(),
				"effect_type": enum_of(ARTIFACT_EFFECTS),
				"values_by_level": {"type": "array", "items": {"type": "number"}},
				"unlock": condition(),
				"icon": opt({"type": "string"}, ""),
			}
		"consumable":
			return {
				"effect": effect(),
				"carry_max": pos_int(),
				"shared_cooldown_group": {"type": "string", "min": 1},
				"price_base": pos_int(0),
			}
		"material", "currency":
			return {
				"stack_max": opt(pos_int()),
				"rarity": opt(enum_of(RARITIES), "common"),
				"icon": {"type": "string", "min": 1}
			}
		"region":
			return {
				"level_range": {"type": "array", "min": 2, "max": 2, "items": pos_int()},
				"locations": refs("location", 1),
				"hub": ref("location"),
				"map_texture": {"type": "string", "min": 1},
				"unlock": condition(),
			}
		"location":
			return {
				"region": ref("region"),
				"kind": enum_of(["hub", "field", "dungeon_entrance"]),
				"level": opt(pos_int()),
				"scene": {"type": "string", "min": 1},
				"map_pos": {"type": "array", "min": 2, "max": 2, "items": num(0, 1)},
				"encounters": refs("encounter"),
				"discoveries": refs("discovery"),
				"exits":
				opt(
					{
						"type": "array",
						"items":
						{
							"type": "dict",
							"fields": {"to": ref("location"), "spawn": {"type": "string"}}
						}
					},
					[]
				),
				"unlock": condition(),
				"fog_reveal": refs(["location", "dungeon"]),
				"npcs": refs("npc"),
			}
		"dungeon":
			return {
				"location": ref("location"),
				"level": pos_int(),
				"scene": {"type": "string", "min": 1},
				"map_pos": {"type": "array", "min": 2, "max": 2, "items": num(0, 1)},
				"rooms":
				{
					"type": "array",
					"min": 1,
					"items":
					{
						"type": "dict",
						"fields":
						{
							"id": {"type": "string", "min": 1},
							"kind": enum_of(["encounter", "rest", "elite", "boss", "checkpoint"]),
							"encounter": ref("encounter", true),
							"heal_pct": opt(num(0, 1)),
						},
					},
				},
				"unlock": condition(),
			}
		"encounter":
			return {
				"location": ref("location"),
				"kind": enum_of(["normal", "elite", "boss"]),
				"level": pos_int(),
				"enemies":
				{
					"type": "array",
					"min": 1,
					"items":
					{
						"type": "dict",
						"fields":
						{
							"enemy": ref("enemy"),
							"count": pos_int(),
							"level_offset": opt({"type": "int"}, 0)
						}
					}
				},
				"loot_table": ref("loot_table"),
				"offline_eligible": {"type": "bool"},
				"speed_cap": {"type": "int", "enum": [1, 2, 4]},
				"first_clear_rewards":
				opt(
					{
						"type": "dict",
						"fields":
						{
							"materials": opt({"type": "dict", "values": pos_int()}, {}),
							"items":
							opt(
								{
									"type": "array",
									"items":
									{
										"type": "dict",
										"fields":
										{"base": ref("item"), "rarity": enum_of(RARITIES)},
									},
								},
								[]
							),
						}
					},
					{}
				),
				"anchor": {"type": "string", "min": 1},
				"respawn_s": opt(num(), 60.0),
				"arena_center": opt(enum_of(["contact", "anchor"]), "contact"),
			}
		"loot_table":
			return {
				"rarity_profile": enum_of(["normal", "elite", "boss", "boss_first_kill", "chest"]),
				"entries":
				{
					"type": "array",
					"min": 1,
					"items":
					{
						"type": "dict",
						"fields":
						{
							"kind":
							enum_of(["gold", "material", "item", "rune", "artifact", "consumable"]),
							"ref":
							{
								"type": "string",
								"ref":
								["material", "currency", "item", "rune", "artifact", "consumable"],
								"optional": true,
								"default": ""
							},
							"chance": num(0, 1),
							"qty": {"type": "array", "min": 2, "max": 2, "items": pos_int(0)},
							"per": enum_of(["enemy", "encounter"]),
							"when": opt(enum_of(["always", "first_clear", "repeat"]), "always"),
						},
					},
				},
				"guaranteed": opt({"type": "array"}, []),
			}
		"discovery":
			return {
				"location": ref(["location", "dungeon"]),
				"kind": enum_of(["vista", "lore", "chest", "memorial", "pickup"]),
				"trigger": enum_of(["zone", "interact", "interact_hold"]),
				"level": pos_int(),
				"reward":
				{
					"type": "dict",
					"fields":
					{
						"xp": opt({"type": "bool"}, false),
						"materials": opt({"type": "dict", "values": pos_int()}, {}),
						"artifacts": refs("artifact"),
						"loot_table": ref("loot_table", true),
					},
				},
				"reveals": refs(["location", "dungeon"]),
				"anchor": {"type": "string", "min": 1},
				"map_pos": opt({"type": "array", "min": 2, "max": 2, "items": num(0, 1)}, []),
				"fog_radius": opt(num(0, 1), 0.0),
				"counts_for_location": opt({"type": "bool"}, true),
				"available_if": opt(condition(), {}),
				"room": opt({"type": "string"}, ""),
			}
		"quest":
			return {
				"kind": enum_of(["main", "side", "daily"]),
				"level": opt(pos_int()),
				"giver": ref("npc", true),
				"active_at_start": opt({"type": "bool"}, false),
				"prerequisites": opt({"type": "array", "items": condition()}, []),
				"tier": opt(enum_of(["S", "M", "L"]), ""),
				"weight": opt(num(0.000001)),
				"objectives":
				{
					"type": "array",
					"min": 1,
					"items":
					{
						"type": "dict",
						"fields":
						{
							"id": {"type": "string", "pattern": "^[a-z0-9_]+$"},
							"step": opt(pos_int(), 1),
							"event": enum_of(OBJECTIVE_TARGETS.keys()),
							"target":
							{
								"type": "string",
								"ref":
								[
									"enemy",
									"encounter",
									"location",
									"dungeon",
									"npc",
									"discovery",
									"material",
									"artifact",
									"character",
									"status",
								]
							},
							"source": ref("character", true),
							"count": pos_int(),
						},
					},
				},
				"rewards":
				{
					"type": "dict",
					"fields":
					{
						"xp_factor": opt(num()),
						"gold": opt(pos_int(0), 0),
						"materials": opt({"type": "dict", "values": pos_int()}, {}),
						"runes":
						opt(
							{
								"type": "array",
								"items":
								{
									"type": "dict",
									"fields":
									{
										"id": ref("rune"),
										"tier": {"type": "int", "min": 1, "max": 5},
									}
								}
							},
							[]
						),
						"artifacts": refs("artifact"),
						"unlocks":
						opt({"type": "array", "items": {"type": "string", "min": 1}}, []),
						"memory": opt({"type": "bool"}, false),
					},
				},
				"next": ref("quest", true),
			}
		"npc":
			return {
				"location": ref("location"),
				"role": opt(enum_of(["smith", "runecarver", "merchant", "quest", "board"]), ""),
				"anchor": {"type": "string", "min": 1},
				"dialogues":
				opt(
					{
						"type": "array",
						"items":
						{
							"type": "dict",
							"fields":
							{
								"dialogue": ref("dialogue"),
								"condition": opt(condition(), {}),
								"offers": ref("quest", true),
								"turns_in": ref("quest", true),
							},
						},
					},
					[]
				),
				"model": {"type": "string", "min": 1},
			}
		"dialogue":
			return {
				"lines":
				{
					"type": "array",
					"min": 1,
					"items":
					{
						"type": "dict",
						"fields":
						{
							"speaker": {"type": "string", "ref": ["npc", "character", "enemy"]},
							"key_suffix": {"type": "string", "min": 1},
							"condition": opt(condition()),
						},
					},
				},
				"choices": opt({"type": "array", "max": 3, "items": {"type": "dict"}}, []),
			}
		"lore":
			return {}
		"shop":
			return {"location": ref("location"), "stock": refs("consumable", 1)}
		"tactics_preset":
			# `tactics`: partial tactics, same shape as CombatTactics.build overrides
			# (checked against the character's spells by ContentRules).
			return {"character": ref("character"), "tactics": {"type": "dict"}}
		"tip":
			return {
				"trigger": enum_of(TIP_TRIGGERS),
				"display": enum_of(TIP_DISPLAYS),
				"level": opt(pos_int(), 0),
				"dungeon": ref("dungeon", true),
				"encounter": ref("encounter", true),
				"abilities": refs("ability"),
				"repeat": opt({"type": "bool"}, false),
				"duration_s": opt(num(), 0.0),
				"preset": ref("tactics_preset", true),
				"actions": opt({"type": "array", "items": enum_of(TIP_ACTIONS)}, []),
			}
	return {}


## Full spec of one entity: common fields (§5) plus the type's own.
static func entity_spec(type_name: String) -> Dictionary:
	var fields := {
		"id": {"type": "string", "pattern": ID_PATTERN, "max": 48},
		"origin": enum_of(["canon", "original"]),
		"name_key": {"type": "string", "min": 1},
		"desc_key": opt({"type": "string"}, ""),
		"canon_note": opt({"type": "string"}, ""),
		"canon_refs": opt({"type": "array", "items": {"type": "string"}}, []),
		"tags": opt({"type": "array", "items": {"type": "string"}}, []),
		"deprecated": opt({"type": "bool"}, false),
		"notes": opt({"type": "string"}, ""),
	}
	fields.merge(fields_for(type_name))
	return {"type": "dict", "fields": fields}


static func type_of_id(id: String) -> String:
	return PREFIX_TO_TYPE.get(id.get_slice(".", 0), "")
