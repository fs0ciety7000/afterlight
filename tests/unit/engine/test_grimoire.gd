extends TestCase
## Criterion 4.6 and GAME_BALANCE §16-§18: fusion (3 × tier n → tier n+1 at
## table cost), one conversion rune per spell, spell ranks and rune slots,
## artifacts, shop.

const P := preload("res://tests/unit/engine/progression_fixtures.gd")
const FERN := "character.fern"
const ZOLTRAAK := "spell.zoltraak"
const RICH := 1_000_000


func _rich(level: int = 20) -> Dictionary:
	return (
		P
		. state(
			RICH,
			{
				"material.rune_shard": RICH,
				"material.grimoire_page": RICH,
				"material.ashen_essence": RICH,
			},
			level
		)
	)


func test_fusion_turns_three_runes_into_one_of_the_next_tier_at_table_cost() -> void:
	var costs := {1: [150, 5], 2: [450, 10], 3: [1350, 15], 4: [4050, 20]}
	for tier in costs:
		var s := _rich()
		Inventory.add_rune(s, "rune.ember", tier, 4)
		var r := RuneRules.fuse(s, "rune.ember", tier, P.content())
		assert_true(r["ok"], "fuse P%d" % tier)
		assert_eq([r["gold"], r["shards"]], costs[tier], "cost P%d" % tier)
		assert_eq(Inventory.rune_count(r["state"], "rune.ember", tier), 1, "3 used, 1 left")
		assert_eq(Inventory.rune_count(r["state"], "rune.ember", tier + 1), 1, "one new rune")
		assert_eq(r["state"]["wallet"]["gold"], RICH - costs[tier][0], "gold paid")
		assert_eq(
			r["state"]["wallet"]["materials"]["material.rune_shard"],
			RICH - costs[tier][1],
			"shards paid"
		)


func test_fusion_refusals() -> void:
	var s := _rich()
	Inventory.add_rune(s, "rune.frost", 1, 2)
	var r := RuneRules.fuse(s, "rune.frost", 1, P.content())
	assert_eq(r["error"], "error.fusion_not_enough_runes", "two runes only")
	assert_eq(r["params"], {"required": 3, "owned": 2}, "params")
	Inventory.add_rune(s, "rune.frost", 5, 3)
	assert_eq(RuneRules.fuse(s, "rune.frost", 5, P.content())["error"], "error.rune_tier_max", "P5")
	var poor := P.state(10, {"material.rune_shard": 100})
	Inventory.add_rune(poor, "rune.frost", 1, 3)
	var no_gold := RuneRules.fuse(poor, "rune.frost", 1, P.content())
	assert_eq(
		[no_gold["error"], no_gold["params"]["required"]], ["error.not_enough_gold", 150], "or"
	)


func test_one_conversion_rune_per_spell_and_no_duplicate() -> void:
	var s := _rich()
	s["characters"][FERN]["spells"][ZOLTRAAK] = 5
	for id in ["rune.ember", "rune.frost", "rune.potency"]:
		Inventory.add_rune(s, id, 1, 2)
	s = Grimoire.socket(s, FERN, ZOLTRAAK, "rune.ember", 1, P.content())["state"]
	var second := Grimoire.socket(s, FERN, ZOLTRAAK, "rune.frost", 1, P.content())
	assert_eq(second["error"], "error.rune_conversion_taken", "two conversions refused")
	var r := Grimoire.socket(s, FERN, ZOLTRAAK, "rune.potency", 1, P.content())
	assert_true(r["ok"], "a modifier fits")
	var dup := Grimoire.socket(r["state"], FERN, ZOLTRAAK, "rune.potency", 1, P.content())
	assert_eq(dup["error"], "error.rune_duplicate", "same rune twice refused")
	assert_eq(
		Grimoire.spell_mods(r["state"], FERN, P.content()),
		{ZOLTRAAK: {"element": "fire", "status_chance": 0.2, "damage_bonus": 0.08}},
		"combat spell_mods"
	)


