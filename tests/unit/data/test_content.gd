extends TestCase
## Content validation: the shipped data must pass, and each rule of
## docs/CONTENT_PIPELINE.md §8 must reject a minimal broken example.

const ROOTS := ["res://game/data/canon", "res://game/data/original"]
const TMP := "user://test_content"


func test_shipped_content_is_valid() -> void:
	var r := ContentLoader.load_roots(ROOTS)
	assert_eq(r["errors"].size(), 0, "\n".join(r["errors"]))
	assert_eq(r["by_id"]["character.fern"]["origin"], "canon", "Fern is canon")
	assert_eq(r["by_id"]["spell.zoltraak"]["origin"], "canon", "Zoltraak is canon")
	assert_eq(r["by_id"]["spell.mana_volley"]["origin"], "original", "volley is original")


func test_shipped_start_builds_a_valid_new_game() -> void:
	var r := ContentLoader.load_roots(ROOTS)
	var state := NewGame.create(r["by_type"]["start"][0], 1, 1)
	assert_eq(StateSchema.validate(state)["errors"].size(), 0, "valid state")


# --- Minimal valid world, then one defect per rule ----------------------------


func _entry(id: String, fields: Dictionary, origin: String = "original") -> Dictionary:
	var e := {"id": id, "origin": origin, "name_key": id + ".name"}
	if origin == "canon":
		e["canon_note"] = "test"
	e.merge(fields)
	return e


func _base() -> Dictionary:
	var spell := func(id: String, kind: String, extra: Dictionary) -> Dictionary:
		var f := {
			"desc_key": id + ".desc",
			"kind": kind,
			"element": "arcane",
			"targeting": "focus",
			"range_m": 10,
			"effects": [{"type": "damage", "coeff": 1.0}],
		}
		f.merge(extra)
		return _entry(id, f)
	var ranks := [{"rank": 1}, {"rank": 2}, {"rank": 3}, {"rank": 4}, {"rank": 5}]
	return {
		"canon/characters.json":
		[
			"character",
			[
				_entry(
					"character.a",
					{
						"playable": true,
						"role": "caster",
						"base_stats": {"power": 1},
						"growth": {"power": 1},
						"auto_attack": "spell.auto",
						"spells": ["spell.act"],
						"ultimate": "spell.ult",
						"model": "res://m.glb",
						"portrait": "res://p.png",
					},
					"canon"
				)
			]
		],
		"original/spells.json":
		[
			"spell",
			[
				spell.call("spell.auto", "auto", {"interval_s": 1.0}),
				spell.call(
					"spell.act", "active", {"mana_cost": 10, "cooldown_s": 5, "ranks": ranks}
				),
				spell.call(
					"spell.ult",
					"ultimate",
					{"cooldown_s": 0, "ult_charge_cost": 100, "ranks": ranks}
				),
			]
		],
		"original/start.json":
		[
			"start",
			[
				_entry(
					"start.default",
					{
						"party": ["character.a"],
						"region": "region.r",
						"location": "location.l",
						"gold": 0,
					}
				)
			]
		],
		"original/regions.json":
		[
			"region",
			[
				_entry(
					"region.r",
					{
						"level_range": [1, 5],
						"locations": ["location.l"],
						"hub": "location.l",
						"map_texture": "res://map.png",
						"unlock": {"start": true},
					}
				)
			]
		],
		"original/locations.json":
		[
			"location",
			[
				_entry(
					"location.l",
					{
						"region": "region.r",
						"kind": "hub",
						"scene": "res://l.tscn",
						"map_pos": [0.5, 0.5],
						"unlock": {"start": true},
					}
				)
			]
		],
	}


