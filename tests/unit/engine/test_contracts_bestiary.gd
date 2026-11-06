extends TestCase
## Daily contracts (docs/content/contracts.md) and the bestiary (ROADMAP 6.5,
## bestiary_discoveries.md §1). Offline victories count for neither.

const F := preload("res://tests/unit/engine/story_fixtures.gd")
const DAY := 86400
## Local midnight of a day (UTC+1), well inside the day.
const NOON := 1_800_000_000 - (1_800_000_000 % DAY) + DAY / 2
const TZ := 3600


func _all_main_done(level: int = 12) -> Dictionary:
	var s := F.state(level)
	for q in ["quest.main_01", "quest.main_02", "quest.main_03"]:
		F.turned_in(s, q)
	return s


func _tier(id: String) -> String:
	return F.content()[id]["tier"]


func test_rewards_follow_the_formula() -> void:
	assert_eq(BalanceStory.contract_reward("M", 1), {"gold": 100, "dust": 6, "shards": 2}, "L1 M")
	assert_eq(BalanceStory.contract_reward("M", 12)["gold"], 320, "L12 M")
	assert_eq(BalanceStory.contract_reward("L", 20)["gold"], 720, "L20 L")
	assert_eq(BalanceStory.contract_reward("S", 1), {"gold": 75, "dust": 4, "shards": 1}, "S")


func test_day_index_uses_local_midnight() -> void:
	var midnight_utc := 1_800_000_000 - (1_800_000_000 % DAY)
	assert_eq(BalanceStory.day_index(midnight_utc - 1, 0), midnight_utc / DAY - 1, "before")
	assert_eq(BalanceStory.day_index(midnight_utc - 1, TZ), midnight_utc / DAY, "UTC+1 is past")


func test_first_day_rolls_the_two_eligible_contracts() -> void:
	var s := F.state()
	var events := []
	Contracts.refresh(s, NOON, TZ, F.content(), events)
	var ids: Array = Contracts.view(s, F.content()).map(
		func(o: Dictionary) -> String: return o["id"]
	)
	ids.sort()
	assert_eq(ids, ["quest.daily_wolves", "quest.daily_wood_patrol"], "2 at the start")
	assert_eq(events[events.size() - 1]["type"], "contracts_rolled", "event")


func test_roll_is_reproducible_and_never_two_long_ones() -> void:
	var c := F.content()
	var s := _all_main_done()
	var pool := Contracts.eligible(s, c)
	assert_eq(pool.size(), 9, "every contract after main_03")
	assert_eq(Contracts.roll(5, 20000, pool, c), Contracts.roll(5, 20000, pool, c), "same seed+day")
	var seen := {}
	for day in range(20000, 20060):
		var picked := Contracts.roll(5, day, pool, c)
		assert_eq(picked.size(), 3, "3 a day")
		var longs := picked.filter(func(id: String) -> bool: return _tier(id) == "L")
		assert_true(longs.size() <= 1, "day %d: %s" % [day, picked])
		var unique := {}
		for id in picked:
			unique[id] = true
			seen[id] = true
		assert_eq(unique.size(), 3, "no duplicate on day %d" % day)
	assert_eq(seen.size(), pool.size(), "each eligible contract shows up in 60 days")


func test_new_day_claims_completed_and_drops_unfinished() -> void:
	var s := F.state(12)
	var c := F.content()
	Contracts.refresh(s, NOON, TZ, c, [])
	var offers: Array = s["progress"]["contracts"]["offers"]
	offers[0]["state"] = "completed"
	var reward: Dictionary = offers[0]["reward"].duplicate()
	var gold := int(s["wallet"]["gold"])
	var events := []
	Contracts.refresh(s, NOON - 3600, TZ, c, events)
	assert_eq(events.size(), 0, "same day: nothing")
	Contracts.refresh(s, NOON - 3 * DAY, TZ, c, events)
	assert_eq(events.size(), 0, "clock moved back: keep")
	Contracts.refresh(s, NOON + 4 * DAY, TZ, c, events)
	assert_eq(events[0]["type"], "contracts_auto_claimed", "auto claim")
	assert_eq(int(s["wallet"]["gold"]), gold + int(reward["gold"]), "gold credited")
	assert_eq(events.size(), 2, "one single new roll after 4 days")
	for o in s["progress"]["contracts"]["offers"]:
		assert_eq(o["state"], "active", "fresh offers")


