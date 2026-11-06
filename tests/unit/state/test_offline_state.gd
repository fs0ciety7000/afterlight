extends TestCase
## GameState side of the offline progression (ROADMAP 5.3, 5.7, 5.8): the
## clock goes through now_unix() (test offset on the test channel only), a
## loaded save settles its absence once, the claim credits once and saves.
## Saves go to a throwaway folder, never to the real slot.

const WOLVES := "encounter.whispering_wood_02"
const H := 3600
const P := preload("res://tests/unit/engine/progression_fixtures.gd")

var _real_store: SaveStore


func _begin() -> void:
	_real_store = SaveService.store
	SaveService.store = SaveStore.new("user://test_saves/offline_%d" % Time.get_ticks_usec())
	GameState.test_channel = false
	GameState.debug_clock_offset_s = 0


func _end() -> void:
	SaveService.store = _real_store
	GameState.test_channel = false
	GameState.debug_clock_offset_s = 0
	GameState.clear()


## A level 3 Fern who beat the wolves and hunts them offline since `since`.
func _hunting(since: int) -> Dictionary:
	var s := P.state(0, {}, 3)
	s["progress"]["cleared_encounters"][WOLVES] = 1
	s["farming"] = WOLVES
	s["meta"]["last_active_at"] = since
	return s


func test_clock_offset_only_on_the_test_channel() -> void:
	_begin()
	var wall := int(Time.get_unix_time_from_system())
	GameState.debug_clock_offset_s = 3 * H
	assert_true(GameState.now_unix() - wall < 5, "ignored off the test channel")
	GameState.test_channel = true
	assert_true(absi(GameState.now_unix() - wall - 3 * H) < 5, "honoured with ?test=1")
	GameState.test_advance_clock(H)
	assert_eq(GameState.debug_clock_offset_s, 4 * H, "advanced")
	_end()


func test_loaded_save_settles_once_and_claim_credits_once() -> void:
	_begin()
	GameState.adopt(_hunting(GameState.now_unix() - 3 * H))
	var summary := GameState.pending_offline_summary()
	assert_eq(summary.get("status", ""), "ok", "summary after 3 h")
	assert_true(summary["counted_s"] >= 3 * H, "3 h counted")
	assert_true(not summary["lines"].is_empty(), "lines")
	assert_true(GameState.summary()["offline_pending"], "probe sees it")
	assert_true(SaveService.store.has_main(), "pending summary saved (%s)" % SaveService.last_error)
	assert_eq(GameState.compute_offline(), summary, "nothing new while it waits")
	var r := GameState.claim_offline()
	assert_true(r["ok"], "claimed")
	assert_true(not r.has("state"), "no state in the result")
	assert_eq(GameState.data["wallet"]["gold"], summary["gold"], "gold credited")
	assert_eq(GameState.pending_offline_summary(), {}, "cleared")
	assert_eq(GameState.claim_offline()["error"], "error.offline.nothing_to_claim", "once")
	var reloaded := SaveService.store.read()
	assert_eq(reloaded["status"], "ok", "saved after the claim")
	GameState.adopt(reloaded["decoded"]["state"])
	assert_eq(GameState.pending_offline_summary(), {}, "a reload credits nothing")
	assert_eq(GameState.data["wallet"]["gold"], summary["gold"], "gold unchanged")
	_end()


func test_three_hours_on_the_test_clock() -> void:
	_begin()
	GameState.test_channel = true
	var s := _hunting(GameState.now_unix())
	GameState.debug_clock_offset_s = 3 * H
	GameState.adopt(s)
	var summary := GameState.pending_offline_summary()
	assert_true(absi(int(summary.get("counted_s", 0)) - 3 * H) < 5, "3 h on the test clock")
	_end()


func test_clock_moved_back_keeps_the_stamp() -> void:
	_begin()
	var future := GameState.now_unix() + H
	GameState.adopt(_hunting(future))
	var summary := GameState.pending_offline_summary()
	assert_eq(summary.get("status", ""), "clock", "clock summary")
	assert_eq(summary["gold"], 0, "no gain")
	assert_eq(GameState.data["meta"]["last_active_at"], future, "stamp kept")
	SaveService.save_now()
	assert_eq(GameState.data["meta"]["last_active_at"], future, "a save keeps it too")
	_end()


func test_import_does_not_settle_the_absence() -> void:
	_begin()
	GameState.adopt(_hunting(GameState.now_unix() - 5 * H), false)
	assert_eq(GameState.pending_offline_summary(), {}, "no summary on import")
	_end()


func test_offline_hunt_choice_and_hunt_here() -> void:
	_begin()
	GameState.adopt(_hunting(GameState.now_unix()))
	var boss := GameState.offline_hunt_quote("encounter.cloister_boss")
	assert_eq(boss["error"], "error.offline.not_normal", "boss refused")
	assert_true(GameState.reason_text(boss) != "", "reason text")
	assert_true(not GameState.set_offline_hunt("encounter.whispering_wood_05")["ok"], "not won")
	var refused := GameState.start_hunt_here("encounter.whispering_wood_05")
	assert_eq(refused["error"], "error.hunt.not_cleared", "hunt here needs a win")
	GameState.data["farming"] = ""
	var started := GameState.start_hunt_here(WOLVES)
	assert_true(started["ok"] and started["offline_hunt"], "started")
	assert_eq(GameState.offline_hunt(), WOLVES, "becomes the offline hunt")
	var a := GameState.next_hunt_setup(WOLVES)
	var b := GameState.next_hunt_setup(WOLVES)
	assert_true(a["seed"] != b["seed"], "a new seed each fight")
	assert_true(not a["first_clear"], "never a first clear")
	var sim := CombatSim.create(a, Content.index())
	assert_eq(sim.error, "", "setup accepted by the simulation")
	assert_true(GameState.hunt_continues({"result": "victory"}), "goes on")
	assert_true(not GameState.hunt_continues({"result": "defeat"}), "stops at a defeat")
	_end()