func _errors(files: Dictionary, raw: Dictionary = {}) -> String:
	var root := "%s/%d" % [TMP, Time.get_ticks_usec()]
	var keys := PackedStringArray(["keys,fr"])
	for path in files:
		var doc := {"schema_version": 1, "type": files[path][0], "entries": files[path][1]}
		_write(root.path_join(path), JSON.stringify(doc))
		for e in files[path][1]:
			keys.append("%s.name,x" % e["id"])
			keys.append("%s.desc,x" % e["id"])
	for path in raw:
		_write(root.path_join(path), raw[path])
	_write(root.path_join("strings.csv"), "\n".join(keys))
	var r := ContentLoader.load_roots(
		[root + "/canon", root + "/original"], root.path_join("strings.csv")
	)
	return "\n".join(r["errors"])


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _expect(files: Dictionary, rule: String, fragment: String, raw: Dictionary = {}) -> void:
	var e := _errors(files, raw)
	assert_true(
		e.contains(rule + " ") and e.contains(fragment), "%s '%s' in:\n%s" % [rule, fragment, e]
	)


func test_minimal_world_is_valid() -> void:
	assert_eq(_errors(_base()), "", "valid")


func test_v1_file_type_must_match_file_name() -> void:
	var w := _base()
	w["original/regions.json"][0] = "location"
	_expect(w, "V1", "type must be 'region'")
	_expect(_base(), "V1", "invalid JSON", {"original/enemies.json": "{oops"})


func test_v2_prefix_must_match_the_file() -> void:
	var w := _base()
	w["original/regions.json"][1][0]["id"] = "spell.r"
	_expect(w, "V2", "prefix 'spell' is not allowed")
	w = _base()
	w["original/regions.json"][1][0]["id"] = "Region.R"
	_expect(w, "V2", "id must match")


func test_v3_duplicate_ids_fail_across_files() -> void:
	var w := _base()
	w["canon/spells.json"] = [
		"spell", [_entry("spell.auto", w["original/spells.json"][1][0], "canon")]
	]
	w["canon/spells.json"][1][0]["origin"] = "canon"
	_expect(w, "V3", "duplicate id")


func test_v4_origin_must_match_the_folder() -> void:
	var w := _base()
	w["original/characters.json"] = w["canon/characters.json"]
	w.erase("canon/characters.json")
	_expect(w, "V4", "origin must be 'original'")


func test_v5_canon_needs_a_note() -> void:
	var w := _base()
	w["canon/characters.json"][1][0].erase("canon_note")
	_expect(w, "V5", "canon_note")


func test_v6_unknown_or_wrong_type_reference() -> void:
	var w := _base()
	w["original/start.json"][1][0]["location"] = "location.nowhere"
	_expect(w, "V6", "unknown location 'location.nowhere'")
	w = _base()
	w["canon/characters.json"][1][0]["auto_attack"] = "region.r"
	_expect(w, "V6", "is a region, expected spell")


func test_v7_wrong_enum_and_missing_field() -> void:
	var w := _base()
	w["original/spells.json"][1][0]["element"] = "water"
	_expect(w, "V7", "'water' not in")
	w = _base()
	w["original/locations.json"][1][0].erase("scene")
	_expect(w, "V7", "missing field 'scene'")


func test_v8_out_of_range_numbers() -> void:
	var w := _base()
	w["original/spells.json"][1][1]["mana_cost"] = -1
	_expect(w, "V8", "must be >= 0")


func test_v9_translation_keys() -> void:
	var w := _base()
	w["original/regions.json"][1][0]["name_key"] = "region_name"
	_expect(w, "V9", "name_key must be 'region.r.name'")
	w = _base()
	w["original/spells.json"][1][1].erase("desc_key")
	_expect(w, "V9", "desc_key is required")


