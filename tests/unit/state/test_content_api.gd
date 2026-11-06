extends TestCase
## GameState side of milestone 6 (GameState.content_api): talking, quests,
## contracts, discoveries and the dungeon commit, save and emit story events;
## a reload keeps quest states. Saves go to a throwaway folder.

const F := preload("res://tests/unit/engine/story_fixtures.gd")

var _real_store: SaveStore
var _events: Array = []


func _begin(s: Dictionary) -> void:
	_real_store = SaveService.store
	SaveService.store = SaveStore.new("user://test_saves/content_%d" % Time.get_ticks_usec())
	_events = []
	GameState.story_events.connect(_on_events)
	GameState.adopt(s, false)


func _end() -> void:
	GameState.story_events.disconnect(_on_events)
	SaveService.store = _real_store
	GameState.clear()


func _on_events(events: Array) -> void:
	_events.append_array(events)


func _types() -> Array:
	return _events.map(func(e: Dictionary) -> String: return e["type"])


func test_talk_then_finish_activates_and_saves() -> void:
	var s := F.state(6)
	_begin(s)
	var api := GameState.content_api
	var talk := api.talk("npc.tobias")
	assert_true(talk["ok"], "talk")
	assert_eq(talk["dialogue"], "dialogue.tobias_offer", "offer")
	assert_eq(talk["lines"].size(), 3, "3 lines")
	assert_eq(talk["lines"][0]["key"], "dialogue.tobias_offer.line_01", "line key")
	assert_eq(api.npc_marker("npc.tobias"), "offer", "full diamond")
	var done := api.finish_talk("npc.tobias", talk["dialogue"])
	assert_true(done["ok"], "finished")
	assert_eq(done["offered"], "quest.side_clockmaker", "accepted at the end")
	assert_eq(api.quest_state("quest.side_clockmaker"), "active", "active")
	assert_true(_types().has("quest_activated"), "event emitted")
	assert_true(SaveService.store.has_main(), "saved")
	assert_eq(
		api.finish_talk("npc.tobias", "dialogue.odile_idle")["error"], "error.dialogue.mismatch"
	)
	assert_eq(api.talk("npc.nobody")["error"], "error.npc.unknown", "unknown NPC")
	_end()


func test_service_npcs_open_their_panel() -> void:
	_begin(F.state(1))
	var api := GameState.content_api
	assert_true(api.talk("npc.bastien")["opens_panel"], "forge")
	assert_true(api.talk("npc.notice_board")["opens_panel"], "board")
	assert_true(not api.talk("npc.odile")["opens_panel"], "Odile has no panel")
	assert_eq(api.npcs_here().size(), 7, "7 NPCs in Aubelin")
	_end()


func test_combat_result_feeds_quests_and_bestiary() -> void:
	_begin(F.state(2))
	var summary := GameState.apply_combat_result(F.fight("encounter.whispering_wood_02"))
	assert_true(summary.has("events"), "summary carries events")
	assert_true(_types().has("quest_progress"), "clear_wood moved")
	assert_true(_types().has("bestiary_tier_unlocked"), "first wolf page")
	var log := GameState.content_api.quest_log()
	assert_eq(log[0]["objectives"][0]["count"], 1, "1/3")
	assert_eq(GameState.summary()["quest"], "quest.main_01", "probe sees the tracked quest")
	_end()


func test_reload_mid_quest_keeps_counts() -> void:
	_begin(F.state(2))
	GameState.apply_combat_result(F.fight("encounter.whispering_wood_02"))
	var saved := F.reloaded(GameState.data)
	GameState.adopt(saved, false)
	assert_eq(
		GameState.data["progress"]["quests"]["quest.main_01"]["counts"]["clear_wood"], 1, "kept"
	)
	_end()


func test_contracts_roll_on_load_and_claim() -> void:
	var s := F.state(3)
	_begin(s)
	var api := GameState.content_api
	assert_eq(api.contracts().size(), 2, "rolled at adoption: 2 eligible the first day")
	assert_eq(api.refresh_contracts()["new_day"], false, "same day: nothing new")
	var first: String = api.contracts()[0]["id"]
	GameState.data["progress"]["contracts"]["offers"][0]["state"] = "completed"
	assert_true(api.contracts_claimable(), "journal icon")
	var gold := int(GameState.data["wallet"]["gold"])
	var r := api.claim_contract(first)
	assert_true(r["ok"], "claimed")
	assert_eq(int(GameState.data["wallet"]["gold"]), gold + int(r["reward"]["gold"]), "gold")
	_end()


func test_discovery_through_the_api() -> void:
	_begin(F.state(1))
	var api := GameState.content_api
	var r := api.take_discovery("discovery.dead_birch_vista")
	assert_true(r["ok"], "found")
	assert_eq(api.discovery_counts("location.whispering_wood"), {"found": 1, "total": 2}, "1/2")
	assert_eq(api.fog_discs().size(), 1, "fog hole")
	assert_true(_types().has("discovery_found"), "event")
	assert_eq(api.take_discovery("discovery.dead_birch_vista")["error"], "error.discovery.found")
	assert_eq(api.compass_hints("location.whispering_wood"), ["discovery.moss_statue"], "hint")
	_end()


func test_dungeon_through_the_api() -> void:
	var s := F.state(11)
	for q in ["quest.main_01", "quest.main_02", "quest.main_03"]:
		F.turned_in(s, q)
	s["progress"]["quests"]["quest.main_04"] = {
		"state": "active", "step": 1, "counts": {}, "order": 9
	}
	_begin(s)
	var api := GameState.content_api
	var r := api.enter_dungeon("dungeon.silent_dial_cloister")
	assert_true(r["ok"], "entered (%s)" % r["error"])
	assert_true(r["first"], "first visit (Fern's line)")
	assert_eq(GameState.data["progress"]["quests"]["quest.main_04"]["step"], 2, "LocationVisited")
	assert_eq(api.dungeon_view()["room"], "vestibule", "at the vestibule")
	assert_eq(api.leave_dungeon_quote()["confirm"], false, "nothing won yet")
	GameState.apply_combat_result(F.fight("encounter.cloister_vestibule"))
	assert_true(api.dungeon_view()["rooms"][1]["accessible"], "gallery door open")
	assert_eq(api.dungeon_vitals()["hp_pct"], 0.6, "HP carried")
	assert_eq(api.leave_dungeon_quote()["confirm"], true, "confirm before leaving")
	assert_true(api.leave_dungeon()["ok"], "left")
	assert_eq(api.dungeon_view(), {}, "outside")
	_end()