func test_rune_slots_follow_the_rank_and_unsocket_is_free() -> void:
	var s := _rich()
	Inventory.add_rune(s, "rune.acuity", 2, 1)
	Inventory.add_rune(s, "rune.thrift", 1, 1)
	s = Grimoire.socket(s, FERN, ZOLTRAAK, "rune.acuity", 2, P.content())["state"]
	var full := Grimoire.socket(s, FERN, ZOLTRAAK, "rune.thrift", 1, P.content())
	assert_eq([full["error"], full["params"]], ["error.rune_slots_full", {"slots": 1}], "rank 1")
	assert_eq(Inventory.rune_count(s, "rune.acuity", 2), 0, "taken from the stock")
	var gold_before: int = s["wallet"]["gold"]
	var off := Grimoire.unsocket(s, FERN, ZOLTRAAK, 0)
	assert_true(off["ok"], "unsocket")
	assert_eq(Inventory.rune_count(off["state"], "rune.acuity", 2), 1, "back in the stock")
	assert_eq(off["state"]["wallet"]["gold"], gold_before, "free")
	assert_eq(off["state"]["characters"][FERN]["runes"], {}, "spell empty")
	assert_eq(
		Grimoire.socket(s, FERN, "spell.mana_bolt", "rune.thrift", 1, P.content())["error"],
		"error.spell_unknown",
		"never on the auto attack"
	)
	var low := P.state(0, {}, 1)
	Inventory.add_rune(low, "rune.thrift", 1, 1)
	var locked := Grimoire.socket(low, FERN, "spell.mana_volley", "rune.thrift", 1, P.content())
	assert_eq([locked["error"], locked["params"]], ["error.spell_locked", {"level": 3}], "locked")


func test_spell_rank_costs_and_level_gates() -> void:
	var table := [[250, 2, 3], [1000, 4, 6], [2250, 6, 9], [4000, 8, 12]]
	var s := _rich(12)
	for r in 4:
		var q := Grimoire.rank_quote(s, FERN, ZOLTRAAK, P.content())
		assert_eq([q["gold"], q["pages"], q["level_required"]], table[r], "rank %d" % (r + 2))
		var up := Grimoire.rank_up(s, FERN, ZOLTRAAK, P.content())
		assert_true(up["ok"], "rank up %d" % (r + 2))
		s = up["state"]
	assert_eq(s["characters"][FERN]["spells"][ZOLTRAAK], 5, "rank 5")
	assert_eq(BalanceGrimoire.rune_slots(5), 3, "3 slots at rank 5")
	assert_eq(Grimoire.rank_up(s, FERN, ZOLTRAAK, P.content())["error"], "error.rank_max", "max")
	var young := _rich(5)
	young["characters"][FERN]["spells"][ZOLTRAAK] = 2
	var gated := Grimoire.rank_up(young, FERN, ZOLTRAAK, P.content())
	assert_eq([gated["error"], gated["params"]], ["error.level_required", {"level": 6}], "gate")
	var poor := P.state(0, {"material.grimoire_page": 2}, 3)
	var no_gold := Grimoire.rank_up(poor, FERN, ZOLTRAAK, P.content())
	assert_eq(no_gold["params"]["required"], 250, "250 gold required")


