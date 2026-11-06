extends TestCase
## Milestone 6 UI built headless (ROADMAP 6.3-6.6): the journal (quests,
## contracts with the reason of a disabled « Récupérer », bestiary tiers,
## discoveries by place), the dialogue and story-card overlays, banners,
## the quest tracker, the world interactables and the dungeon helpers.
## Saves go to a throwaway folder, never to the real slot.

const JOURNAL := "res://game/app/screens/journal_screen.gd"
const WOLF := "enemy.mist_wolf"
const WOOD := "location.whispering_wood"

var _real_store: SaveStore


func _begin() -> void:
	TranslationServer.set_locale("fr")
	_real_store = SaveService.store
	SaveService.store = SaveStore.new("user://test_saves/story_ui_%d" % Time.get_ticks_usec())
	GameState.test_channel = false
	GameState.start_new(Content.start())


func _end() -> void:
	SaveService.store = _real_store
	GameState.clear()


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _open(params: Dictionary = {}) -> Control:
	var screen: Control = (load(JOURNAL) as GDScript).new()
	screen.call("setup", params)
	_root().add_child(screen)
	return screen


func _close(node: Node) -> void:
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.free()


func _control(id: String) -> Control:
	var c: Variant = UiProbe._controls.get(id)
	return c if is_instance_valid(c) and (c as Control).is_inside_tree() else null


func _text(id: String) -> String:
	var c := _control(id)
	return str(c.get("text")) if c else ""


func test_journal_quests_tab_shows_the_tracked_quest_and_its_objectives() -> void:
	_begin()
	assert_eq(GameState.content_api.tracked_quest(), "quest.main_01", "main_01 tracked")
	var screen := _open()
	assert_eq(_text("journal.title"), tr("ui.journal.title"), "title")
	assert_eq(_text("journal.quest.main_01"), Content.display_name("quest.main_01"), "name")
	assert_true(
		_text("journal.quest.main_01.state").begins_with(tr("ui.journal.tracked")), "tracked"
	)
	assert_true(_text("journal.quest.main_01.objective.clear_wood").contains("(0/3)"), "0/3")
	assert_true(_text("journal.quest.main_01.rewards") != "", "rewards shown")
	_close(screen)
	_end()


func test_journal_contracts_claim_is_disabled_with_its_reason() -> void:
	_begin()
	var offers: Array = GameState.data["progress"]["contracts"]["offers"]
	assert_true(offers.size() >= 2, "contracts rolled at the new game")
	var first: String = offers[0]["id"]
	var second: String = offers[1]["id"]
	offers[1]["state"] = "completed"
	var screen := _open({"tab": "contracts"})
	var a := _control("journal.contract.%s.claim" % first.get_slice(".", 1)) as Button
	assert_true(a != null and a.disabled, "active contract: disabled")
	assert_eq(
		_text("journal.contract.%s.claim_reason" % first.get_slice(".", 1)),
		GameState.reason_text({"error": "error.contract.not_completed"}),
		"reason shown"
	)
	var b := _control("journal.contract.%s.claim" % second.get_slice(".", 1)) as Button
	assert_true(b != null and not b.disabled, "completed contract: enabled")
	var gold := int(GameState.data["wallet"]["gold"])
	b.pressed.emit()
	assert_true(int(GameState.data["wallet"]["gold"]) > gold, "claimed: gold credited")
	assert_eq(
		load(JOURNAL).contract_reason({"state": "claimed"}),
		tr("ui.contracts.claimed"),
		"claimed reason"
	)
	_close(screen)
	_end()


