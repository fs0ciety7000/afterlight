extends TestCase
## Milestone 5 screens (ROADMAP 5.5, 5.7) built headless: the offline hunt
## choice shows the quote of each encounter and the reason of a disabled
## choice; « Pendant votre absence » shows the pending summary and its claim.
## Saves go to a throwaway folder, never to the real slot.

const HUNTS := "res://game/app/screens/hunts_screen.gd"
const SUMMARY := "res://game/app/screens/offline_summary_screen.gd"
const WOLVES := "encounter.whispering_wood_02"
const H := 3600
const P := preload("res://tests/unit/engine/progression_fixtures.gd")

var _real_store: SaveStore


func _begin() -> void:
	TranslationServer.set_locale("fr")
	_real_store = SaveService.store
	SaveService.store = SaveStore.new("user://test_saves/idle_ui_%d" % Time.get_ticks_usec())
	GameState.test_channel = false
	GameState.debug_clock_offset_s = 0


func _end() -> void:
	SaveService.store = _real_store
	GameState.clear()


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _open(path: String, params: Dictionary = {}) -> Control:
	var screen: Control = (load(path) as GDScript).new()
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


## A level 3 Fern who beat the wolves and hunts them offline since `since`.
func _hunting(since: int) -> Dictionary:
	var s := P.state(0, {}, 3)
	s["progress"]["cleared_encounters"][WOLVES] = 1
	s["farming"] = WOLVES
	s["meta"]["last_active_at"] = since
	return s


func test_hunt_choice_builds_from_a_new_game_with_reasons() -> void:
	_begin()
	GameState.start_new(Content.start())
	# The wood reveals the ruins (elite and boss) on the map.
	GameState.data["world"]["revealed_locations"].append("location.watch_ruins")
	var screen := _open(HUNTS, {"location": "location.whispering_wood"})
	assert_eq(_text("hunts.title"), tr("ui.hunts.title"), "title")
	assert_eq(_text("hunts.current"), tr("ui.hunts.current_none"), "no hunt yet")
	assert_true(_control("hunts.place.whispering_wood") != null, "the wood is listed")
	for short in ["cloister_alpha", "cloister_boss"]:
		var b := _control("hunts.choose." + short) as Button
		assert_true(b != null and b.disabled, short + " disabled")
		assert_eq(
			_text("hunts.choose.%s_reason" % short),
			tr("error.offline.not_normal"),
			short + " reason"
		)
		assert_true(_control("hunts.choose.%s_reason" % short).visible, short + " reason shown")
	var never := _control("hunts.choose.whispering_wood_01") as Button
	assert_true(never != null and never.disabled, "never won: disabled")
	assert_eq(
		_text("hunts.choose.whispering_wood_01_reason"),
		tr("error.offline.not_cleared"),
		"never won: reason"
	)
	assert_true(_control("hunts.place.lantern_mire") != null, "revealed mire listed")
	_close(screen)
	_end()


func test_hunt_choice_quotes_a_won_encounter_and_sets_it() -> void:
	_begin()
	GameState.adopt(_hunting(GameState.now_unix()))
	GameState.data["farming"] = ""
	# The fixture lives in a test region: show the real one.
	GameState.data["world"]["region_id"] = "region.aubelin_vale"
	GameState.data["world"]["revealed_locations"].append("location.whispering_wood")
	var screen := _open(HUNTS)
	var b := _control("hunts.choose.whispering_wood_02") as Button
	assert_true(b != null and not b.disabled, "won encounter enabled")
	assert_true(_text("hunts.stats.whispering_wood_02").contains("XP/h"), "stats shown")
	assert_eq(_text("hunts.choose.whispering_wood_02_reason"), "", "no reason")
	b.pressed.emit()
	assert_eq(GameState.offline_hunt(), WOLVES, "hunt set")
	assert_true(_text("hunts.status").ends_with(Content.display_name(WOLVES)), "status line")
	_close(screen)
	_end()


func test_absence_summary_shows_the_gains_then_claims_once() -> void:
	_begin()
	GameState.adopt(_hunting(GameState.now_unix() - 3 * H))
	var summary: Dictionary = GameState.pending_offline_summary()
	assert_eq(summary.get("status", ""), "ok", "summary waits")
	assert_eq(OfflineSummaryScreen.entry_screen(), "offline_summary", "shown after a load")
	var screen := _open(SUMMARY)
	assert_eq(_text("offline.title"), tr("ui.offline.title"), "title")
	assert_eq(_text("offline.gold"), "+%d" % summary["gold"], "gold")
	assert_eq(_text("offline.xp"), "+%d" % summary["xp"], "xp")
	assert_eq(_text("offline.clears"), str(floori(float(summary["clears"]))), "clears")
	assert_eq(
		_text("offline.duration"),
		tr("ui.offline.counted").format(
			{"duration": Kit.format_duration(int(summary["counted_s"]))}
		),
		"duration"
	)
	assert_true(not _control("offline.capped").visible, "3 h is under the cap")
	var claim := _control("offline.claim") as Button
	assert_true(claim != null and not claim.disabled, "Récupérer enabled")
	_close(screen)
	var r: Dictionary = GameState.claim_offline()
	assert_true(r["ok"], "claimed")
	assert_eq(GameState.data["wallet"]["gold"], summary["gold"], "credited")
	assert_eq(OfflineSummaryScreen.entry_screen(), "explore", "not shown again")
	_end()


func test_unsafe_absence_explains_why_nothing_is_credited() -> void:
	_begin()
	var s := _hunting(GameState.now_unix() - 9 * H)
	s["characters"][s["party"][0]]["level"] = 1
	s["progress"]["cleared_encounters"]["encounter.whispering_wood_04"] = 1
	s["farming"] = "encounter.whispering_wood_04"
	GameState.adopt(s)
	var summary: Dictionary = GameState.pending_offline_summary()
	assert_eq(summary.get("status", ""), "unsafe", "level 1 does not survive the pack")
	var screen := _open(SUMMARY)
	assert_true(_text("offline.warning").begins_with("Fern ne tiendrait que"), "reason shown")
	assert_true(_control("offline.gold") == null, "no gains listed")
	assert_true(_control("offline.claim") != null, "the claim clears it")
	_close(screen)
	_end()