func test_artifact_slots_levels_and_stat_effects() -> void:
	var s := _rich(5)
	s["artifacts"] = {"artifact.traveler_compass": 1, "artifact.cracked_hourglass": 1}
	var locked := ArtifactRules.equip(s, FERN, 0, "artifact.traveler_compass")
	assert_eq(
		[locked["error"], locked["params"]], ["error.artifact_slot_locked", {"level": 6}], "L5"
	)
	s["characters"][FERN]["level"] = 6
	var before := Equipment.stats(s, FERN, P.content())
	s = ArtifactRules.equip(s, FERN, 0, "artifact.traveler_compass")["state"]
	assert_near(
		Equipment.stats(s, FERN, P.content())["gold_find"] - before["gold_find"], 0.08, 1e-9, "+8 %"
	)
	var second := ArtifactRules.equip(s, FERN, 1, "artifact.cracked_hourglass")
	assert_eq(second["params"], {"level": 15}, "slot 2 at level 15")
	s["characters"][FERN]["level"] = 15
	s = ArtifactRules.equip(s, FERN, 1, "artifact.cracked_hourglass")["state"]
	assert_near(ArtifactRules.offline_efficiency_bonus(s, FERN, P.content()), 0.03, 1e-9, "+0.03")
	assert_eq(
		ArtifactRules.equip(s, FERN, 1, "artifact.traveler_compass")["error"],
		"error.artifact_already_equipped",
		"once"
	)
	var costs := [[500, 1], [2000, 2], [4500, 3], [8000, 5]]
	for i in 4:
		var r := ArtifactRules.level_up(s, "artifact.traveler_compass")
		assert_eq([r["gold"], r["essence"]], costs[i], "level %d" % (i + 2))
		s = r["state"]
	assert_eq(
		ArtifactRules.level_up(s, "artifact.traveler_compass")["error"],
		"error.artifact_max_level",
		"max"
	)
	assert_near(Equipment.stats(s, FERN, P.content())["gold_find"], 0.20, 1e-9, "level 5")
	s = ArtifactRules.unequip(s, FERN, 0)["state"]
	assert_near(Equipment.stats(s, FERN, P.content())["gold_find"], 0.0, 1e-9, "removed")


func test_shop_prices_caps_and_gold() -> void:
	var s := P.state(100, {}, 10)
	var shop := "shop.aubelin_merchant"
	assert_eq(Merchant.price(s, "consumable.healing_draught", P.content()), 57, "30 × 1.9")
	assert_eq(Merchant.price(s, "consumable.mana_elixir", P.content()), 48, "25 × 1.9 rounded")
	var r := Merchant.buy(s, shop, "consumable.healing_draught", 1, P.content())
	assert_true(r["ok"], "buy")
	assert_eq(r["state"]["wallet"]["gold"], 43, "paid")
	assert_eq(r["state"]["consumables"]["consumable.healing_draught"], 1, "carried")
	var poor := Merchant.buy(r["state"], shop, "consumable.healing_draught", 1, P.content())
	assert_eq([poor["error"], poor["params"]["required"]], ["error.not_enough_gold", 57], "gold")
	s["consumables"]["consumable.mana_elixir"] = 5
	var cap := Merchant.buy(s, shop, "consumable.mana_elixir", 1, P.content())
	assert_eq([cap["error"], cap["params"]], ["error.carry_max", {"max": 5}], "cap")
	assert_eq(
		Merchant.buy(s, shop, "consumable.nope", 1, P.content())["error"],
		"error.not_in_stock",
		"stock"
	)


func test_party_build_carries_gear_ranks_runes_and_potions() -> void:
	var s := _rich(10)
	s["inventory"] = [P.item("w", "item.birch_staff", "rare", 10, [], 4)]
	s = Equipment.equip(s, FERN, "w", P.content())["state"]
	s["characters"][FERN]["spells"][ZOLTRAAK] = 3
	Inventory.add_rune(s, "rune.storm", 2, 1)
	s = Grimoire.socket(s, FERN, ZOLTRAAK, "rune.storm", 2, P.content())["state"]
	s["consumables"] = {"consumable.healing_draught": 2}
	var setup := PartyBuild.setup(s, P.content())
	var e: Dictionary = setup["party"][0]
	assert_near(e["flat"]["power"], 20.98, 0.01, "gear")
	assert_eq(e["spell_ranks"], {ZOLTRAAK: 3}, "ranks")
	assert_eq(e["spell_mods"][ZOLTRAAK]["element"], "lightning", "conversion")
	assert_eq(setup["consumables"], {"consumable.healing_draught": 2}, "potions")
	setup["encounter"] = "encounter.whispering_wood_01"
	setup["seed"] = 3
	var sim := CombatSim.create(setup, P.content())
	assert_eq(sim.error, "", "sim accepts the setup")
	assert_eq(StateSchema.validate(s)["errors"].size(), 0, "state stays valid")
