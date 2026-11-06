extends TestCase


func _victory(xp: int, gold: int) -> Dictionary:
	return {
		"type": "encounter_completed",
		"encounter": "encounter.test",
		"result": "victory",
		"rewards": {"xp": xp, "gold": gold, "materials": {"material.mana_dust": 2}},
	}


func test_victory_grants_xp_gold_materials_and_counts_the_clear() -> void:
	var r := CombatOutcome.apply(Fixtures.new_state(), _victory(50, 12))
	var s: Dictionary = r["state"]
	assert_eq(s["characters"]["character.fern"]["level"], 2, "level up at 40 XP")
	assert_eq(s["characters"]["character.fern"]["xp"], 10, "carry over")
	assert_eq(s["wallet"]["gold"], 112, "gold added to the 100 of the fixture")
	assert_eq(s["wallet"]["materials"]["material.mana_dust"], 5, "3 + 2 dust")
	assert_eq(s["progress"]["cleared_encounters"]["encounter.test"], 1, "cleared once")
	assert_eq(r["summary"]["levels_gained"], 1, "summary")
	assert_eq(StateSchema.validate(s)["errors"].size(), 0, "state stays valid")


func test_defeat_changes_nothing() -> void:
	var before := Fixtures.new_state()
	var r := CombatOutcome.apply(before, {"result": "defeat", "encounter": "encounter.test"})
	assert_eq(SaveCodec.canonical(r["state"]), SaveCodec.canonical(before), "unchanged")


func test_input_state_is_not_mutated() -> void:
	var before := Fixtures.new_state()
	var copy := SaveCodec.canonical(before)
	CombatOutcome.apply(before, _victory(10, 1))
	assert_eq(SaveCodec.canonical(before), copy, "pure")


func test_victory_puts_loot_in_the_bag_and_stocks() -> void:
	var completed := _victory(0, 0)
	completed["rewards"]["items"] = [
		ProgressionFixtures.item("", "item.birch_staff", "rare", 4),
	]
	completed["rewards"]["runes"] = [{"id": "rune.frost", "tier": 1}]
	completed["consumables_used"] = {"consumable.healing_draught": 1}
	var before := Fixtures.new_state()
	before["consumables"] = {"consumable.healing_draught": 3}
	var r := CombatOutcome.apply(before, completed, ProgressionFixtures.content())
	var s: Dictionary = r["state"]
	assert_eq(s["inventory"].size(), 1, "item in the bag")
	assert_eq(r["summary"]["items"], [s["inventory"][0]["uid"]], "summary lists it")
	assert_eq(s["runes"]["rune.frost"][0], 1, "rune stocked")
	assert_eq(s["consumables"]["consumable.healing_draught"], 2, "used potion removed")
	assert_eq(StateSchema.validate(s)["errors"].size(), 0, "state stays valid")


func test_defeat_still_spends_the_consumables_used() -> void:
	var before := Fixtures.new_state()
	before["consumables"] = {"consumable.healing_draught": 1}
	var r := CombatOutcome.apply(
		before, {"result": "defeat", "consumables_used": {"consumable.healing_draught": 1}}
	)
	assert_eq(r["state"]["consumables"], {}, "spent")


func test_xp_at_the_cap_is_wasted_and_reported() -> void:
	var before := Fixtures.new_state()
	before["characters"]["character.fern"]["level"] = 20
	var r := CombatOutcome.apply(before, _victory(120, 0))
	assert_eq(r["state"]["characters"]["character.fern"]["xp"], 0, "no XP kept")
	assert_eq(r["summary"]["wasted_xp"], 120, "wasted")
	assert_eq(r["summary"]["lines"], [{"key": "log.xp_wasted", "params": {"xp": 120}}], "line")
