extends TestCase
## Milestone 6 content (ROADMAP 6.1, 6.2): quests, dialogues, discoveries and
## the dungeon as specified in docs/content/, with original French texts.

const ROOTS := ["res://game/data/canon", "res://game/data/original"]
const MAX_LINE := 120
const MAX_LINES := 4


func _content() -> Dictionary:
	return ContentLoader.load_roots(ROOTS)


func _texts() -> Dictionary:
	var out := {}
	var f := FileAccess.open(ContentLoader.STRINGS_CSV, FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2:
			out[row[0]] = row[1]
	return out


func test_dialogue_and_story_lines_exist_and_stay_short() -> void:
	var c := _content()
	var texts := _texts()
	for d in c["by_type"]["dialogue"]:
		assert_true(d["lines"].size() <= MAX_LINES, "%s: <= 4 lines" % d["id"])
		for line in d["lines"]:
			var key: String = "%s.%s" % [d["id"], line["key_suffix"]]
			assert_true(texts.has(key), "%s in strings.csv" % key)
	for key in texts:
		if key.begins_with("dialogue.") or key.begins_with("story."):
			assert_true(
				texts[key].length() <= MAX_LINE, "%s: %d chars" % [key, texts[key].length()]
			)
	for key in ["story.intro.card_01", "story.intro.card_03", "story.epilogue.card_03"]:
		assert_true(texts.has(key), key)


func test_no_dialogue_is_marked_as_a_quote() -> void:
	for path in ["res://game/data/original/dialogues.json", "res://game/data/original/npcs.json"]:
		var text := FileAccess.get_file_as_string(path)
		assert_true(not text.contains('"quote"'), "%s: no quote field" % path)
		assert_true(not text.contains('"source"'), "%s: no source field" % path)
	var texts := _texts()
	for key in texts:
		if key.begins_with("dialogue."):
			assert_true(not texts[key].contains("« "), "%s: no quotation marks" % key)


func test_himmel_is_canon_cited_only_twice() -> void:
	var c := _content()
	var himmel: Dictionary = c["by_id"]["character.himmel"]
	assert_eq(himmel["origin"], "canon", "canon")
	assert_eq(himmel["playable"], false, "not playable")
	assert_true(himmel["canon_note"].length() > 20, "canon_note")
	var texts := _texts()
	var keys := []
	for key in texts:
		if texts[key].contains("Himmel") and key != "character.himmel.name":
			keys.append(key)
	keys.sort()
	assert_eq(keys, ["dialogue.odette_statue_done.line_01", "discovery.moss_statue.lore"], "cited")
	for key in texts:
		if key.begins_with("dialogue."):
			assert_true(not texts[key].contains("Frieren"), "%s: Fern does not mention her" % key)


func test_quests_match_the_spec() -> void:
	var c := _content()
	var mains := []
	var sides := []
	var dailies := []
	var gold := 0
	var pages := 0
	for q in c["by_type"]["quest"]:
		match q["kind"]:
			"main":
				mains.append(q["id"])
			"side":
				sides.append(q["id"])
			"daily":
				dailies.append(q["id"])
		gold += int(q["rewards"]["gold"])
		pages += int(q["rewards"]["materials"].get("material.grimoire_page", 0))
	assert_eq(mains.size(), 4, "4 main quests")
	assert_eq(sides.size(), 3, "3 side quests")
	assert_eq(dailies.size(), 9, "9 contracts in the pool")
	assert_eq(gold, 4350, "quest gold (quests.md 1.4)")
	assert_eq(pages, 11, "11 pages from quests (GAME_BALANCE 16)")
	assert_true(c["by_id"]["quest.main_01"]["active_at_start"], "main_01 active at start")


func test_six_counted_discoveries_two_per_field() -> void:
	var c := _content()
	var per := {}
	for d in c["by_type"]["discovery"]:
		if d["counts_for_location"]:
			per[d["location"]] = int(per.get(d["location"], 0)) + 1
			assert_true(d["fog_radius"] > 0.0, "%s lifts the fog" % d["id"])
	assert_eq(
		per,
		{"location.whispering_wood": 2, "location.lantern_mire": 2, "location.watch_ruins": 2},
		"2 per field, none in Aubelin"
	)


func test_unlocks_follow_the_main_quests() -> void:
	var by_id: Dictionary = _content()["by_id"]
	assert_eq(
		by_id["location.lantern_mire"]["unlock"], {"quest_completed": "quest.main_01"}, "mire"
	)
	assert_eq(
		by_id["location.watch_ruins"]["unlock"], {"quest_completed": "quest.main_02"}, "ruins"
	)
	assert_eq(
		by_id["dungeon.silent_dial_cloister"]["unlock"],
		{"quest_completed": "quest.main_03"},
		"dungeon"
	)
	assert_eq(by_id["location.whispering_wood"]["fog_reveal"], [], "the Wood no longer reveals")
	assert_eq(by_id["location.lantern_mire"]["encounters"].size(), 5, "5 mire packs")
	assert_eq(by_id["location.watch_ruins"]["encounters"].size(), 5, "5 ruins packs")
	assert_eq(
		by_id["encounter.watch_ruins_05"]["first_clear_rewards"],
		{"materials": {"material.cloister_key": 1}, "items": []},
		"the key"
	)


func test_dungeon_rooms_are_not_hunted() -> void:
	var by_id: Dictionary = _content()["by_id"]
	var dungeon: Dictionary = by_id["dungeon.silent_dial_cloister"]
	assert_eq(dungeon["rooms"].size(), 7, "7 rooms")
	for room in dungeon["rooms"]:
		if room.get("encounter", "") == "":
			continue
		var e: Dictionary = by_id[room["encounter"]]
		assert_eq(e["offline_eligible"], false, "%s: no offline" % e["id"])
		assert_eq(e["arena_center"], "anchor", "%s: arena on the anchor" % e["id"])
		assert_true(
			not by_id[e["location"]]["encounters"].has(e["id"]), "%s not in the field" % e["id"]
		)


func test_npcs_have_anchors_and_dialogues() -> void:
	var c := _content()
	assert_eq(c["by_type"]["npc"].size(), 7, "7 NPCs")
	for npc in c["by_type"]["npc"]:
		assert_true(not npc["dialogues"].is_empty(), "%s talks" % npc["id"])
		var last: Dictionary = npc["dialogues"][npc["dialogues"].size() - 1]
		assert_eq(last["condition"], {}, "%s ends on an unconditional line" % npc["id"])
	assert_eq(c["by_id"]["location.aubelin"]["npcs"].size(), 7, "all in Aubelin")


## GDD decisions 29-30: the guaranteed staff, and the Volley test pack.
func test_early_game_staff_and_volley_test() -> void:
	var by_id: Dictionary = _content()["by_id"]
	assert_eq(
		by_id["encounter.whispering_wood_01"]["first_clear_rewards"]["items"],
		[{"base": "item.birch_staff", "rarity": "uncommon"}],
		"first clear of the first pack gives the staff"
	)
	var pack: Dictionary = by_id["encounter.whispering_wood_04"]
	assert_eq(pack["level"], 3, "level 3")
	var levels := []
	for g in pack["enemies"]:
		for i in int(g["count"]):
			levels.append(int(pack["level"]) + int(g["level_offset"]))
	assert_eq(levels, [2, 2, 1, 1], "same four wolves")
