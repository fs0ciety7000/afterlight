extends TestCase
## Milestone 4 criteria 4.2 and 4.3 (GAME_BALANCE §14): rarity by source,
## item level, implicit, affixes without duplicate id or group, values in
## their scaled range, legendaries in the upper half; determinism.

const DRAWS := 100_000
const TOLERANCE_PT := 0.5


func _content() -> Dictionary:
	return CombatBench.content()


func test_rarity_frequencies_match_the_weights_of_each_source() -> void:
	for profile in BalanceItems.RARITY_WEIGHTS:
		var rng := SeededRng.new(SeededRng.derive_seed(42, "rarity:" + profile))
		var counts := {}
		for i in DRAWS:
			var r := ItemFactory.roll_rarity(rng, profile)
			counts[r] = int(counts.get(r, 0)) + 1
		var weights: Dictionary = BalanceItems.RARITY_WEIGHTS[profile]
		for rarity in weights:
			var pct := 100.0 * float(counts.get(rarity, 0)) / float(DRAWS)
			assert_near(pct, float(weights[rarity]), TOLERANCE_PT, "%s %s" % [profile, rarity])


func test_item_level_follows_the_source() -> void:
	assert_eq(BalanceItems.item_level(5, "normal"), 5, "normal")
	assert_eq(BalanceItems.item_level(11, "elite"), 12, "elite +1")
	assert_eq(BalanceItems.item_level(12, "boss"), 14, "boss +2")


func test_implicit_and_scales_match_the_balance_example() -> void:
	# §14.3: rare staff ilvl 10 → ilvl_mult 2.35, tier 2, implicit 16.92.
	assert_near(BalanceItems.ilvl_mult(10), 2.35, 0.0001, "ilvl_mult")
	assert_eq(BalanceItems.affix_tier(10), 2, "tier")
	assert_near(BalanceItems.pct_scale(10), 1.25, 0.0001, "pct scale")
	assert_near(BalanceItems.implicit_value("power", 6.0, 10, "rare", 0), 16.92, 0.001, "implicit")
	# §2.2: the same staff at +4.
	assert_near(BalanceItems.implicit_value("power", 6.0, 10, "rare", 4), 20.98, 0.01, "at +4")
	# Amulet crit chance follows the tier, not ilvl_mult.
	assert_near(
		BalanceItems.implicit_value("crit_chance", 0.02, 10, "common", 0), 0.025, 0.0001, "amulet"
	)
	assert_eq(BalanceItems.affix_tier(30), 4, "tier is capped at 4")


func _roll_many(count: int) -> Array:
	var content := _content()
	var out := []
	var rng := SeededRng.new(7)
	var profiles := BalanceItems.RARITY_WEIGHTS.keys()
	for i in count:
		var profile: String = profiles[i % profiles.size()]
		var ilvl := 1 + (i % 20)
		out.append(ItemFactory.roll_item(rng, content, profile, ilvl))
	return out


func test_affixes_have_no_duplicate_id_or_group_and_the_right_count() -> void:
	var content := _content()
	for item in _roll_many(4000):
		var base: Dictionary = content[item["item_id"]]
		assert_true(int(base["min_ilvl"]) <= int(item["item_level"]), "base min_ilvl")
		var ids := {}
		var groups := {}
		for a in item["affixes"]:
			var affix: Dictionary = content[a["id"]]
			assert_true(not ids.has(a["id"]), "duplicate affix %s" % a["id"])
			assert_true(not groups.has(affix["group"]), "duplicate group %s" % affix["group"])
			assert_true((affix["slots"] as Array).has(base["slot"]), "affix fits the slot")
			ids[a["id"]] = true
			groups[affix["group"]] = true
		assert_eq(item["affixes"].size(), BalanceItems.AFFIX_COUNT[item["rarity"]], "affix count")


func test_affix_values_stay_in_range_and_legendaries_roll_the_upper_half() -> void:
	var content := _content()
	var legendaries := 0
	for item in _roll_many(4000):
		var legendary: bool = item["rarity"] == "legendary"
		for a in item["affixes"]:
			var span := ItemFactory.affix_range(content[a["id"]], int(item["item_level"]))
			var low: float = (span[0] + span[1]) * 0.5 if legendary else span[0]
			assert_true(
				float(a["value"]) >= low - 1e-9 and float(a["value"]) <= span[1] + 1e-9,
				"%s %s in [%f, %f]: %f" % [item["rarity"], a["id"], low, span[1], a["value"]]
			)
		if legendary:
			legendaries += 1
			assert_true(item["legendary"] != "", "legendary effect")
			assert_eq(
				content[item["legendary"]]["slot"],
				content[item["item_id"]]["slot"],
				"effect fits the slot"
			)
		else:
			assert_eq(item["legendary"], "", "no effect below legendary")
	assert_true(legendaries > 50, "enough legendaries sampled (%d)" % legendaries)


func test_same_seed_gives_the_same_item() -> void:
	var a := ItemFactory.roll_item(SeededRng.new(99), _content(), "elite", 12)
	var b := ItemFactory.roll_item(SeededRng.new(99), _content(), "elite", 12)
	assert_eq(a, b, "deterministic")
	var c := ItemFactory.roll_item(SeededRng.new(100), _content(), "elite", 12)
	assert_true(a != c, "another seed gives another item")


