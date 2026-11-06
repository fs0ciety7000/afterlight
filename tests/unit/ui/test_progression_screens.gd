extends TestCase
## Milestone 4 screens (ROADMAP 4.8, 4.10) built headless from a new game:
## each screen builds and registers its controls, and a disabled action
## button shows the reason of its quote.

const SCREENS := {
	"character": "res://game/app/screens/character_screen.gd",
	"bag": "res://game/app/screens/bag_screen.gd",
	"grimoire": "res://game/app/screens/grimoire_screen.gd",
	"forge": "res://game/app/screens/forge_screen.gd",
	"runecarver": "res://game/app/screens/runecarver_screen.gd",
	"merchant": "res://game/app/screens/merchant_screen.gd",
}
const P := preload("res://tests/unit/engine/progression_fixtures.gd")


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## A fresh game in GameState (not saved: no action is committed here).
func _new_game(gold: int = 0) -> void:
	TranslationServer.set_locale("fr")
	GameState.start_new(Content.start())
	GameState.data["wallet"]["gold"] = gold


func _open(id: String, params: Dictionary = {}) -> Control:
	var screen: Control = (load(SCREENS[id]) as GDScript).new()
	screen.name = id
	screen.call("setup", params)
	_root().add_child(screen)
	return screen


func _close(screen: Control) -> void:
	_root().remove_child(screen)
	screen.free()


func _control(id: String) -> Control:
	var c: Variant = UiProbe._controls.get(id)
	return c if is_instance_valid(c) and (c as Control).is_inside_tree() else null


func _text(id: String) -> String:
	var c := _control(id)
	return str(c.get("text")) if c else ""


func _add_item(uid: String, base: String, rarity: String, affixes: Array) -> void:
	GameState.data["inventory"].append(P.item(uid, base, rarity, 1, affixes))


func test_every_screen_builds_from_a_new_game() -> void:
	_new_game()
	for id: String in SCREENS:
		var screen := _open(id)
		for tab: String in SCREENS:
			assert_true(_control("prog.tab." + tab) != null, "%s: tab %s" % [id, tab])
		assert_true(_control("prog.close") != null, "%s: close" % id)
		assert_eq(_text(id + ".title"), tr_text("ui.prog.tab." + id), "%s title" % id)
		_close(screen)
	GameState.clear()


func test_merchant_buy_without_gold_shows_the_reason() -> void:
	_new_game(0)
	var screen := _open("merchant")
	var buy := _control("shop.buy.healing_draught") as Button
	assert_true(buy != null and buy.disabled, "buy disabled at 0 gold")
	var reason := _text("shop.buy.healing_draught_reason")
	assert_true(reason.begins_with("Or insuffisant : "), "reason shown: " + reason)
	assert_true(_control("shop.buy.healing_draught_reason").visible, "reason visible")
	_close(screen)
	GameState.clear()


func test_merchant_buy_is_enabled_with_gold() -> void:
	_new_game(1000)
	var screen := _open("merchant")
	var buy := _control("shop.buy.healing_draught") as Button
	assert_true(buy != null and not buy.disabled, "buy enabled")
	assert_eq(_text("shop.carried.healing_draught"), "Porté : 0 / 5", "carried")
	_close(screen)
	GameState.clear()


func test_grimoire_rank_up_without_resources_shows_the_reason() -> void:
	_new_game(0)
	var screen := _open("grimoire", {"spell": "spell.zoltraak"})
	var rank := _control("grimoire.rank_up") as Button
	assert_true(rank != null and rank.disabled, "rank up disabled")
	assert_true(_text("grimoire.rank_up_reason") != "", "reason shown")
	assert_eq(_text("grimoire.rank"), "1 / 5", "rank")
	_close(screen)
	GameState.clear()


func test_runecarver_without_runes_explains_the_fusion_refusal() -> void:
	_new_game(0)
	var screen := _open("runecarver")
	var fuse := _control("runes.fuse") as Button
	assert_true(fuse != null and fuse.disabled, "fusion disabled")
	assert_true(
		_text("runes.fuse_reason").begins_with("Il faut 3 runes"), _text("runes.fuse_reason")
	)
	_close(screen)
	GameState.clear()