func test_journal_bestiary_tiers_and_what_unlocks_them() -> void:
	_begin()
	GameState.data["progress"]["bestiary"][WOLF] = 0
	var screen := _open({"tab": "bestiary"})
	assert_eq(_text("journal.bestiary.mist_wolf.name"), tr("ui.bestiary.unknown"), "locked: ???")
	assert_eq(
		_text("journal.bestiary.mist_wolf.next"),
		tr("ui.journal.bestiary_next").format({"count": 1}),
		"locked: what unlocks it"
	)
	_close(screen)
	for case: Array in [[1, 1, 5], [5, 2, 25], [25, 3, 0]]:
		GameState.data["progress"]["bestiary"][WOLF] = case[0]
		screen = _open({"tab": "bestiary"})
		assert_eq(
			_text("journal.bestiary.mist_wolf.name"),
			Content.display_name(WOLF),
			"named %d" % case[0]
		)
		assert_true(
			_text("journal.bestiary.mist_wolf.tier").contains(tr("ui.bestiary.tier_%d" % case[1])),
			"tier %d at %d wins" % [case[1], case[0]]
		)
		assert_eq(
			_control("journal.bestiary.mist_wolf.affinities") != null, case[1] >= 2, "affinities"
		)
		assert_eq(_control("journal.bestiary.mist_wolf.stats") != null, case[1] >= 3, "stats")
		_close(screen)
	_end()


func test_journal_discoveries_by_place() -> void:
	_begin()
	var screen := _open({"tab": "discoveries"})
	assert_eq(
		_text("journal.discoveries.whispering_wood.count"),
		tr("ui.discovery.count").format({"found": 0, "total": 2}),
		"0/2 in the wood"
	)
	assert_eq(_text("journal.discovery.dead_birch_vista"), tr("ui.bestiary.unknown"), "hidden")
	_close(screen)
	var r := GameState.content_api.take_discovery("discovery.dead_birch_vista")
	assert_true(r["ok"], "taken")
	screen = _open({"tab": "discoveries"})
	assert_eq(
		_text("journal.discovery.dead_birch_vista"),
		Content.display_name("discovery.dead_birch_vista"),
		"listed once found"
	)
	assert_true(
		_text("journal.discoveries.whispering_wood.count").contains("1/2"), "1/2 in the wood"
	)
	assert_true(
		(
			GameState
			. content_api
			. fog_discs()
			. map(func(d: Dictionary) -> String: return d["discovery_id"])
			. has("discovery.dead_birch_vista")
		),
		"its disc lifts the fog"
	)
	_close(screen)
	_end()


func test_banners_have_text_for_story_events() -> void:
	_begin()
	for e: Dictionary in [
		{"type": "quest_activated", "quest": "quest.main_02"},
		{"type": "quest_completed", "quest": "quest.main_01"},
		{"type": "quest_turned_in", "quest": "quest.main_01"},
		{
			"type": "quest_progress",
			"quest": "quest.main_01",
			"objective": "clear_wood",
			"count": 1,
			"target": 3
		},
		{"type": "discovery_found", "discovery_id": "discovery.moss_statue", "xp": 70, "gold": 0},
		{"type": "bestiary_tier_unlocked", "enemy_id": WOLF, "tier": 1},
		{"type": "contract_completed", "id": "quest.daily_wolves"},
		{"type": "dungeon_checkpoint", "room": "campfire"},
		{"type": "dungeon_shortcut_opened", "dungeon_id": "dungeon.silent_dial_cloister"},
	]:
		var text := StoryText.banner_text(e)
		assert_true(text != "" and not text.contains("{"), "%s: %s" % [e["type"], text])
	assert_true(
		(
			StoryText
			. banner_text({"type": "bestiary_tier_unlocked", "enemy_id": WOLF, "tier": 1})
			. contains(Content.display_name(WOLF))
		),
		"bestiary banner names the enemy"
	)
	var banners := StoryBanners.new()
	_root().add_child(banners)
	UiProbe.world["banners"] = []
	GameState.story_events.emit([{"type": "bestiary_tier_unlocked", "enemy_id": WOLF, "tier": 1}])
	assert_eq(UiProbe.world["banners"].size(), 1, "banner published")
	assert_eq(banners.get_child_count(), 1, "banner shown")
	_close(banners)
	_end()


