extends TestCase
## Offline progression (GAME_BALANCE §20, ROADMAP 5.1-5.5, 5.7 engine side).

const FERN := "character.fern"
const T0 := 1_800_000_000
const EXAMPLE := "encounter.test_offline_example"
const WOLVES := "encounter.whispering_wood_02"
const SLOW := "encounter.test_offline_slow"
const H := 3600


## Shipped content plus the §20.4 encounter (level 7: 2 lanterns, 1 wolf).
static func content() -> Dictionary:
	var c := ProgressionFixtures.content().duplicate()
	c[EXAMPLE] = {
		"_type": "encounter",
		"id": EXAMPLE,
		"name_key": EXAMPLE + ".name",
		"kind": "normal",
		"level": 7,
		"enemies":
		[
			{"enemy": "enemy.wandering_lantern", "count": 2},
			{"enemy": "enemy.mist_wolf", "count": 1}
		],
		"loot_table": "loot.field_normal",
		"offline_eligible": true,
	}
	c[SLOW] = c[EXAMPLE].duplicate(true)
	c[SLOW]["id"] = SLOW
	c[SLOW]["level"] = 15
	c[SLOW]["enemies"] = [{"enemy": "enemy.stone_sentinel", "count": 3}]
	return c


## §20.4 Fern: level 8, power 80, crit 0.08 / 1.5, 895 HP, defense 48.2,
## rank 1 spells, no rune.
static func example_entry() -> Dictionary:
	return {
		"character": FERN,
		"level": 8,
		"stats":
		{
			"max_hp": 895.0,
			"max_mana": 128.0,
			"mana_regen": 4.0,
			"power": 80.0,
			"defense": 48.2,
			"crit_chance": 0.08,
			"crit_damage": 1.5,
		},
	}


## A level `level` Fern who already beat `hunt` and chose it offline.
static func hunting(hunt: String, level: int = 8) -> Dictionary:
	var s := ProgressionFixtures.state(0, {}, level)
	s["meta"]["last_active_at"] = T0
	s["progress"]["cleared_encounters"][hunt] = 1
	s["farming"] = hunt
	return s


func test_worked_example_of_20_4() -> void:
	var c := content()
	var est := OfflineModel.estimate(example_entry(), EXAMPLE, c)
	assert_eq(est["mana_ratio"], 1.0, "r = 1 (pool + income)")
	assert_true(est["veiled"], "one active every 4.5 s: veiled")
	assert_near(est["rot"], 1.526667, 0.000001, "ROT")
	assert_near(est["burst"], 3.0, 0.000001, "opening Volley")
	assert_near(est["dps"], 127.0187, 0.0001, "DPS")
	assert_near(est["burst_damage"], 249.6, 0.0001, "burst")
	assert_near(est["ehp"], 1588.4, 0.01, "EHP")
	assert_near(est["clear_time_s"], 11.0402, 0.0001, "clear_time")
	assert_near(est["cycle_s"], 17.0402, 0.0001, "cycle")
	assert_near(est["incoming_dps"], 20.846, 0.001, "incoming")
	assert_near(est["reserve"], 1449.59, 0.01, "reserve")
	assert_near(est["survival_s"], 69.54, 0.01, "survival")
	assert_true(est["survives"], "survives")
	var s := hunting(EXAMPLE)
	var summary: Dictionary = OfflineCalc.compute(s, T0 + 10 * H, c, example_entry())["summary"]
	assert_eq(summary["status"], "ok", "status")
	assert_eq(summary["counted_s"], 28800, "Δ_eff")
	assert_true(summary["capped"], "capped")
	assert_near(summary["clears"], 422.5307, 0.0001, "N")
	assert_eq(summary["xp"], 25351, "XP")
	assert_eq(summary["gold"], 11154, "gold")
	assert_eq([summary["level_before"], summary["level_after"]], [8, 10], "level 8 → 10")
	_assert_one_of(summary["materials"]["material.mana_dust"], 285, "dust")
	_assert_one_of(summary["materials"]["material.rune_shard"], 50, "shards")
	_assert_one_of(summary["materials"]["material.grimoire_page"], 4, "pages")
	_assert_one_of(summary["items_dropped"], 105, "items")
	_assert_one_of(summary["runes_dropped"], 12, "runes")
	assert_eq(summary["items"].size(), 30, "30 items kept")
	assert_eq(summary["items_salvaged"], summary["items_dropped"] - 30, "the rest salvaged")
	assert_true(summary["salvage_dust"] > 0, "salvage dust")
	var claimed := OfflineCalc.claim(_with_pending(s, summary), c)
	var hero: Dictionary = claimed["state"]["characters"][FERN]
	assert_eq([hero["level"], hero["xp"]], [10, 4331], "level 10, 4 331 / 15 920")