func test_character_shows_locked_artifact_slots_and_stats() -> void:
	_new_game()
	var screen := _open("character")
	assert_eq(
		_text("character.artifact_slot.0"), "Terminez la quête « Les rouages de Tobias »", "slot 1"
	)
	assert_eq(_text("character.artifact_slot.1"), "Emplacement disponible au niveau 15", "slot 2")
	assert_eq(_text("character.level"), "Niv. 1", "level")
	assert_true(_text("character.stat.power") != "", "power shown")
	assert_eq(_text("character.slot.weapon"), "Vide", "empty weapon slot")
	_close(screen)
	GameState.clear()


func test_bag_card_shows_affix_range_and_comparison() -> void:
	_new_game()
	_add_item("t1", "item.copper_amulet", "uncommon", [["affix.crit_chance", 0.03]])
	var screen := _open("bag", {"uid": "t1"})
	assert_eq(_text("bag.count"), "Sac : 1 / 60", "count")
	var equip := _control("bag.equip") as Button
	assert_true(equip != null and not equip.disabled, "equip enabled")
	assert_true(
		_text("bag.detail_mods").contains("Précision : +3 % [2-4]"), _text("bag.detail_mods")
	)
	assert_eq(_text("bag.detail_rarity"), "Peu commune", "rarity word")
	var cmp := _control("bag.compare.crit_chance_flat") as Label
	assert_true(cmp != null and cmp.text.begins_with("▲"), "better than nothing worn")
	assert_true(_control("bag.bulk_salvage") != null, "bulk salvage")
	_close(screen)
	GameState.clear()


func test_bag_bulk_salvage_with_nothing_selected_is_explained() -> void:
	_new_game()
	var screen := _open("bag")
	var bulk := _control("bag.bulk_salvage") as Button
	assert_true(bulk != null and bulk.disabled, "nothing to salvage")
	assert_eq(_text("bag.bulk_salvage_reason"), "Rien à recycler", "reason")
	_close(screen)
	GameState.clear()


func test_forge_quote_shows_cost_and_reason() -> void:
	_new_game(0)
	_add_item("t1", "item.birch_staff", "common", [])
	var screen := _open("forge", {"uid": "t1"})
	var enhance := _control("forge.enhance") as Button
	assert_true(enhance != null and enhance.disabled, "enhance disabled at 0 gold")
	assert_true(_text("forge.enhance_reason").begins_with("Or insuffisant"), "reason")
	assert_eq(_text("forge.chance"), "100 %", "guaranteed +1")
	assert_eq(_text("forge.level"), "+0 / +4", "common items stop at +4")
	_close(screen)
	GameState.clear()


func test_progression_text_formats_values_and_ranges() -> void:
	TranslationServer.set_locale("fr")
	assert_eq(ProgressionText.value("crit_chance", "flat", 0.05), "5 %", "ratio stat")
	assert_eq(ProgressionText.value("power", "flat", 12.0, true), "+12", "signed flat")
	assert_eq(ProgressionText.value("max_hp", "percent", -0.045, true), "−4,5 %", "signed pct")
	assert_eq(ProgressionText.range_text("crit_chance", "flat", [0.02, 0.04]), "2-4", "range")
	assert_eq(ProgressionText.rune_name("rune.ember", 2), "Braise II", "rune tier")


func tr_text(key: String) -> String:
	return TranslationServer.translate(key)


func test_shopkeeper_screens_show_portrait_and_name() -> void:
	_new_game()
	var names := {"forge": "Bastien", "runecarver": "Maëlle", "merchant": "Rosalie"}
	for id: String in names:
		var screen := _open(id)
		var portrait := _control(id + ".npc_portrait") as TextureRect
		assert_true(portrait != null and portrait.texture != null, "%s: portrait" % id)
		assert_eq(_text(id + ".npc_name"), names[id], "%s: name" % id)
		_close(screen)
	var bag := _open("bag")
	assert_true(_control("bag.npc_portrait") == null, "no shopkeeper on the bag screen")
	_close(bag)
