extends TestCase
## Audio (ROADMAP Jalon 7): the buses exist, every music and sfx id named by
## the map (assets/audio/audio_map.json), the code or the source plan has its
## files, the event rules name real spells, events and captions, and the
## volume API maps a 0..1 slider to the bus.

const PLAN_PATH := "res://art/source/audio/plan.json"
const CODE_DIRS := ["res://game"]
## Combat events the sim emits that a rule may listen to.
const SIM_EVENTS := [
	"spell_cast",
	"attack_started",
	"cast_interrupted",
	"telegraph_started",
	"damage_dealt",
	"barrier_broken",
	"loot_dropped",
	"enemy_defeated",
	"boss_phase_changed",
]


func test_buses_exist() -> void:
	var layout := FileAccess.get_file_as_string("res://default_bus_layout.tres")
	for bus: String in AudioCatalog.BUSES:
		assert_true(AudioServer.get_bus_index(bus) != -1, "bus %s missing at runtime" % bus)
		if bus != "Master":
			assert_true(('&"%s"' % bus) in layout, "bus %s missing from the layout" % bus)


func test_map_only_references_existing_files() -> void:
	for id in AudioCatalog.referenced_sfx():
		assert_true(AudioCatalog.has_sfx(id), "sfx %s has no file in assets/audio/sfx" % id)
	for id in AudioCatalog.referenced_music():
		assert_true(AudioCatalog.has_music(id), "music %s has no file in assets/audio/music" % id)


func test_every_place_has_music_and_steps() -> void:
	for type_name in ["location", "dungeon"]:
		for e: Dictionary in Content.all_of(type_name):
			assert_true(AudioCatalog.music_for(e["id"]) != "", "%s has no music" % e["id"])
	for key in ["title", "combat", "boss", "victory", "defeat"]:
		assert_true(AudioCatalog.music_for(key) != "", "music entry %s missing" % key)
	assert_true(AudioCatalog.steps_for("location.nowhere") != "", "default footsteps")


func test_every_planned_sound_was_produced() -> void:
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	for item: Dictionary in plan["items"]:
		var id: String = item["id"]
		var ok := (
			AudioCatalog.has_music(id)
			if item["kind"] in ["music", "sting"]
			else AudioCatalog.has_sfx(id)
		)
		assert_true(ok, "planned sound %s has no game file" % id)


func test_ids_named_in_code_exist() -> void:
	var re := RegEx.create_from_string(
		'(play_sfx|play_music|music_for|story_sfx|ui_sfx|play_ui|caption_for)\\("([a-z_.]+)"'
	)
	var m := AudioCatalog.map()
	for path in _scripts("res://game"):
		for hit in re.search_all(FileAccess.get_file_as_string(path)):
			var fn := hit.get_string(1)
			var id := hit.get_string(2)
			var known := false
			match fn:
				"play_sfx":
					known = AudioCatalog.has_sfx(id)
				"play_music":
					known = AudioCatalog.has_music(id)
				"music_for":
					known = (m["music"] as Dictionary).has(id)
				"story_sfx":
					known = (m["story"] as Dictionary).has(id)
				"ui_sfx", "play_ui":
					known = (m["ui"] as Dictionary).has(id)
				"caption_for":
					known = (m["captions"] as Dictionary).has(id)
			assert_true(known, '%s: %s("%s") names nothing' % [path, fn, id])


func test_combat_rules_are_valid() -> void:
	var keys := ContentLoader.translation_keys("res://game/i18n/strings.csv")
	for rule: Dictionary in AudioCatalog.map()["combat"]:
		assert_true(str(rule.get("event", "")) in SIM_EVENTS, "unknown event in %s" % rule)
		if rule.has("spell"):
			assert_true(Content.has_entity(rule["spell"]), "unknown spell %s" % rule["spell"])
		if rule.has("min_rarity"):
			assert_true(rule["min_rarity"] in BalanceItems.RARITIES, "rarity %s" % rule)
		if rule.has("caption"):
			assert_true(keys.has(rule["caption"]), "caption key %s missing" % rule["caption"])
		assert_true(rule.get("bus", "SFX") in AudioCatalog.BUSES, "bus of %s" % rule)
	for key: String in (AudioCatalog.map()["captions"] as Dictionary).values():
		assert_true(keys.has(key), "caption key %s missing" % key)


func test_rules_pick_the_expected_sound() -> void:
	var pick := func(e: Dictionary, facts: Dictionary = {}) -> String:
		return str(AudioCatalog.combat_rule(e, facts).get("sfx", ""))
	assert_eq(pick.call({"type": "spell_cast", "spell": "spell.zoltraak"}), "zoltraak_cast")
	assert_eq(pick.call({"type": "damage_dealt", "spell": "spell.zoltraak"}), "zoltraak_impact")
	assert_eq(
		pick.call(
			{"type": "damage_dealt", "spell": "spell.mana_bolt"}, {"target_family": "construct"}
		),
		"hit_stone"
	)
	assert_eq(pick.call({"type": "damage_dealt"}, {"target_family": "beast"}), "hit_flesh")
	var seal := AudioCatalog.combat_rule(
		{"type": "telegraph_started", "spell": "ability.morvaine_ash_seal"}
	)
	assert_eq(seal.get("sfx", ""), "ash_seal")
	assert_eq(seal.get("caption", ""), "ui.caption.ash_seal")
	assert_eq(
		AudioCatalog.combat_rule({"type": "telegraph_started", "spell": "ability.wolf_lunge"}).get(
			"caption", ""
		),
		"ui.caption.telegraph"
	)
	var loot := {"type": "loot_dropped", "items": [{"rarity": "epic"}], "runes": []}
	assert_eq(AudioCatalog.best_rarity(loot), "epic")
	assert_eq(pick.call(loot, {"rarity": "epic"}), "loot_rare")
	assert_eq(pick.call(loot, {"rarity": "uncommon"}), "loot_common")
	assert_eq(pick.call({"type": "unit_spawned"}), "")


func test_music_follows_the_screen() -> void:
	assert_eq(Audio.music_key("title", true, "location.aubelin"), "title")
	assert_eq(Audio.music_key("explore", false, ""), "title")
	assert_eq(Audio.music_key("explore", true, "location.aubelin"), "location.aubelin")
	assert_eq(
		Audio.music_key("bag", true, "dungeon.silent_dial_cloister"), "dungeon.silent_dial_cloister"
	)
	assert_eq(Audio.music_key("settings", true, "location.aubelin"), "")


func test_bus_volume_api() -> void:
	Audio.set_bus_volume("Music", 0.5)
	assert_near(Audio.get_bus_volume("Music"), 0.5, 0.001, "music at half")
	var i := AudioServer.get_bus_index("Music")
	assert_near(AudioServer.get_bus_volume_db(i), linear_to_db(0.5), 0.01, "bus dB")
	Audio.set_bus_volume("SFX", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "0 mutes")
	assert_eq(Audio.get_bus_volume("SFX"), 0.0)
	Audio.set_bus_volume("Music", 1.0)
	Audio.set_bus_volume("SFX", 1.0)
	assert_true(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "unmuted")


func test_kit_buttons_click() -> void:
	var b := Kit.button("x")
	var connected := 0
	for c: Dictionary in b.pressed.get_connections():
		if (c["callable"] as Callable).get_method() == "play_ui":
			connected += 1
	assert_eq(connected, 1, "one UI sound hook per Kit button")
	b.free()


func _scripts(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out
