extends TestCase
## Quests (ROADMAP 6.6, docs/content/quests.md): each objective advances on
## its event, steps gate, rewards are credited once, states survive a reload.

const F := preload("res://tests/unit/engine/story_fixtures.gd")
const M1 := "quest.main_01"
const M2 := "quest.main_02"
const WOOD_1 := "encounter.whispering_wood_01"


func _state_of(s: Dictionary, id: String) -> String:
	return QuestRules.state_of(s, id, F.content())


func _count(s: Dictionary, id: String, objective: String) -> int:
	return int(s["progress"]["quests"][id]["counts"].get(objective, 0))


func test_main_01_is_active_from_the_new_game() -> void:
	var s := F.state()
	assert_eq(_state_of(s, M1), "active", "main_01 active")
	assert_eq(_state_of(s, M2), "locked", "main_02 waits for main_01")
	assert_eq(QuestRules.tracked(s, F.content()), M1, "HUD follows main_01")
	assert_eq(StateSchema.validate(s)["errors"].size(), 0, "valid state")


func test_main_01_wood_fights_and_odile_in_any_order() -> void:
	var s := F.state(2)
	s = F.play(s, F.fight(WOOD_1))
	s = F.play(s, F.fight(WOOD_1, false))
	assert_eq(_count(s, M1, "clear_wood"), 1, "one victory, the defeat does not count")
	s = F.play(s, F.fight("encounter.whispering_wood_03"))
	assert_eq(_count(s, M1, "clear_wood"), 2, "any pack of the Wood, replayed or not")
	var talk := F.talk(s, "npc.odile")
	assert_eq(talk["dialogue"], "dialogue.odile_intro", "intro first")
	s = talk["state"]
	assert_eq(_count(s, M1, "meet_odile"), 1, "met Odile")
	assert_eq(_state_of(s, M1), "active", "still one pack to go")
	assert_eq(
		NpcRules.select(s, "npc.odile", F.content())["dialogue"], "dialogue.odile_main01_wait"
	)
	s = F.play(s, F.fight(WOOD_1))
	assert_eq(_state_of(s, M1), "completed", "objectives met")
	assert_eq(NpcRules.marker(s, "npc.odile", F.content()), "turn_in", "gold diamond")
	s = F.reloaded(s)
	assert_eq(_state_of(s, M1), "completed", "survives a reload")
	var done := F.talk(s, "npc.odile")
	assert_eq(done["dialogue"], "dialogue.odile_main01_done", "hand-in dialogue")
	assert_eq(done["turned_in"], M1, "turned in")
	s = done["state"]
	var hero: Dictionary = s["characters"][F.FERN]
	var xp := BalanceStory.quest_xp("main", 3)
	assert_eq(done["rewards"]["xp"], xp, "QUEST_XP_MAIN × xp_to_next(3)")
	assert_eq(s["wallet"]["gold"], 100, "100 gold")
	assert_eq(s["wallet"]["materials"].get("material.grimoire_page", 0), 1, "1 page")
	assert_true(hero["level"] >= 3, "XP credited (level %d)" % hero["level"])
	assert_eq(WorldRules.status("location.lantern_mire", s, F.content()), "available", "mire opens")
	assert_eq(_state_of(s, M2), "available", "main_02 offered by Maëlle")
	assert_eq(NpcRules.marker(s, "npc.maelle", F.content()), "offer", "offer marker")
	var again := QuestRules.turn_in(s, M1, F.content())
	assert_eq(again["error"], "error.quest.not_completed", "rewards only once")


func test_talk_that_completes_a_quest_chains_the_hand_in() -> void:
	var s := F.state(2)
	for i in 3:
		s = F.play(s, F.fight(WOOD_1))
	var r := F.talk(s, "npc.odile")
	assert_eq(r["dialogue"], "dialogue.odile_intro", "intro")
	assert_eq(r["next_dialogue"], "dialogue.odile_main01_done", "hand-in follows")


func test_steps_gate_later_objectives() -> void:
	var s := F.state(5)
	F.turned_in(s, M1)
	s = QuestRules.accept(s, M2, F.content())["state"]
	s = F.play(s, F.fight("encounter.lantern_mire_01"))
	assert_eq(_count(s, M2, "clear_mire"), 0, "step 2 waits for reach_mire")
	var events := []
	WorldRules.visit("location.lantern_mire", s, F.content())
	StoryEvents.visited(s, "location.lantern_mire", F.content(), events)
	assert_eq(s["progress"]["quests"][M2]["step"], 2, "step 2")
	assert_true(events.any(func(e: Dictionary) -> bool: return e["type"] == "quest_step_advanced"))
	s = F.play(s, F.fight("encounter.lantern_mire_02"))
	assert_eq(_count(s, M2, "clear_mire"), 1, "counts now")
	s = F.reloaded(s)
	assert_eq(s["progress"]["quests"][M2]["step"], 2, "step saved")
	assert_eq(_count(s, M2, "clear_mire"), 1, "counter saved")