func test_v10_v11_v12_v13_v14_v17_combat_and_world_rules() -> void:
	var w := _base()
	var attack := _entry(
		"ability.hit",
		{
			"kind": "attack",
			"element": "arcane",
			"targeting": "nearest",
			"range_m": 2,
			"interval_s": 1.0,
			"effects": [{"type": "damage", "coeff": 2.0}],
		}
	)
	w["original/abilities.json"] = ["ability", [attack]]
	_expect(w, "V13", "needs a telegraph")
	attack["telegraph"] = {"shape": "circle", "size_m": 3, "duration_s": 0.3}
	_expect(w, "V13", "telegraph shorter")

	w = _base()
	w["original/loot_tables.json"] = [
		"loot_table",
		[
			_entry(
				"loot.t",
				{
					"rarity_profile": "normal",
					"entries": [{"kind": "gold", "chance": 0, "qty": [1, 2], "per": "enemy"}],
				}
			)
		]
	]
	_expect(w, "V14", "sum of chances is zero")

	w = _base()
	w["original/runes.json"] = [
		"rune",
		[
			_entry(
				"rune.x",
				{
					"desc_key": "rune.x.desc",
					"group": "modifier",
					"stat": "damage_bonus",
					"values_by_tier": [1, 2, 2, 3, 4],
					"weight": 1,
				}
			)
		]
	]
	_expect(w, "V17", "strictly increasing")


func test_milestone_4_item_rune_artifact_and_shop_rules() -> void:
	var w := _base()
	w["original/loot_tables.json"] = [
		"loot_table",
		[
			_entry(
				"loot.t",
				{
					"rarity_profile": "normal",
					"entries":
					[
						{"kind": "item", "chance": 0.25, "qty": [1, 1], "per": "encounter"},
						{"kind": "rune", "chance": 0.1, "qty": [1, 1], "per": "encounter"},
					],
				}
			)
		]
	]
	assert_eq(_errors(w), "", "items and runes may omit ref (random pick)")
	w["original/loot_tables.json"][1][0]["entries"].append(
		{"kind": "material", "chance": 0.5, "qty": [1, 1], "per": "encounter", "when": "repeat"}
	)
	_expect(w, "V7", "material entries need a ref")

	w = _base()
	w["original/runes.json"] = [
		"rune",
		[
			_entry(
				"rune.x",
				{
					"desc_key": "rune.x.desc",
					"group": "modifier",
					"stat": "power",
					"values_by_tier": [1, 2, 3, 4, 5],
					"weight": 1,
				}
			)
		]
	]
	_expect(w, "V7", "'power' not in")

	w = _base()
	var artifact := {
		"desc_key": "artifact.x.desc",
		"max_level": 2,
		"effect_type": "gold_find",
		"values_by_level": [0.2, 0.1],
		"unlock": {"start": true},
	}
	w["original/artifacts.json"] = ["artifact", [_entry("artifact.x", artifact)]]
	_expect(w, "V8", "values_by_level must be strictly increasing")
	w["original/artifacts.json"][1][0]["effect_type"] = "teleport"
	_expect(w, "V7", "'teleport' not in")

	w = _base()
	w["original/equipment.json"] = [
		"item",
		[
			_entry(
				"item.x",
				{
					"desc_key": "item.x.desc",
					"slot": "feet",
					"implicit": [{"stat": "max_hp", "base": 20}],
					"min_ilvl": 1,
				}
			)
		]
	]
	_expect(w, "V7", "no affix can roll on slot feet")

	w = _base()
	w["original/shops.json"] = [
		"shop", [_entry("shop.s", {"location": "location.l", "stock": ["region.r"]})]
	]
	_expect(w, "V6", "is a region, expected consumable")


func test_shipped_item_bases_match_slot_implicit() -> void:
	var r := ContentLoader.load_roots(ROOTS)
	for base in r["by_type"]["item"]:
		var want: Dictionary = BalanceItems.SLOT_IMPLICIT[base["slot"]]
		assert_eq(base["implicit"].size(), want.size(), "%s implicit count" % base["id"])
		for line in base["implicit"]:
			assert_near(float(line["base"]), float(want[line["stat"]]), 0.0001, base["id"])


func test_v18_playable_character_needs_a_full_kit() -> void:
	var w := _base()
	w["canon/characters.json"][1][0]["ultimate"] = "spell.act"
	_expect(w, "V18", "must have kind ultimate")
	w = _base()
	w["canon/characters.json"][1][0]["spells"] = []
	_expect(w, "V18", "need spells")