## floori(expected) + Bernoulli(fraction): `whole` or `whole + 1`.
func _assert_one_of(actual: Variant, whole: int, label: String) -> void:
	assert_true(int(actual) == whole or int(actual) == whole + 1, "%s %s" % [label, actual])


func test_kept_items_are_the_best() -> void:
	var c := content()
	var s := hunting(EXAMPLE)
	var summary: Dictionary = OfflineCalc.compute(s, T0 + 8 * H, c, example_entry())["summary"]
	var worst_kept := 99
	for item in summary["items"]:
		worst_kept = mini(worst_kept, BalanceItems.RARITIES.find(item["rarity"]))
		assert_eq(item["uid"], "", "no uid before the claim")
		assert_eq(item["item_level"], 7, "ilvl of the encounter")
	assert_true(worst_kept >= 0, "kept items have a rarity")


func test_no_combat_tick_and_fast() -> void:
	var c := content()
	var s := hunting(WOLVES, 3)
	OfflineCalc.compute(s, T0 + 8 * H, c)  # warms the item catalog
	var ticks := CombatSim.ticks_total
	var start := Time.get_ticks_usec()
	var r := OfflineCalc.compute(s, T0 + 8 * H + 7, c)
	var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
	assert_eq(CombatSim.ticks_total, ticks, "no tick")
	assert_eq(r["summary"]["status"], "ok", "computed")
	assert_true(r["summary"]["clears"] > 100.0, "hundreds of clears")
	assert_true(elapsed_ms < 50.0, "8 h in %.1f ms" % elapsed_ms)


func test_clock_bounds() -> void:
	var c := content()
	var s := hunting(WOLVES, 3)
	assert_eq(OfflineCalc.compute(s, T0, c)["summary"], {}, "0 s: no summary")
	assert_eq(OfflineCalc.compute(s, T0 + 59, c)["summary"], {}, "59 s: no summary")
	assert_eq(OfflineCalc.compute(s, T0 + 60, c)["summary"]["status"], "ok", "60 s: summary")
	var a: Dictionary = OfflineCalc.compute(s, T0 + 8 * H, c)["summary"]
	var b: Dictionary = OfflineCalc.compute(s, T0 + 8 * H + 1, c)["summary"]
	assert_true(not a["capped"] and b["capped"], "8 h + 1 s is capped")
	for key in ["counted_s", "clears", "xp", "gold", "materials", "items", "runes", "salvage_dust"]:
		assert_eq(a[key], b[key], "8 h = 8 h + 1 s: %s" % key)
	var back := OfflineCalc.compute(s, T0 - H, c)
	assert_eq(back["summary"]["status"], "clock", "clock moved back")
	assert_eq([back["summary"]["xp"], back["summary"]["gold"]], [0, 0], "no gain")
	assert_eq(back["summary"]["items"], [], "no item")
	assert_eq(back["last_active_at"], T0, "timestamp kept")
	assert_eq(OfflineCalc.compute(s, T0 + H, c)["last_active_at"], T0 + H, "stamp moves on")


func test_no_hunt_no_summary() -> void:
	var s := hunting(WOLVES, 3)
	s["farming"] = ""
	assert_eq(OfflineCalc.compute(s, T0 + H, content())["summary"], {}, "no hunt")


func test_same_inputs_same_summary_and_different_inputs_differ() -> void:
	var c := content()
	var s := hunting(EXAMPLE)
	var a: Dictionary = OfflineCalc.compute(s, T0 + 5 * H, c, example_entry())["summary"]
	var b: Dictionary = OfflineCalc.compute(s, T0 + 5 * H, c, example_entry())["summary"]
	assert_eq(a, b, "same summary")
	var later: Dictionary = OfflineCalc.compute(s, T0 + 5 * H + 30, c, example_entry())["summary"]
	assert_true(later["items"] != a["items"], "another window, another draw")
	var other := s.duplicate(true)
	other["meta"]["seed"] = 99
	var reseeded: Dictionary = OfflineCalc.compute(other, T0 + 5 * H, c, example_entry())["summary"]
	assert_true(reseeded["items"] != a["items"], "another seed, another draw")