func test_dungeon_rooms_do_not_count_for_their_location() -> void:
	var o := {"event": "EncounterCompleted", "target": "location.watch_ruins", "step": 1}
	var room := F.fight("encounter.cloister_vestibule")
	assert_eq(QuestRules.gain(o, room, F.content()), 0, "vestibule is a dungeon room")
	assert_eq(QuestRules.gain(o, F.fight("encounter.watch_ruins_02"), F.content()), 1, "field")


func test_enemy_kills_and_the_key() -> void:
	var s := F.state(8)
	F.turned_in(s, M1)
	F.turned_in(s, M2)
	s["wallet"]["materials"]["material.cloister_key"] = 1
	s = QuestRules.accept(s, "quest.main_03", F.content())["state"]
	assert_eq(_count(s, "quest.main_03", "key"), 1, "key already owned counts at once")
	s = F.play(s, F.fight("encounter.watch_ruins_01"))
	s = F.play(s, F.fight("encounter.watch_ruins_02", false, {"enemy.stone_sentinel": 1}))
	assert_eq(_count(s, "quest.main_03", "sentinels"), 2, "kills count, even in a lost fight")
	s = F.play(s, F.fight("encounter.watch_ruins_04"))
	s = F.play(s, F.fight("encounter.watch_ruins_05"))
	assert_eq(_state_of(s, "quest.main_03"), "completed", "4 sentinels and the key")


func test_key_from_the_first_clear_of_the_tower_guardians() -> void:
	var s := F.state(9)
	F.turned_in(s, M1)
	F.turned_in(s, M2)
	s = QuestRules.accept(s, "quest.main_03", F.content())["state"]
	s = F.play(s, F.fight("encounter.watch_ruins_05", true, null, {"material.cloister_key": 1}))
	assert_eq(_count(s, "quest.main_03", "key"), 1, "key collected")


func test_delivery_counts_what_is_held_and_takes_it_at_hand_in() -> void:
	var s := F.state(6)
	assert_eq(_state_of(s, "quest.side_clockmaker"), "available", "level 6")
	assert_eq(
		NpcRules.select(s, "npc.tobias", F.content())["dialogue"], "dialogue.tobias_offer", "offer"
	)
	s["wallet"]["materials"]["material.rune_shard"] = 12
	s = F.talk(s, "npc.tobias")["state"]
	assert_eq(_state_of(s, "quest.side_clockmaker"), "completed", "12 held >= 10")
	s["wallet"]["materials"]["material.rune_shard"] = 4
	s = F.reloaded(s)
	var events := []
	QuestRules.refresh_all(s, F.content(), events)
	assert_eq(_state_of(s, "quest.side_clockmaker"), "active", "spent shards reopen it")
	assert_eq(_count(s, "quest.side_clockmaker", "shards"), 4, "4/10")
	s["wallet"]["materials"]["material.rune_shard"] = 11
	var r := F.talk(s, "npc.tobias")
	assert_eq(r["turned_in"], "quest.side_clockmaker", "handed in")
	s = r["state"]
	assert_eq(s["wallet"]["materials"]["material.rune_shard"], 1, "10 taken")
	assert_eq(s["artifacts"].get("artifact.cracked_hourglass", 0), 1, "hourglass")
	assert_true(s["progress"]["unlocks"].has("artifact_slot_1"), "artifact slot 1 token")
	assert_true(ArtifactRules.slot_open(s, F.FERN, 0), "slot 1 opens at hand-in")


func test_tobias_before_level_6() -> void:
	var s := F.state(3)
	assert_eq(
		NpcRules.select(s, "npc.tobias", F.content())["dialogue"], "dialogue.tobias_early", "early"
	)
	assert_eq(F.talk(s, "npc.tobias")["offered"], "", "nothing offered")