func test_v19_literal_text_is_refused() -> void:
	var w := _base()
	w["original/regions.json"][1][0]["name"] = "Val"
	_expect(w, "V19", "literal 'name'")


func test_conditions_are_checked() -> void:
	var w := _base()
	w["original/locations.json"][1][0]["unlock"] = {"quest_completed": "quest.none"}
	_expect(w, "V6", "unknown quest 'quest.none'")
	w["original/locations.json"][1][0]["unlock"] = {"weather": "rain"}
	_expect(w, "V7", "unknown condition 'weather'")


func _combat_world() -> Dictionary:
	var w := _base()
	w["original/abilities.json"] = [
		"ability",
		[
			_entry(
				"ability.hit",
				{
					"kind": "attack",
					"element": "arcane",
					"targeting": "nearest",
					"range_m": 2,
					"interval_s": 1.0,
					"effects": [{"type": "damage", "coeff": 1.0}],
				}
			)
		]
	]
	w["original/ai_profiles.json"] = [
		"ai_profile",
		[
			_entry(
				"ai.rusher",
				{
					"states": ["idle", "attack"],
					"target_rule": "nearest",
				}
			)
		]
	]
	w["original/enemies.json"] = [
		"enemy",
		[
			_entry(
				"enemy.boss",
				{
					"archetype": "boss",
					"family": "demon",
					"stats_l1":
					{
						"hp": 100,
						"power": 5,
						"def_ratio": 0.1,
						"barrier_ratio": 0,
						"move_speed": 3,
						"aggro_m": 8
					},
					"affinities":
					{
						"arcane": "neutral",
						"fire": "neutral",
						"frost": "neutral",
						"lightning": "neutral"
					},
					"attack": "ability.hit",
					"ai_profile": "ai.rusher",
					"xp_mult": 1,
					"gold_mult": 1,
					"model": "res://b.glb",
					"phases":
					[
						{"id": "p1", "hp_threshold": 1.0, "abilities": []},
						{"id": "p2", "hp_threshold": 0.5, "abilities": []}
					],
					"enrage_s": 300,
				}
			)
		]
	]
	w["original/loot_tables.json"] = [
		"loot_table",
		[
			_entry(
				"loot.t",
				{
					"rarity_profile": "boss",
					"entries": [{"kind": "gold", "chance": 1, "qty": [1, 2], "per": "encounter"}],
				}
			)
		]
	]
	w["original/encounters.json"] = [
		"encounter",
		[
			_entry(
				"encounter.boss",
				{
					"location": "location.l",
					"kind": "boss",
					"level": 5,
					"enemies": [{"enemy": "enemy.boss", "count": 1}],
					"loot_table": "loot.t",
					"offline_eligible": false,
					"speed_cap": 2,
					"anchor": "BossAnchor",
				}
			)
		]
	]
	w["original/dungeons.json"] = [
		"dungeon",
		[
			_entry(
				"dungeon.d",
				{
					"location": "location.l",
					"level": 5,
					"scene": "res://d.tscn",
					"map_pos": [0.5, 0.5],
					"unlock": {"start": true},
					"rooms":
					[
						{"id": "r1", "kind": "rest"},
						{"id": "r2", "kind": "boss", "encounter": "encounter.boss"}
					],
				}
			)
		]
	]
	return w


func test_combat_world_fixture_is_valid() -> void:
	assert_eq(_errors(_combat_world()), "", "valid")


func test_v10_boss_cannot_farm_offline_or_run_at_x4() -> void:
	var w := _combat_world()
	w["original/encounters.json"][1][0]["offline_eligible"] = true
	_expect(w, "V10", "cannot be offline_eligible")
	w = _combat_world()
	w["original/encounters.json"][1][0]["speed_cap"] = 4
	_expect(w, "V10", "cannot run at x4")