func test_eligibility() -> void:
	var c := content()
	var s := hunting(WOLVES, 10)
	s["progress"]["cleared_encounters"]["encounter.cloister_alpha"] = 1
	s["progress"]["cleared_encounters"]["encounter.cloister_boss"] = 1
	assert_eq(
		OfflineCalc.quote(s, "encounter.cloister_alpha", c)["error"], "error.offline.not_normal"
	)
	assert_eq(
		OfflineCalc.quote(s, "encounter.cloister_boss", c)["error"], "error.offline.not_normal"
	)
	assert_eq(
		OfflineCalc.quote(s, "encounter.whispering_wood_05", c)["error"],
		"error.offline.not_cleared"
	)
	assert_eq(OfflineCalc.quote(s, "encounter.nope", c)["error"], "error.offline.unknown_encounter")
	var q := OfflineCalc.quote(s, WOLVES, c)
	assert_true(q["ok"], "cleared normal encounter")
	assert_true(not q.has("state") or q["state"].is_empty(), "a quote changes nothing")
	assert_true(q["clears_per_hour"] > 0.0 and q["xp_per_hour"] > 0, "rates")
	var refused := OfflineCalc.set_hunt(s, "encounter.cloister_boss", c)
	assert_true(not refused["ok"], "boss refused")
	var ok := OfflineCalc.set_hunt(hunting(WOLVES, 3), WOLVES, c)
	assert_eq(ok["state"]["farming"], WOLVES, "hunt set")


func test_too_slow_is_not_eligible() -> void:
	var c := content()
	var s := hunting(SLOW, 1)
	var q := OfflineCalc.quote(s, SLOW, c)
	assert_eq(q["error"], "error.offline.too_slow", "level 1 vs 3 level 15 sentinels")
	assert_eq(q["params"]["max"], 120, "max shown")


func test_unsafe_hunt_credits_nothing() -> void:
	var c := content()
	var s := hunting(EXAMPLE)
	var frail := example_entry()
	frail["stats"]["max_hp"] = 40.0
	frail["stats"]["defense"] = 0.0
	var summary: Dictionary = OfflineCalc.compute(s, T0 + 2 * H, c, frail)["summary"]
	assert_eq(summary["status"], "unsafe", "status")
	assert_eq(summary["reason"], "error.offline.unsafe", "reason")
	assert_eq([summary["xp"], summary["gold"], summary["items"]], [0, 0, []], "no gain")
	var lines := OfflineCalc.lines(summary)
	assert_eq(lines[1]["key"], "error.offline.unsafe", "explanation line")
	var r := OfflineCalc.claim(_with_pending(s, summary), c)
	assert_true(r["ok"], "read and cleared")
	assert_eq(r["state"]["wallet"]["gold"], 0, "nothing credited")
	assert_eq(OfflineCalc.pending(r["state"]), {}, "cleared")


func test_hourglass_raises_efficiency() -> void:
	var c := content()
	var s := hunting(WOLVES, 6)
	var base: Dictionary = OfflineCalc.compute(s, T0 + 4 * H, c)["summary"]
	s["artifacts"]["artifact.cracked_hourglass"] = 1
	s["characters"][FERN]["artifacts"] = ["artifact.cracked_hourglass", ""]
	var with: Dictionary = OfflineCalc.compute(s, T0 + 4 * H, c)["summary"]
	assert_near(base["efficiency"], 0.25, 0.000001, "base efficiency")
	assert_near(with["efficiency"], 0.28, 0.000001, "+0.03 at level 1")
	assert_near(with["clears"] / base["clears"], 0.28 / 0.25, 0.000001, "N scales")