func test_fights_fill_contracts_then_claim_once() -> void:
	var s := F.state(3)
	var c := F.content()
	s["progress"]["contracts"] = {
		"day_index": 1,
		"offers":
		[
			{
				"id": "quest.daily_wood_patrol",
				"count": 7,
				"state": "active",
				"reward": {"gold": 90, "dust": 4, "shards": 1}
			},
			{
				"id": "quest.daily_interrupts",
				"count": 0,
				"state": "active",
				"reward": {"gold": 1, "dust": 1, "shards": 1}
			},
		]
	}
	var cut := F.fight(
		"encounter.lantern_mire_01", true, null, {}, {"interrupts": {"character.fern": 3}}
	)
	s = F.play(s, F.fight("encounter.whispering_wood_02"))
	s = F.play(s, cut)
	var offers: Array = s["progress"]["contracts"]["offers"]
	assert_eq(offers[0]["state"], "completed", "8/8 patrols")
	assert_eq(offers[1]["count"], 3, "3 interrupts by Fern")
	assert_true(Contracts.has_claimable(s), "journal icon")
	var r := Contracts.claim(s, "quest.daily_wood_patrol")
	assert_true(r["ok"], "claimed")
	assert_eq(int(r["state"]["wallet"]["gold"]) - int(s["wallet"]["gold"]), 90, "+90 gold")
	assert_eq(
		Contracts.claim(r["state"], "quest.daily_wood_patrol")["error"],
		"error.contract.not_completed",
		"once"
	)


func test_frozen_contract_counts_fern_only() -> void:
	var o: Dictionary = F.content()["quest.daily_frozen"]["objectives"][0]
	var fight := F.fight(
		"encounter.lantern_mire_01",
		true,
		null,
		{},
		{"statuses": {"status.frozen": {"character.fern": 2, "enemy.mist_wolf": 1}}}
	)
	assert_eq(QuestRules.gain(o, fight, F.content()), 2, "Fern's freezes")


func test_bestiary_tiers_and_thresholds() -> void:
	var c := F.content()
	for pair in [[0, 0], [1, 1], [4, 1], [5, 2], [24, 2], [25, 3]]:
		var s := F.state()
		s["progress"]["bestiary"]["enemy.mist_wolf"] = pair[0]
		assert_eq(Bestiary.tier(s, "enemy.mist_wolf", c), pair[1], "%d wolves" % pair[0])
	var s := F.state()
	s["progress"]["bestiary"]["enemy.mist_wolf_alpha"] = 3
	s["progress"]["bestiary"]["enemy.morvaine"] = 2
	assert_eq(Bestiary.tier(s, "enemy.mist_wolf_alpha", c), 2, "alpha 1/3/10")
	assert_eq(Bestiary.tier(s, "enemy.morvaine", c), 2, "boss 1/2/5")


func test_bestiary_counts_summons_and_reports_tiers() -> void:
	var s := F.state(11)
	var fight := F.fight(
		"encounter.cloister_alpha", true, {"enemy.mist_wolf_alpha": 1, "enemy.mist_wolf": 2}
	)
	var r := StoryEvents.apply_fight(s, fight, F.content())
	s = r["state"]
	assert_eq(s["progress"]["bestiary"]["enemy.mist_wolf_alpha"], 1, "+1 alpha")
	assert_eq(s["progress"]["bestiary"]["enemy.mist_wolf"], 2, "+2 wolves (howl)")
	var unlocked: Array = r["summary"]["events"].filter(
		func(e: Dictionary) -> bool: return e["type"] == "bestiary_tier_unlocked"
	)
	assert_eq(unlocked.size(), 2, "two new pages")
	var view := Bestiary.view(s, F.content())
	assert_eq(view[0]["enemy_id"], "enemy.mist_wolf", "sorted")
	assert_eq(view[0]["next"], 5, "next tier at 5")


func test_met_enemy_appears_at_zero_after_a_defeat() -> void:
	var s := F.play(F.state(), F.fight("encounter.lantern_mire_01", false))
	assert_eq(s["progress"]["bestiary"].get("enemy.wandering_lantern", -1), 0, "met, not beaten")


func test_offline_claim_counts_for_no_quest_contract_or_bestiary() -> void:
	var s := F.state(3)
	s["progress"]["cleared_encounters"]["encounter.whispering_wood_02"] = 1
	s["farming"] = "encounter.whispering_wood_02"
	Contracts.refresh(s, NOON, TZ, F.content(), [])
	s["meta"]["last_active_at"] = F.NOW
	var r := OfflineCalc.compute(s, F.NOW + 4 * 3600, F.content())
	assert_true(r["summary"].get("clears", 0) > 0, "offline wins")
	OfflineCalc.store(s, r["summary"])
	var claimed := OfflineCalc.claim(s, F.content())
	assert_true(claimed["ok"], "claimed")
	var after: Dictionary = claimed["state"]
	assert_eq(after["progress"]["bestiary"], s["progress"]["bestiary"], "bestiary unchanged")
	assert_eq(after["progress"]["quests"], s["progress"]["quests"], "quests unchanged")
	assert_eq(after["progress"]["contracts"], s["progress"]["contracts"], "contracts unchanged")