func test_v11_boss_phases() -> void:
	var w := _combat_world()
	w["original/enemies.json"][1][0]["phases"] = []
	_expect(w, "V11", "need phases and enrage_s")
	w = _combat_world()
	w["original/enemies.json"][1][0]["phases"][1]["hp_threshold"] = 1.0
	_expect(w, "V11", "strictly decreasing")


func test_v12_dungeon_ends_with_the_boss() -> void:
	var w := _combat_world()
	w["original/dungeons.json"][1][0]["rooms"].reverse()
	_expect(w, "V12", "last room must be the boss")


func test_v16_every_location_is_reachable_from_the_start() -> void:
	var w := _base()
	var locations: Array = w["original/locations.json"][1]
	locations[0]["fog_reveal"] = ["location.far"]
	w["original/regions.json"][1][0]["locations"].append("location.far")
	var far := _entry(
		"location.far",
		{
			"region": "region.r",
			"kind": "field",
			"level": 3,
			"scene": "res://f.tscn",
			"map_pos": [0.2, 0.2],
			"unlock": {"level_at_least": 3},
		}
	)
	locations.append(far)
	assert_eq(_errors(w), "", "reachable through fog and level")
	far["unlock"] = {"level_at_least": 99}
	_expect(w, "V16", "condition can never be met")
	far["unlock"] = {"start": true}
	locations[0]["fog_reveal"] = []
	_expect(w, "V16", "never revealed")


# --- Milestone 6: quests, NPCs, discoveries, V15, V20 -------------------------


## Minimal world with an NPC, a dialogue, a field with one encounter and two
## chained main quests.
func _quest_world() -> Dictionary:
	var w := _combat_world()
	var field := _entry(
		"location.f",
		{
			"region": "region.r",
			"kind": "field",
			"level": 1,
			"scene": "res://f.tscn",
			"map_pos": [0.2, 0.2],
			"unlock": {"quest_completed": "quest.q1"},
			"encounters": ["encounter.boss"],
		}
	)
	w["original/locations.json"][1].append(field)
	w["original/regions.json"][1][0]["locations"].append("location.f")
	w["original/encounters.json"][1][0]["location"] = "location.f"
	w["original/dialogues.json"] = [
		"dialogue",
		[_entry("dialogue.hi", {"lines": [{"speaker": "npc.n", "key_suffix": "line_01"}]})]
	]
	w["original/npcs.json"] = [
		"npc",
		[
			_entry(
				"npc.n",
				{
					"location": "location.l",
					"role": "board",
					"anchor": "npc_a",
					"model": "res://n.glb",
					"dialogues":
					[
						{
							"dialogue": "dialogue.hi",
							"condition": {"quest_state": {"id": "quest.q1", "state": "available"}},
							"offers": "quest.q1",
						}
					],
				}
			)
		]
	]
	var quest := func(id: String, objectives: Array, extra: Dictionary) -> Dictionary:
		var f := {
			"desc_key": id + ".desc",
			"kind": "main",
			"level": 1,
			"objectives": objectives,
			"rewards": {"gold": 10},
		}
		f.merge(extra, true)
		return _entry(id, f)
	w["original/quests.json"] = [
		"quest",
		[
			quest.call(
				"quest.q1",
				[{"id": "talk", "event": "TalkedTo", "target": "npc.n", "count": 1}],
				{"prerequisites": [{"start": true}], "rewards": {"unlocks": ["location.f"]}}
			),
			(
				quest
				. call(
					"quest.q2",
					[
						{
							"id": "win",
							"event": "EncounterCompleted",
							"target": "location.f",
							"count": 2
						},
						{
							"id": "boss",
							"step": 2,
							"event": "EnemyDefeated",
							"target": "enemy.boss",
							"count": 1
						},
					],
					{"prerequisites": [{"quest_completed": "quest.q1"}]}
				)
			),
		]
	]
	return w


func test_quest_world_fixture_is_valid() -> void:
	assert_eq(_errors(_quest_world()), "", "valid: q1 unlocks and reveals the field")


