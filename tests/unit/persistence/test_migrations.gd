extends TestCase
## Exercises the migration chain with a synthetic future format, so the
## mechanism is proven before the first real migration is needed.


func _v0_state() -> Dictionary:
	# Hypothetical older format: gold stored at top level, no wallet.
	var state := Fixtures.new_state()
	var gold: int = state["wallet"]["gold"]
	state.erase("wallet")
	state["gold"] = gold
	return state


static func _v0_to_v1(s: Dictionary) -> Dictionary:
	s["wallet"] = {"gold": s["gold"], "materials": {}}
	s.erase("gold")
	return s


func _migrations() -> Dictionary:
	return {0: _v0_to_v1}


func test_old_save_is_migrated_to_current_version() -> void:
	var text := SaveCodec.encode(_v0_state(), 1, 0)
	var r := SaveCodec.decode(text, _migrations(), 1)
	assert_true(r["ok"], "ok (%s %s)" % [r["error"], r["detail"]])
	assert_eq(r["migrated_from"], 0, "migrated from v0")
	assert_eq(r["version"], 1, "now v1")
	assert_eq(r["state"]["wallet"]["gold"], 100, "gold moved into wallet")


func test_missing_migration_step_is_an_error_not_a_crash() -> void:
	var text := SaveCodec.encode(_v0_state(), 1, 0)
	assert_eq(SaveCodec.decode(text, {}, 1)["error"], SaveCodec.ERR_MIGRATION, "no step")


func test_released_table_covers_every_version_below_current() -> void:
	var table := SaveMigrations.all()
	for v in range(1, SaveCodec.CURRENT_VERSION):
		assert_true(table.has(v), "migration from v%d exists" % v)


## A state as saved by format v2 (Milestone 2-3): no progression fields.
func _v2_state() -> Dictionary:
	var v2 := Fixtures.new_state()
	for key in ["runes", "consumables", "artifacts"]:
		v2.erase(key)
	for id in v2["characters"]:
		v2["characters"][id].erase("runes")
		v2["characters"][id].erase("artifacts")
	return v2


func test_real_v1_save_migrates_to_current_with_fog_and_spawn() -> void:
	var v1 := _v2_state()
	v1["world"].erase("revealed_locations")
	v1["world"].erase("spawn")
	v1["world"]["discovered_locations"] = ["location.test_village", "location.other"]
	var r := SaveCodec.decode(SaveCodec.encode(v1, 1, 1), SaveMigrations.all())
	assert_true(r["ok"], "ok (%s %s)" % [r["error"], r["detail"]])
	assert_eq(r["migrated_from"], 1, "from v1")
	assert_eq(
		r["state"]["world"]["revealed_locations"],
		["location.test_village", "location.other"],
		"fog"
	)
	assert_eq(r["state"]["world"]["spawn"], "default", "spawn")


func test_real_v2_save_migrates_to_v3_with_progression_fields() -> void:
	var v2 := _v2_state()
	v2["inventory"] = [
		{
			"uid": "i1",
			"item_id": "item.birch_staff",
			"rarity": "common",
			"item_level": 2,
			"affixes": [{"id": "affix.power_flat", "value": 3.0}],
			"enhance": 1,
			"sockets": [],
		}
	]
	var r := SaveCodec.decode(SaveCodec.encode(v2, 1, 2), SaveMigrations.all())
	assert_true(r["ok"], "ok (%s %s)" % [r["error"], r["detail"]])
	assert_eq(r["migrated_from"], 2, "from v2")
	assert_eq(r["version"], SaveCodec.CURRENT_VERSION, "now current")
	var s: Dictionary = r["state"]
	var item: Dictionary = s["inventory"][0]
	assert_true(not item.has("sockets"), "sockets dropped")
	assert_eq([item["legendary"], item["enhance_attempts"], item["pity"]], ["", 0, 0], "new fields")
	assert_eq(item["enhance"], 1, "enhancement kept")
	assert_eq(s["characters"]["character.fern"]["artifacts"], ["", ""], "artifact slots")
	assert_eq(s["characters"]["character.fern"]["runes"], {}, "no socketed rune")
	assert_eq([s["runes"], s["consumables"], s["artifacts"]], [{}, {}, {}], "empty stocks")
	assert_eq(s["wallet"]["gold"], 100, "wallet untouched")


## A state as saved by format v3 (Milestone 4): no offline block.
func test_real_v3_save_migrates_to_v4_with_an_empty_offline_block() -> void:
	var v3 := Fixtures.new_state()
	v3.erase("offline")
	v3["farming"] = "encounter.whispering_wood_02"
	var r := SaveCodec.decode(SaveCodec.encode(v3, 1, 3), SaveMigrations.all())
	assert_true(r["ok"], "ok (%s %s)" % [r["error"], r["detail"]])
	assert_eq([r["migrated_from"], r["version"]], [3, SaveCodec.CURRENT_VERSION], "v3 → current")
	assert_eq(r["state"]["offline"], {"pending": []}, "no pending summary")
	assert_eq(r["state"]["farming"], "encounter.whispering_wood_02", "offline hunt kept")