func test_dialogue_overlay_advances_offers_and_skips() -> void:
	_begin()
	var host := Control.new()
	_root().add_child(host)
	var t := GameState.content_api.talk("npc.odile")
	assert_true(t["ok"] and t["lines"].size() >= 1, "Odile talks")
	var done := []
	var d := DialogueOverlay.open(host, t["lines"], "quest.main_02")
	d.finished.connect(func(skipped: bool) -> void: done.append(skipped))
	assert_eq(
		_text("dialogue.speaker"), StoryText.speaker_name(str(t["lines"][0]["speaker"])), "who"
	)
	assert_eq(_text("dialogue.text"), tr(str(t["lines"][0]["key"])), "first line")
	for i in t["lines"].size():
		d._advance()
	assert_true(
		_text("dialogue.card_title").contains(StoryText.quest_name("quest.main_02")), "offer"
	)
	assert_true(done.is_empty(), "the offer card waits")
	(_control("dialogue.accept") as Button).pressed.emit()
	assert_eq(done, [false], "accepted")
	var skipped := []
	var d2 := DialogueOverlay.open(host, t["lines"])
	d2.finished.connect(func(s: bool) -> void: skipped.append(s))
	(_control("dialogue.skip") as Button).pressed.emit()
	assert_eq(skipped, [true], "skipped")
	var r := GameState.content_api.finish_talk("npc.odile", t["dialogue"])
	assert_true(r["ok"], "finish_talk after the overlay")
	_close(host)
	_end()


func test_story_cards_and_lines() -> void:
	assert_eq(StoryCards.keys_of("intro").size(), 3, "3 intro cards")
	assert_eq(StoryCards.keys_of("epilogue").size(), 3, "3 epilogue cards")
	var lines := StoryText.dialogue_lines("dialogue.morvaine_intro")
	assert_eq(lines.size(), 3, "Morvaine's intro")
	assert_eq(lines[0]["speaker"], "enemy.morvaine", "speaker")
	assert_eq(
		StoryText.speaker_name("enemy.morvaine"), Content.display_name("enemy.morvaine"), "name"
	)
	assert_eq(StoryText.speaker_name(""), "", "no speaker for the bell")


func test_quest_tracker_follows_the_tracked_quest() -> void:
	_begin()
	var tracker := QuestTracker.new()
	_root().add_child(tracker)
	assert_eq(_text("hud.quest"), Content.display_name("quest.main_01"), "tracked quest")
	assert_true(_text("hud.quest.objective.clear_wood").contains("(0/3)"), "objective")
	var e := QuestTracker.tracked_entry()
	assert_eq(e.get("id", ""), "quest.main_01", "entry")
	_close(tracker)
	_end()


func test_discovery_entries_map_kinds_and_prompts() -> void:
	_begin()
	var anchor := Node3D.new()
	var chest := ExploreStory.discovery_entry(
		{"id": "discovery.wood_chest", "kind": "chest", "trigger": "interact"}, anchor
	)
	assert_eq(chest["kind"], "chest", "chest")
	assert_eq(chest["prompt"], tr("ui.story.open_chest"), "open")
	var herb := ExploreStory.discovery_entry(
		{"id": "discovery.mist_herb_wood_01", "kind": "pickup", "trigger": "interact"}, anchor
	)
	assert_eq(herb["kind"], "herb", "herb")
	var statue := ExploreStory.discovery_entry(
		{"id": "discovery.moss_statue", "kind": "memorial", "trigger": "interact_hold"}, anchor
	)
	assert_eq(statue["prompt"], tr("discovery.moss_statue.action"), "hold action")
	var vista := ExploreStory.discovery_entry(
		{"id": "discovery.dead_birch_vista", "kind": "vista", "trigger": "zone"}, anchor
	)
	assert_eq(vista["radius"], ExploreStory.ZONE_RADIUS_M, "zone radius")
	var herbs := GameState.content_api.discoveries_in(WOOD).filter(
		func(d: Dictionary) -> bool: return str(d["id"]).contains("mist_herb")
	)
	assert_true(herbs.is_empty(), "herbs hidden without the herbalist's quest")
	anchor.free()
	_end()