func test_v15_quest_prerequisites_in_a_cycle() -> void:
	var w := _quest_world()
	w["original/quests.json"][1][0]["prerequisites"] = [{"quest_completed": "quest.q2"}]
	_expect(w, "V15", "prerequisites form a cycle")


func test_v15_objective_event_must_fit_its_target() -> void:
	var w := _quest_world()
	w["original/discoveries.json"] = [
		"discovery",
		[
			_entry(
				"discovery.d",
				{
					"location": "location.l",
					"kind": "lore",
					"trigger": "interact",
					"level": 1,
					"anchor": "d1",
					"reward": {"xp": true},
					"map_pos": [0.5, 0.5],
				}
			)
		]
	]
	w["original/quests.json"][1][1]["objectives"][1]["target"] = "discovery.d"
	_expect(w, "V15", "EnemyDefeated cannot target a discovery")
	w = _quest_world()
	w["original/quests.json"][1][1]["objectives"][1]["event"] = "ItemDelivered"
	_expect(w, "V15", "ItemDelivered cannot target a enemy")
	w = _quest_world()
	w["original/quests.json"][1][1]["objectives"][1]["step"] = 3
	_expect(w, "V15", "steps must run 1..n")


func test_v15_main_quest_unreachable_from_the_start() -> void:
	var w := _quest_world()
	w["original/quests.json"][1][1]["objectives"][1]["target"] = "enemy.nowhere"
	_expect(w, "V6", "unknown")
	w = _quest_world()
	# the field only opens with q1, so q1 cannot ask for a fight there
	w.erase("original/dungeons.json")
	w["original/quests.json"][1][0]["objectives"] = [
		{"id": "win", "event": "EncounterCompleted", "target": "encounter.boss", "count": 1}
	]
	_expect(w, "V15", "main quest cannot be completed from the start")


func test_v16_quest_unlocks_reveal_and_open_places() -> void:
	var w := _quest_world()
	w["original/quests.json"][1][0]["rewards"] = {}
	_expect(w, "V16", "never revealed")


func test_new_conditions_are_checked() -> void:
	var w := _quest_world()
	var entry: Dictionary = w["original/npcs.json"][1][0]["dialogues"][0]
	entry["condition"] = {"quest_state": {"id": "quest.q1", "state": "done"}}
	_expect(w, "V7", "unknown state 'done'")
	entry["condition"] = {"objective": {"quest": "quest.q1", "id": "nope", "done": true}}
	_expect(w, "V6", "has no objective 'nope'")
	entry["condition"] = {"discovery_found": "quest.q1"}
	_expect(w, "V6", "is not a discovery")


func test_npc_roles_and_reward_unlock_tokens() -> void:
	var w := _quest_world()
	w["original/npcs.json"][1][0]["role"] = "bard"
	_expect(w, "V7", "'bard' not in")
	w = _quest_world()
	w["original/quests.json"][1][0]["rewards"]["unlocks"] = ["artifact_slot_9"]
	_expect(w, "V6", "neither a location")
	w = _quest_world()
	w["original/quests.json"][1][0]["rewards"]["materials"] = {"enemy.boss": 1}
	_expect(w, "V6", "'enemy.boss' is not a material")


func test_v20_save_ids_must_still_exist() -> void:
	var r := ContentLoader.load_roots(ROOTS)
	var state := NewGame.create(r["by_type"]["start"][0], 1, 1, r["by_id"])
	assert_eq(ContentRules.check_save_ids(state, r["by_id"]).size(), 0, "a new game is fine")
	state["progress"]["bestiary"]["enemy.removed_wolf"] = 3
	var errors := ContentRules.check_save_ids(state, r["by_id"])
	assert_eq(errors.size(), 1, "one removed id")
	assert_true(
		errors[0].begins_with("V20 ") and errors[0].contains("enemy.removed_wolf"), errors[0]
	)
	assert_eq(
		ContentRules.check_save_ids(state, r["by_id"], {"enemy.removed_wolf": "migration"}).size(),
		0,
		"retired through a migration"
	)
