extends TestCase
## panel.tactics, tip cards and the danger level tag built headless (GDD
## decisions 23-30): rows with their live sentence, disabled actions with
## their reason, the preset's diff before it applies, the grimoire's entry
## points. Saves go to a throwaway folder, never to the real slot.

const F := preload("res://tests/unit/engine/story_fixtures.gd")
const GRIMOIRE := "res://game/app/screens/grimoire_screen.gd"
const HUNTS := "res://game/app/screens/hunts_screen.gd"
const PRESET := "tactics_preset.morvaine"

var _real_store: SaveStore


func _begin(level: int) -> void:
	TranslationServer.set_locale("fr")
	_real_store = SaveService.store
	SaveService.store = SaveStore.new("user://test_saves/tactics_ui_%d" % Time.get_ticks_usec())
	GameState.adopt(F.state(level), false)


func _end() -> void:
	SaveService.store = _real_store
	GameState.clear()


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _host() -> Control:
	var host := Control.new()
	_root().add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return host


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


func _saved() -> Dictionary:
	return GameState.data["characters"]["character.fern"]["tactics"]


func test_panel_rows_and_live_sentence() -> void:
	_begin(2)
	var host := _host()
	TacticsPanel.open(host)
	assert_eq(_text("tactics.title"), tr("ui.tactics.title"), "title")
	assert_true(_control("tactics.row.targeting") != null, "targeting row")
	assert_true(_control("tactics.row.defensive_barrier") != null, "Barrier row at level 2")
	assert_true(_control("tactics.row.mana_volley") == null, "Volley hidden before level 3")
	assert_true(_control("tactics.row.healing_draught") != null, "consumable row")
	assert_true(_control("tactics.row.mana_reserve") != null, "reserve row")
	assert_eq(
		_text("tactics.say.defensive_barrier"),
		"Fern se protège juste avant un coup annoncé, ou si ses PV passent sous 30 %.",
		"default sentence"
	)
	assert_true(_control("tactics.slider.defensive_barrier").is_visible_in_tree(), "HP slider")
	assert_eq(_text("tactics.value.defensive_barrier"), "30 %", "slider value")
	var opt := _control("tactics.opt.defensive_barrier.auto_telegraph_or_hp") as Button
	assert_eq(opt.theme_type_variation, "PrimaryButton", "current mode highlighted")
	assert_true(opt.text.ends_with(tr("ui.tactics.default_suffix")), "default flagged")

	(_control("tactics.opt.defensive_barrier.auto_before_telegraph") as Button).pressed.emit()
	assert_eq(
		_saved().get("spells", {}),
		{"spell.defensive_barrier": "auto_before_telegraph"},
		"saved at once"
	)
	assert_eq(
		_text("tactics.say.defensive_barrier"),
		"Fern se protège juste avant un coup annoncé au sol ou par une incantation.",
		"sentence follows the mode"
	)
	assert_true(
		not _control("tactics.slider.defensive_barrier").is_visible_in_tree(), "no slider then"
	)
	assert_eq(_text("tactics.status"), tr("ui.tactics.saved"), "status")
	_close(host)
	_end()


func test_slider_saves_its_value() -> void:
	_begin(2)
	var host := _host()
	TacticsPanel.open(host)
	(_control("tactics.slider.defensive_barrier") as HSlider).value = 0.5
	assert_eq(_text("tactics.value.defensive_barrier"), "50 %", "value label")
	assert_true(_text("tactics.say.defensive_barrier").contains("50 %"), "sentence")
	assert_near(float(_saved()["barrier_hp_pct"]), 0.5, 0.001, "saved")
	(_control("tactics.slider.mana_reserve") as HSlider).value = 0.4
	assert_true(_text("tactics.say.mana_reserve").contains("40 %"), "reserve sentence")
	_close(host)
	_end()


func test_reset_is_disabled_with_its_reason_at_the_defaults() -> void:
	_begin(2)
	var host := _host()
	TacticsPanel.open(host)
	var reset := _control("tactics.reset") as Button
	assert_true(reset.disabled, "nothing to reset")
	assert_eq(_text("tactics.reset_reason"), tr("ui.tactics.reset_none"), "reason")
	assert_true(_control("tactics.reset_reason").is_visible_in_tree(), "reason shown")
	(_control("tactics.opt.targeting.lowest_hp") as Button).pressed.emit()
	assert_true(not reset.disabled, "enabled after a change")
	assert_true(not _control("tactics.reset_reason").is_visible_in_tree(), "reason hidden")
	reset.pressed.emit()
	assert_eq(_saved(), {}, "back to the defaults")
	assert_eq(_text("tactics.status"), tr("ui.tactics.reset_done"), "status")
	assert_true(reset.disabled, "disabled again")
	_close(host)
	_end()