func test_world_interactables_reach_zones_and_markers() -> void:
	var world := Node3D.new()
	_root().add_child(world)
	var a := Marker3D.new()
	world.add_child(a)
	a.position = Vector3(10, 0, 0)
	var b := Marker3D.new()
	world.add_child(b)
	b.position = Vector3(0, 0, 10)
	var items := WorldInteractables.new()
	world.add_child(items)
	(
		items
		. build(
			[
				{
					"id": "npc.odile",
					"kind": "npc",
					"anchor": a,
					"name": "Odile",
					"prompt": "p",
					"radius": 3.5,
					"trigger": "interact",
					"marker": "offer",
					"model": "res://assets/models/npcs/missing_placeholder.glb",
				},
				{
					"id": "discovery.dead_birch_vista",
					"kind": "discovery",
					"anchor": b,
					"name": "",
					"prompt": "",
					"radius": 3.0,
					"trigger": "zone",
					"marker": "",
					"model": "",
				},
				{"id": "no_anchor", "kind": "npc", "anchor": null},
			]
		)
	)
	assert_eq(items.ids().size(), 2, "missing anchor skipped")
	assert_eq(items.nearest(Vector3(8, 0, 0)).get("id", ""), "npc.odile", "Odile in reach")
	assert_true(items.nearest(Vector3(0, 0, 0)).is_empty(), "nothing in reach")
	assert_eq(items.zones_at(Vector3(0, 0, 9)), ["discovery.dead_birch_vista"], "zone")
	assert_eq(items.marker_of("npc.odile"), "offer", "marker")
	items.set_marker("npc.odile", "turn_in")
	assert_eq(items.marker_of("npc.odile"), "turn_in", "marker changed")
	items.remove("discovery.dead_birch_vista")
	assert_true(not items.has("discovery.dead_birch_vista"), "removed")
	_close(world)


func test_patrol_moves_the_pack_and_pauses_at_the_ends() -> void:
	var view := ExploreView.new()
	_root().add_child(view)
	var anchor := Marker3D.new()
	view.add_child(anchor)
	anchor.set_meta("patrol", [[28, 12], [30, -10]])
	var points: Array[Vector3] = view._patrol_points(anchor)
	assert_eq(points.size(), 2, "two patrol points")
	var pack := Node3D.new()
	view.add_child(pack)
	pack.global_position = points[0]
	view._packs["encounter.test"] = {
		"anchor": anchor, "node": pack, "radius": 5.0, "patrol": points, "leg": 1, "wait": 0.0
	}
	view._move_patrols(1.0)
	assert_near(
		pack.global_position.distance_to(points[0]), ExploreView.PATROL_SPEED, 0.01, "walks"
	)
	for i in 30:
		view._move_patrols(1.0)
	assert_eq(view._packs["encounter.test"]["leg"], 0, "turned back at the end")
	assert_true(view.pack_node("encounter.test") == pack, "pack node")
	anchor.set_meta("patrol", [])
	assert_true(view._patrol_points(anchor).is_empty(), "no patrol")
	view._packs.clear()
	_close(view)


func test_dungeon_load_args_vitals_and_boss_lines() -> void:
	_begin()
	var dungeon := ExploreDungeon.new()
	assert_true(dungeon.load_args().is_empty(), "outside: nothing")
	var next := GameState.data.duplicate(true)
	next["progress"]["quests"]["quest.main_03"] = {
		"state": "turned_in", "step": 1, "counts": {}, "order": 9
	}
	GameState.commit_action(next)
	var r := GameState.content_api.enter_dungeon("dungeon.silent_dial_cloister")
	assert_true(r["ok"], "entered: " + str(r.get("error", "")))
	assert_true(dungeon.inside(), "inside")
	var args := dungeon.load_args()
	assert_eq(args["place"], "dungeon.silent_dial_cloister", "dungeon scene")
	assert_eq(args["spawn"], "default", "at the entrance")
	assert_eq(args["encounters"].size(), 5, "every room fight")
	GameState.data["progress"]["dungeon_run"]["vitals"] = {
		"hp_pct": 0.4, "mana_pct": 0.5, "ult_charge": 20.0
	}
	var setup := {"party": [{"id": "character.fern"}]}
	var merged := dungeon.combat_setup("encounter.cloister_gallery", setup)
	assert_eq(merged["party"][0]["hp_pct"], 0.4, "HP carried into the room fight")
	assert_true(not setup["party"][0].has("hp_pct"), "setup not mutated")
	assert_true(
		not dungeon.combat_setup("encounter.whispering_wood_01", setup)["party"][0].has("hp_pct"),
		"field fights start full"
	)
	assert_eq(dungeon.room_of("encounter.cloister_boss").get("kind", ""), "boss", "boss room")
	dungeon.free()
	_end()