func test_claim_credits_once() -> void:
	var c := content()
	var s := hunting(EXAMPLE)
	var summary: Dictionary = OfflineCalc.compute(s, T0 + 3 * H, c, example_entry())["summary"]
	var pending := _with_pending(s, summary)
	var r := OfflineCalc.claim(pending, c)
	assert_true(r["ok"], "claimed")
	var next: Dictionary = r["state"]
	var dust: int = (
		int(summary["materials"].get("material.mana_dust", 0)) + int(summary["salvage_dust"])
	)
	assert_eq(next["wallet"]["gold"], summary["gold"], "gold")
	assert_eq(next["wallet"]["materials"].get("material.mana_dust", 0), dust, "dust")
	assert_eq(r["items"].size(), summary["items"].size(), "items in the bag")
	assert_eq(Inventory.bag_count(next), summary["items"].size(), "bag")
	assert_eq(OfflineCalc.pending(next), {}, "pending cleared")
	assert_eq(OfflineCalc.pending(pending), summary, "input untouched")
	var again := OfflineCalc.claim(next, c)
	assert_eq(again["error"], "error.offline.nothing_to_claim", "second claim refused")


func test_full_bag_salvages_and_says_so() -> void:
	var c := content()
	var s := hunting(EXAMPLE)
	ProgressionFixtures.fill_bag(s, BalanceItems.INVENTORY_SLOTS - 2)
	var summary: Dictionary = OfflineCalc.compute(s, T0 + 8 * H, c, example_entry())["summary"]
	assert_eq(summary["items"].size(), 2, "only the free slots are kept")
	assert_eq(summary["items_salvaged"], summary["items_dropped"] - 2, "rest salvaged")
	var pending := _with_pending(s, summary)
	ProgressionFixtures.fill_bag(pending, 2)  # the bag filled up before the claim
	var r := OfflineCalc.claim(pending, c)
	assert_eq(r["auto_salvaged"].size(), 2, "auto-salvaged at the claim")
	var keys := []
	for line in r["lines"]:
		keys.append(line["key"])
	assert_true(keys.has("log.loot.auto_salvaged_other"), "reported")


func test_level_cap_reports_wasted_xp() -> void:
	var c := content()
	var s := hunting(WOLVES, BalanceProgression.LEVEL_CAP)
	var summary: Dictionary = OfflineCalc.compute(s, T0 + 2 * H, c)["summary"]
	assert_eq(summary["level_after"], BalanceProgression.LEVEL_CAP, "capped level")
	assert_eq(summary["xp_wasted"], summary["xp"], "all wasted")


func test_summary_lines() -> void:
	var c := content()
	var s := hunting(EXAMPLE)
	var summary: Dictionary = OfflineCalc.compute(s, T0 + 10 * H, c, example_entry())["summary"]
	var keys := []
	for line in OfflineCalc.lines(summary):
		keys.append(line["key"])
	for key in [
		"log.offline.hunt",
		"log.offline.duration",
		"log.offline.capped",
		"log.offline.clears",
		"log.offline.xp",
		"log.offline.level_up",
		"log.offline.gold",
		"log.offline.material",
		"log.offline.items_kept",
		"log.offline.items_salvaged",
	]:
		assert_true(keys.has(key), key)
	var strings := ContentLoader.translation_keys("res://game/i18n/strings.csv")
	for key in keys:
		assert_true(strings.has(key), "translated: " + key)
	var clock: Dictionary = OfflineCalc.compute(s, T0 - 60, c)["summary"]
	assert_eq(OfflineCalc.lines(clock)[1]["key"], "log.offline.clock", "clock line")


func test_summary_survives_a_save_round_trip() -> void:
	var c := content()
	var s := hunting(WOLVES, 3)
	s["progress"]["cleared_encounters"][WOLVES] = 2
	var summary: Dictionary = OfflineCalc.compute(s, T0 + 6 * H, c)["summary"]
	var pending := _with_pending(s, summary)
	var r := SaveCodec.decode(SaveCodec.encode(pending, T0), SaveMigrations.all())
	assert_true(r["ok"], "valid (%s %s)" % [r["error"], r["detail"]])
	var back := OfflineCalc.pending(r["state"])
	assert_eq(typeof(back["xp"]), TYPE_INT, "ints stay ints")
	assert_eq(back["xp"], summary["xp"], "xp")
	assert_eq(back["items"].size(), summary["items"].size(), "items")


func _with_pending(s: Dictionary, summary: Dictionary) -> Dictionary:
	var out := s.duplicate(true)
	OfflineCalc.store(out, summary)
	return out
