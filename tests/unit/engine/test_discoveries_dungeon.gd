extends TestCase
## Discoveries lift the fog and count per place (ROADMAP 6.5); herbs, chests;
## the dungeon run: doors, fountain, campfire, defeat, shortcut, fallback.

const F := preload("res://tests/unit/engine/story_fixtures.gd")
const CLOISTER := "dungeon.silent_dial_cloister"


func _take(s: Dictionary, id: String) -> Dictionary:
	return Discoveries.take(s, id, F.content())


func test_birch_vista_gives_xp_lifts_the_fog_and_counts() -> void:
	var s := F.state(1)
	assert_eq(
		WorldRules.status("location.watch_ruins", s, F.content()), "hidden", "Ruins under the fog"
	)
	var r := _take(s, "discovery.dead_birch_vista")
	assert_true(r["ok"], "found")
	assert_eq(r["event"]["xp"], 70, "0.1 × xp_to_next(3)")
	s = F.reloaded(r["state"])
	assert_eq(int(s["characters"][F.FERN]["xp"]) + 40, 70 + 0, "70 XP credited (40 to level 2)")
	assert_eq(
		WorldRules.status("location.watch_ruins", s, F.content()), "locked", "revealed, locked"
	)
	assert_eq(
		Discoveries.counts(s, "location.whispering_wood", F.content()),
		{"found": 1, "total": 2},
		"Découvertes 1/2"
	)
	var discs := Discoveries.fog_discs(s, F.content())
	assert_eq(discs.size(), 1, "one hole in the veil")
	assert_eq(discs[0]["map_pos"], [0.24, 0.36], "at the birch")
	assert_eq(_take(s, "discovery.dead_birch_vista")["error"], "error.discovery.found", "once")


func test_journal_completes_the_main_02_objective() -> void:
	var s := F.state(6)
	F.turned_in(s, "quest.main_01")
	s = QuestRules.accept(s, "quest.main_02", F.content())["state"]
	WorldRules.visit("location.lantern_mire", s, F.content())
	StoryEvents.visited(s, "location.lantern_mire", F.content(), [])
	s = _take(s, "discovery.ferryman_journal")["state"]
	StoryEvents.feed(
		s,
		{"type": "discovery_found", "discovery_id": "discovery.ferryman_journal"},
		F.content(),
		[]
	)
	assert_eq(s["progress"]["quests"]["quest.main_02"]["counts"]["find_journal"], 1, "journal")


func test_herbs_only_while_the_quest_runs_and_never_twice() -> void:
	var herb := "discovery.mist_herb_wood_01"
	var s := F.state(3)
	F.turned_in(s, "quest.main_01")
	assert_true(not Discoveries.visible(s, herb, F.content()), "hidden without the quest")
	assert_eq(_take(s, herb)["error"], "error.discovery.unavailable", "cannot pick")
	s = QuestRules.accept(s, "quest.side_herbalist", F.content())["state"]
	assert_true(Discoveries.visible(s, herb, F.content()), "shown with the quest")
	var r := _take(s, herb)
	assert_eq(r["state"]["wallet"]["materials"]["material.mist_herb"], 1, "one herb")
	assert_eq(r["event"]["xp"], 0, "no XP")
	assert_eq(r["event"]["counted"], false, "not in Découvertes n/2")
	s = F.reloaded(r["state"])
	assert_eq(_take(s, herb)["error"], "error.discovery.found", "gone after a reload")
	var listed: Array = Discoveries.in_place(s, "location.whispering_wood", F.content())
	assert_true(listed.any(func(d: Dictionary) -> bool: return d["id"] == herb and d["found"]))


func test_chest_opens_once_with_seeded_loot() -> void:
	var s := F.state(3)
	var a := _take(s, "discovery.wood_chest")
	var b := _take(s, "discovery.wood_chest")
	assert_true(a["ok"], "opened")
	assert_eq(a["event"]["gold"], b["event"]["gold"], "same seed, same gold")
	assert_eq(a["state"]["inventory"], b["state"]["inventory"], "same item")
	assert_true(a["event"]["gold"] > 0, "gold")
	assert_eq(a["event"]["materials"]["material.grimoire_page"], 1, "a page")
	assert_eq(a["state"]["inventory"].size(), 1, "one item")
	assert_eq(_take(a["state"], "discovery.wood_chest")["error"], "error.discovery.found", "once")
	var other := Discoveries.take(F.state(3, 78), "discovery.wood_chest", F.content())
	assert_true(other["ok"], "another game opens its own chest")


func _in_dungeon() -> Dictionary:
	var s := F.state(11)
	for q in ["quest.main_01", "quest.main_02", "quest.main_03"]:
		F.turned_in(s, q)
	var r := DungeonRun.enter(s, CLOISTER, F.content())
	assert_true(r["ok"], "entered (%s)" % r["error"])
	return r["state"]


func _move(s: Dictionary, room: String) -> Dictionary:
	var r := DungeonRun.move_to(s, room, F.content())
	assert_true(r["ok"], "into %s (%s)" % [room, r["error"]])
	return r["state"]


