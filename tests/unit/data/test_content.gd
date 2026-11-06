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
					"stat": "power",
					"values_by_tier": [1, 2, 2, 3, 4],
					"weight": 1,
				}
			)
		]
	]
	_expect(w, "V17", "strictly increasing")


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
