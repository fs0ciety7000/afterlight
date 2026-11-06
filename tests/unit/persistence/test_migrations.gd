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
	assert_eq([r["migrated_from"], r["version"]], [3, 4], "v3 → v4")
	assert_eq(r["state"]["offline"], {"pending": []}, "no pending summary")
	assert_eq(r["state"]["farming"], "encounter.whispering_wood_02", "offline hunt kept")


func test_v3_state_without_offline_is_invalid_as_v4() -> void:
	var v3 := Fixtures.new_state()
	v3.erase("offline")
	assert_true(not StateSchema.validate(v3)["errors"].is_empty(), "offline is required")