func test_dungeon_is_locked_before_main_03() -> void:
	var r := DungeonRun.enter(F.state(11), CLOISTER, F.content())
	assert_eq(r["error"], "error.dungeon.locked", "locked")
	assert_eq(r["params"], {"quest": "quest.main_03.name"}, "reason names the quest")


func test_doors_open_room_by_room() -> void:
	var s := _in_dungeon()
	var c := F.content()
	var d: Dictionary = c[CLOISTER]
	assert_eq(DungeonRun.accessible(s, d), ["vestibule"], "only the vestibule")
	assert_eq(DungeonRun.move_to(s, "gallery", c)["error"], "error.dungeon.room_closed", "grate")
	s = F.play(s, F.fight("encounter.cloister_vestibule"))
	assert_eq(DungeonRun.accessible(s, d), ["vestibule", "gallery"], "gallery opens")
	var vitals := DungeonRun.vitals(s)
	assert_eq(vitals["hp_pct"], 0.6, "HP carried to the next room")
	s = F.play(s, F.fight("encounter.cloister_gallery"))
	assert_eq(
		DungeonRun.accessible(s, d), ["vestibule", "gallery", "fountain", "courtyard"], "rest open"
	)
	s = _move(s, "fountain")
	var drink := DungeonRun.use_fountain(s, c)
	assert_near(drink["vitals"]["hp_pct"], 0.9, 1e-6, "+30 % of max HP")
	assert_eq(
		DungeonRun.use_fountain(drink["state"], c)["error"], "error.dungeon.fountain_used", "once"
	)
	s = drink["state"]
	assert_eq(
		Discoveries.take(s, "discovery.cloister_chest", c)["error"],
		"error.discovery.room_not_cleared",
		"chest after the courtyard"
	)
	s = F.play(s, F.fight("encounter.cloister_courtyard"))
	assert_true(Discoveries.take(s, "discovery.cloister_chest", c)["ok"], "chest opens")
	s = F.play(s, F.fight("encounter.cloister_alpha"))
	s = _move(s, "campfire")
	assert_eq(DungeonRun.run(s)["checkpoint"], "campfire", "checkpoint")
	var rested := DungeonRun.rest(s, c)
	assert_eq(rested["vitals"]["hp_pct"], 1.0, "full at the campfire")
	s = F.reloaded(rested["state"])
	StoryEvents.on_load(s, c)
	assert_eq(DungeonRun.run(s)["room"], "campfire", "reload: back at the campfire")
	assert_eq(DungeonRun.run(s)["cleared_rooms"].size(), 4, "rooms kept")


func test_defeat_sends_back_to_the_checkpoint_rooms_kept() -> void:
	var s := _in_dungeon()
	s = F.play(s, F.fight("encounter.cloister_vestibule"))
	s = F.play(s, F.fight("encounter.cloister_gallery"))
	s = F.play(s, F.fight("encounter.cloister_courtyard", false))
	var run := DungeonRun.run(s)
	assert_eq(run["room"], "vestibule", "back at the entrance")
	assert_eq(run["vitals"]["hp_pct"], 1.0, "full HP")
	assert_eq(run["cleared_rooms"], ["vestibule", "gallery"], "won rooms stay won")


func test_leaving_resets_and_the_shortcut_opens_after_the_boss() -> void:
	var s := _in_dungeon()
	var c := F.content()
	s = F.play(s, F.fight("encounter.cloister_vestibule"))
	var out := DungeonRun.leave(s)
	assert_true(out["confirm"], "a won room asks for confirmation")
	s = out["state"]
	assert_eq(s["progress"]["dungeon_run"], {}, "reset")
	assert_eq(s["world"]["spawn"], "from_cloister", "back at the Ruins")
	s = DungeonRun.enter(s, CLOISTER, c)["state"]
	assert_true(not DungeonRun.shortcut_open(s, c[CLOISTER]), "no shortcut yet")
	s["progress"]["cleared_encounters"]["encounter.cloister_boss"] = 0
	var r := StoryEvents.apply_fight(s, F.fight("encounter.cloister_boss"), c)
	assert_true(
		r["summary"]["events"].any(
			func(e: Dictionary) -> bool: return e["type"] == "dungeon_shortcut_opened"
		),
		"shortcut event"
	)
	s = DungeonRun.leave(r["state"])["state"]
	s = DungeonRun.enter(s, CLOISTER, c)["state"]
	s = F.play(s, F.fight("encounter.cloister_vestibule"))
	assert_eq(
		DungeonRun.accessible(s, c[CLOISTER]),
		["vestibule", "gallery", "kennel", "campfire", "dial"],
		"stair to the campfire, boss and elite replayable"
	)


func test_save_without_a_valid_run_falls_back_to_the_ruins() -> void:
	var s := _in_dungeon()
	s["progress"]["dungeon_run"] = {"dungeon_id": "dungeon.gone"}
	assert_true(StoryEvents.on_load(s, F.content()), "changed")
	assert_eq(s["progress"]["dungeon_run"], {}, "dropped")
	assert_eq(s["world"]["location_id"], "location.watch_ruins", "at the Ruins")
	assert_eq(s["world"]["spawn"], "from_cloister", "from the postern")