func test_statue_found_before_the_offer() -> void:
	var s := F.state(3)
	F.turned_in(s, M1)
	s["progress"]["discoveries"].append("discovery.moss_statue")
	var pick := NpcRules.select(s, "npc.aubelin_merchant", F.content())
	assert_eq(pick["dialogue"], "dialogue.odette_statue_offer_found", "dedicated line")
	var r := NpcRules.finish(s, "npc.aubelin_merchant", pick["dialogue"], F.content())
	assert_eq(_state_of(r["state"], "quest.side_statue"), "completed", "filled at once")
	assert_eq(r["next_dialogue"], "dialogue.odette_statue_done", "hand-in follows")
	var done := F.talk(r["state"], "npc.aubelin_merchant")
	assert_eq(done["turned_in"], "quest.side_statue", "turned in")
	assert_true(done["rewards"]["memory"], "memory text in the journal")


func test_main_04_ends_with_the_epilogue_at_odile() -> void:
	var s := F.state(12)
	for q in [M1, M2, "quest.main_03"]:
		F.turned_in(s, q)
	assert_eq(
		NpcRules.select(s, "npc.odile", F.content())["dialogue"], "dialogue.odile_main04_offer"
	)
	s = F.talk(s, "npc.odile")["state"]
	var entered := DungeonRun.enter(s, "dungeon.silent_dial_cloister", F.content())
	s = entered["state"]
	StoryEvents.visited(s, "dungeon.silent_dial_cloister", F.content(), [])
	assert_eq(s["progress"]["quests"]["quest.main_04"]["step"], 2, "entered")
	s = F.play(s, F.fight("encounter.cloister_boss"))
	assert_eq(s["progress"]["quests"]["quest.main_04"]["step"], 3, "Morvaine beaten")
	assert_eq(NpcRules.marker(s, "npc.odile", F.content()), "turn_in", "go back to Odile")
	s = F.reloaded(s)
	var r := F.talk(s, "npc.odile")
	assert_eq(r["dialogue"], "dialogue.odile_epilogue", "epilogue")
	assert_eq(r["turned_in"], "quest.main_04", "handed in by the same talk")
	assert_eq(
		NpcRules.select(r["state"], "npc.odile", F.content())["dialogue"], "dialogue.odile_after"
	)


func test_rewards_of_main_02_give_the_frost_rune() -> void:
	var s := F.state(6)
	F.turned_in(s, M1)
	s = QuestRules.accept(s, M2, F.content())["state"]
	s["progress"]["quests"][M2] = {"state": "completed", "step": 2, "counts": {}, "order": 1}
	s["world"]["discovered_locations"].append("location.lantern_mire")
	s["progress"]["discoveries"].append("discovery.ferryman_journal")
	s["progress"]["quests"][M2]["counts"]["clear_mire"] = 4
	var r := QuestRules.turn_in(s, M2, F.content())
	assert_true(r["ok"], "turned in (%s)" % r["error"])
	assert_eq(Inventory.rune_count(r["state"], "rune.frost", 1), 1, "frost rune tier 1")
	assert_true(
		r["state"]["world"]["revealed_locations"].has("location.watch_ruins"), "ruins revealed"
	)


func test_quest_log_lists_started_quests() -> void:
	var s := F.state(6)
	var log := QuestRules.log_view(s, F.content())
	assert_eq(log.size(), 1, "only main_01")
	assert_eq(log[0]["objectives"].size(), 2, "two objectives")
	assert_eq(log[0]["objectives"][0]["key"], "quest.main_01.objective_clear_wood", "text key")
	s = F.talk(s, "npc.tobias")["state"]
	assert_eq(QuestRules.log_view(s, F.content()).size(), 2, "clockmaker accepted")
	assert_eq(QuestRules.tracked(s, F.content()), M1, "main first")


## GAME_BALANCE §21.2 (ROADMAP 6.7): quests handed in before the boss give
## ~30 % of the XP needed to reach level 12 (QUEST_XP_MAIN raised for it).
func test_quests_give_about_30_percent_of_the_xp_to_level_12() -> void:
	var c := F.content()
	var to_12 := 0
	for level in range(1, 12):
		to_12 += BalanceProgression.xp_to_next(level)
	assert_eq(to_12, 72940, "cumulative XP to level 12")
	var quests := 0
	for id in c:
		var q: Dictionary = c[id]
		if q.get("_type", "") == "quest" and q["kind"] != "daily" and int(q["level"]) < 12:
			quests += BalanceStory.quest_xp(q["kind"], int(q["level"]))
	var share := float(quests) / float(to_12)
	assert_true(share >= 0.27 and share <= 0.33, "quest share %.3f (%d XP)" % [share, quests])