func test_rune_tiers_follow_the_source() -> void:
	var rng := SeededRng.new(3)
	var seen := {}
	for i in 3000:
		var normal := ItemFactory.roll_rune(rng, _content(), "normal")
		assert_true(int(normal["tier"]) <= 2, "normal drops P1-P2")
		var boss := ItemFactory.roll_rune(rng, _content(), "boss")
		assert_true(int(boss["tier"]) >= 2, "boss drops P2-P3")
		seen[normal["id"]] = true
	assert_eq(seen.size(), 8, "every rune type can drop")


func test_modifiers_scale_implicit_and_flat_affixes_with_enhancement() -> void:
	var item := {
		"item_id": "item.birch_staff",
		"rarity": "rare",
		"item_level": 10,
		"affixes":
		[{"id": "affix.power_pct", "value": 0.075}, {"id": "affix.power_flat", "value": 8.9}],
		"legendary": "",
		"enhance": 4,
	}
	var sums := ItemFactory.sum_modifiers(ItemFactory.modifiers(item, _content()))
	assert_near(sums["flat"]["power"], 20.98 + 8.9 * 1.24, 0.01, "implicit + flat affix at +4")
	assert_near(sums["percent"]["power"], 0.075, 0.0001, "percent affix unchanged")


func _sim_with_all_enemies_killed(encounter: String, first_clear: bool) -> CombatSim:
	var sim := (
		CombatSim
		. create(
			{
				"encounter": encounter,
				"seed": 5,
				"party": [CombatBench.fern(12)],
				"first_clear": first_clear,
			},
			_content()
		)
	)
	for u in sim.units:
		if u["side"] == "enemy":
			sim.kills.append(u["uid"])
	return sim


func test_boss_first_kill_gives_epic_items_the_bell_and_five_essences() -> void:
	var r := CombatRewards.compute(_sim_with_all_enemies_killed("encounter.cloister_boss", true))
	assert_eq(r["items"].size(), 2, "two items")
	for item in r["items"]:
		assert_true(item["rarity"] in ["epic", "legendary"], "epic or better")
		assert_eq(item["item_level"], 14, "ilvl = 12 + 2")
	assert_eq(r["artifacts"], ["artifact.ashen_bell"], "the bell")
	assert_eq(r["materials"]["material.ashen_essence"], 5, "five essences")
	assert_eq(r["runes"].size(), 1, "one rune")
	var again := CombatRewards.compute(
		_sim_with_all_enemies_killed("encounter.cloister_boss", false)
	)
	assert_eq(again["artifacts"], [], "no second bell")
	assert_true(again["materials"]["material.ashen_essence"] in [2, 3], "2-3 essences")


func test_elite_gives_at_least_one_item_and_rewards_are_reproducible() -> void:
	var a := CombatRewards.compute(_sim_with_all_enemies_killed("encounter.cloister_alpha", false))
	var b := CombatRewards.compute(_sim_with_all_enemies_killed("encounter.cloister_alpha", false))
	assert_true(a["items"].size() >= 1, "guaranteed item")
	assert_eq(a, b, "same seed, same loot")


## Rolled affix values are stable through JSON (the save checksum is computed
## on reloaded JSON): some raw doubles drifted by one ulp per round trip, and
## a save holding one failed its write verification.
func test_rolled_affix_values_are_stable_through_json() -> void:
	var rng := SeededRng.new(SeededRng.derive_seed(7, "json_stable"))
	var unstable := 0
	for i in 6000:
		var item := ItemFactory.roll_item(rng, _content(), "chest", 1 + i % 20)
		for a in item["affixes"]:
			var once: Variant = JSON.parse_string(JSON.stringify([a["value"]], "", true, true))[0]
			var twice: Variant = JSON.parse_string(JSON.stringify([once], "", true, true))[0]
			if once != twice:
				unstable += 1
	assert_eq(unstable, 0, "unstable affix values")


## GDD decision 29: the first clear of whispering_wood_01 gives an uncommon
## birch staff of item level 1, after the table draws; repeats do not.
func test_first_clear_of_the_first_pack_gives_the_staff() -> void:
	var r := CombatRewards.compute(
		_sim_with_all_enemies_killed("encounter.whispering_wood_01", true)
	)
	var again := CombatRewards.compute(
		_sim_with_all_enemies_killed("encounter.whispering_wood_01", false)
	)
	assert_eq(r["items"].size(), again["items"].size() + 1, "one more item on the first clear")
	var staff: Dictionary = r["items"][-1]
	assert_eq([staff["item_id"], staff["rarity"]], ["item.birch_staff", "uncommon"], "the staff")
	assert_eq(staff["item_level"], 1, "ilvl = encounter level")
	assert_eq(staff["affixes"].size(), BalanceItems.AFFIX_COUNT["uncommon"], "affixes rolled")
	var a := CombatRewards.compute(
		_sim_with_all_enemies_killed("encounter.whispering_wood_01", true)
	)
	assert_eq(a, r, "same seed, same staff")