func test_v3_state_without_offline_is_invalid_as_v4() -> void:
	var v3 := Fixtures.new_state()
	v3.erase("offline")
	assert_true(not StateSchema.validate(v3)["errors"].is_empty(), "offline is required")


## A state as saved by format v4 (Milestone 5): progress without quests
## content, contracts, dungeon run or unlock tokens.
func _v4_state(level: int, visited: Array) -> Dictionary:
	var v4 := Fixtures.new_state()
	for key in ["contracts", "dungeon_run", "unlocks"]:
		v4["progress"].erase(key)
	v4["progress"]["quests"] = {}
	v4["progress"]["bestiary"] = {"enemy.mist_wolf": 12}
	v4["characters"]["character.fern"]["level"] = level
	v4["world"]["discovered_locations"].append_array(visited)
	v4["world"]["revealed_locations"].append_array(visited)
	return v4


func test_real_v4_save_migrates_to_v5_with_quests_and_contracts() -> void:
	var r := SaveCodec.decode(SaveCodec.encode(_v4_state(3, []), 1, 4), SaveMigrations.all())
	assert_true(r["ok"], "ok (%s %s)" % [r["error"], r["detail"]])
	assert_eq([r["migrated_from"], r["version"]], [4, SaveCodec.CURRENT_VERSION], "v4 → current")
	var p: Dictionary = r["state"]["progress"]
	assert_eq(p["quests"].keys(), ["quest.main_01"], "main_01 starts")
	assert_eq(p["quests"]["quest.main_01"]["state"], "active", "active")
	assert_eq(p["contracts"], {"day_index": -1, "offers": []}, "contracts roll at first load")
	assert_eq(p["dungeon_run"], {}, "outside any dungeon")
	assert_eq(p["unlocks"], [], "no artifact slot below level 6")
	assert_eq(p["bestiary"], {"enemy.mist_wolf": 12}, "bestiary kept")


func test_v4_player_who_reached_the_ruins_keeps_them_open() -> void:
	var v4 := _v4_state(8, ["location.lantern_mire", "location.watch_ruins"])
	var r := SaveCodec.decode(SaveCodec.encode(v4, 1, 4), SaveMigrations.all())
	var p: Dictionary = r["state"]["progress"]
	assert_eq(p["quests"]["quest.main_01"]["state"], "turned_in", "main_01 done")
	assert_eq(p["quests"]["quest.main_02"]["state"], "turned_in", "main_02 done")
	assert_true(not p["quests"].has("quest.main_03"), "main_03 waits for Bastien")
	assert_eq(p["unlocks"], ["artifact_slot_1"], "slot 1 kept at level 8")
	var c := CombatBench.content()
	assert_eq(WorldRules.status("location.watch_ruins", r["state"], c), "available", "still open")


func test_v4_state_is_invalid_as_v5() -> void:
	var v4 := _v4_state(1, [])
	assert_true(not StateSchema.validate(v4)["errors"].is_empty(), "contracts are required")


## A state as saved by format v5 (Milestone 6 before tactics): no saved
## tactics, no tips seen.
func _v5_state() -> Dictionary:
	var v5 := Fixtures.new_state()
	v5["characters"]["character.fern"].erase("tactics")
	v5["progress"].erase("tips_seen")
	return v5


func test_real_v5_save_migrates_to_v6_with_default_tactics_and_no_tip_seen() -> void:
	var r := SaveCodec.decode(SaveCodec.encode(_v5_state(), 1, 5), SaveMigrations.all())
	assert_true(r["ok"], "ok (%s %s)" % [r["error"], r["detail"]])
	assert_eq([r["migrated_from"], r["version"]], [5, 6], "v5 → v6")
	assert_eq(r["state"]["characters"]["character.fern"]["tactics"], {}, "default tactics")
	assert_eq(r["state"]["progress"]["tips_seen"], [], "no tip seen")


func test_v5_state_is_invalid_as_v6() -> void:
	assert_true(not StateSchema.validate(_v5_state())["errors"].is_empty(), "tactics are required")


## V20: the reference save (a v5 game that went through the milestone 6
## content) still loads, and every id it holds exists in the data.
func test_v20_reference_save_ids_still_exist() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/saves/reference_v5.json")
	var r := SaveCodec.decode(text, SaveMigrations.all())
	assert_true(r["ok"], "reference save loads (%s %s)" % [r["error"], r["detail"]])
	var errors := ContentRules.check_save_ids(
		r["state"], CombatBench.content(), SaveMigrations.RETIRED_IDS
	)
	assert_eq(errors.size(), 0, "\n".join(errors))
	assert_true(r["state"]["progress"]["quests"].size() >= 3, "the save has quests")