func test_apply_preset_shows_the_diff_first() -> void:
	_begin(12)
	var host := _host()
	TacticsPanel.open(host)
	var apply := _control("tactics.apply_preset") as Button
	assert_true(apply.visible and not apply.disabled, "advice offered")
	apply.pressed.emit()
	assert_true(_control("tactics.diff").is_visible_in_tree(), "diff shown")
	assert_true(
		_text("tactics.diff").contains("Ciblage : Le plus proche → Lanceurs d'abord"), "diff line"
	)
	assert_eq(_saved(), {}, "nothing applied yet")
	(_control("tactics.diff_confirm") as Button).pressed.emit()
	assert_eq(_saved().get("targeting", ""), "casters_first", "applied")
	assert_true(not _control("tactics.diff").is_visible_in_tree(), "diff closed")
	assert_true(apply.disabled, "nothing left to apply")
	assert_eq(_text("tactics.apply_preset_reason"), tr("ui.tactics.diff_none"), "reason")
	_close(host)
	_end()


func test_open_on_the_diff_and_cancel() -> void:
	_begin(12)
	var host := _host()
	var panel := TacticsPanel.open(host, {"preset": PRESET, "show_diff": true})
	assert_true(_control("tactics.diff").is_visible_in_tree(), "opened on the diff")
	(_control("tactics.diff_cancel") as Button).pressed.emit()
	assert_true(not _control("tactics.diff").is_visible_in_tree(), "cancelled")
	assert_eq(_saved(), {}, "nothing applied")
	var closed := [false]
	panel.closed.connect(func() -> void: closed[0] = true)
	(_control("tactics.close") as Button).pressed.emit()
	assert_true(closed[0], "closed signal")
	_close(host)
	_end()


func test_grimoire_opens_tactics_and_shows_badges() -> void:
	_begin(2)
	var screen: Control = (load(GRIMOIRE) as GDScript).new()
	screen.call("setup", {})
	_root().add_child(screen)
	var open := _control("tactics.open.grimoire") as Button
	assert_true(open != null and not open.disabled, "Tactiques button")
	var badge := _control("tactics.badge.defensive_barrier") as Button
	assert_true(badge != null, "Barrier badge")
	assert_eq(
		badge.text,
		tr("ui.tactics.badge").format({"mode": "Avant un coup télégraphé, sinon sous X %"}),
		"badge shows the mode"
	)
	badge.pressed.emit()
	assert_true(_control("tactics.panel") != null, "panel open")
	assert_eq(UiProbe.world.get("tactics_open"), true, "probe")
	_close(screen)
	_end()


func test_tip_card_buttons_and_dismiss() -> void:
	_begin(2)
	var tip := GameState.tactics.next_tip({"trigger": "level_reached", "level": 2})
	assert_eq(tip.get("id", ""), "tip.barrier_unlocked", "Barrier tip at level 2")
	var host := _host()
	var card := TipCard.make(tip, 360.0)
	host.add_child(card)
	assert_eq(_text("tip.title"), tr("tip.barrier_unlocked.name"), "title")
	assert_eq(_text("tip.text"), tr("tip.barrier_unlocked"), "text")
	assert_true(_control("tip.open") != null and _control("tip.close") != null, "buttons")
	assert_true(_control("tip.apply") == null, "no preset to apply")
	var got := []
	card.action.connect(func(id: String) -> void: got.append(id))
	(_control("tip.open") as Button).pressed.emit()
	assert_eq(got, ["open_tactics"], "action")
	assert_true(_control("tip.card") == null, "dismissed")
	_close(host)
	_end()


func test_campfire_tip_offers_the_preset() -> void:
	_begin(12)
	var tip := GameState.tactics.next_tip(
		{"trigger": "first_campfire", "dungeon": "dungeon.silent_dial_cloister"}
	)
	var host := _host()
	host.add_child(TipCard.make(tip, 360.0))
	assert_true(_control("tip.apply") != null, "Appliquer le conseil")
	assert_true(_control("tip.later") != null, "Plus tard")
	_close(host)
	_end()


func test_level_tag_above_is_danger_with_a_pictogram() -> void:
	var above := LevelTag.make(
		{"level": 3, "above": true, "key": "ui.encounter.level_above", "params": {"level": 3}}
	)
	assert_eq(above.label.text, "Niveau 3 (au-dessus du vôtre)", "text")
	assert_eq(above.get_child_count(), 2, "pictogram + text")
	assert_eq(above.label.get_theme_color("font_color"), UiTokens.DAY["danger"], "danger colour")
	var same := LevelTag.make(
		{"level": 2, "above": false, "key": "ui.map.level", "params": {"level": 2}}
	)
	assert_eq(same.label.text, "Niveau 2", "plain")
	assert_eq(same.get_child_count(), 1, "no pictogram")
	above.free()
	same.free()


func test_fern_campfire_dialogue_has_its_second_line() -> void:
	var keys := StoryText.dialogue_lines("dialogue.fern_campfire").map(
		func(l: Dictionary) -> String: return l["key"]
	)
	assert_eq(
		keys, ["dialogue.fern_campfire.line_01", "dialogue.fern_campfire.line_02"], "owner answer 3"
	)


func test_tactics_strings_exist() -> void:
	var keys := ContentLoader.translation_keys("res://game/i18n/strings.csv")
	for key in [
		"dialogue.fern_campfire.line_02",
		"ui.tactics.confirm_preset",
		"ui.tactics.reset_none",
		"ui.tactics.live_hint",
		"ui.tactics.badge",
		"ui.tactics.campfire_hint",
		"ui.encounter.level_above",
	]:
		assert_true(keys.has(key), key)
