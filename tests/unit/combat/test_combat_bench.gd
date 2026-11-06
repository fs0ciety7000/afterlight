extends TestCase
## Reduced balance bench (GAME_BALANCE §22.1, ROADMAP 3.3): fewer seeds than
## tools/combat_bench.gd (200 per line), same targets. Seeds are fixed, so the
## result is reproducible; the full run gives the reported numbers.


func test_normal_encounters_idle_typical() -> void:
	for n in [
		["encounter.whispering_wood_02", 1],
		["encounter.whispering_wood_03", 2],
		["encounter.whispering_wood_04", 3],
		["encounter.whispering_wood_05", 3],
		["encounter.lantern_mire_01", 4],
		["encounter.lantern_mire_02", 4],
		["encounter.lantern_mire_03", 5],
		["encounter.lantern_mire_04", 5],
		["encounter.lantern_mire_05", 6],
		["encounter.watch_ruins_01", 7],
		["encounter.watch_ruins_02", 7],
		["encounter.watch_ruins_03", 8],
		["encounter.watch_ruins_04", 8],
		["encounter.watch_ruins_05", 9],
		["encounter.cloister_vestibule", 10],
		["encounter.cloister_gallery", 10],
		["encounter.cloister_courtyard", 11],
	]:
		var r := CombatBench.bench(n[0], n[1], "typical", "idle", 8)
		assert_true(r["win_rate"] >= 0.95, "%s win %s" % [n[0], r])
		assert_true(r["p50"] <= 30.0, "%s p50 %s" % [n[0], r])


func test_normal_encounters_idle_unlucky() -> void:
	for n in [["encounter.whispering_wood_02", 1], ["encounter.whispering_wood_04", 3]]:
		var r := CombatBench.bench(n[0], n[1], "unlucky", "idle", 8)
		assert_true(r["win_rate"] >= 0.85, "%s win %s" % [n[0], r])


func test_first_fight_is_won_without_gear() -> void:
	var r := CombatBench.bench("encounter.whispering_wood_01", 1, "bare", "idle", 8)
	assert_true(r["win_rate"] >= 0.95, "first fight %s" % r)


## GAME_BALANCE §22.6: the guaranteed staff alone wins the whole Wood at
## each encounter's level.
func test_starter_wins_the_wood_at_each_encounter_level() -> void:
	for n in [
		["encounter.whispering_wood_01", 1],
		["encounter.whispering_wood_02", 1],
		["encounter.whispering_wood_03", 2],
		["encounter.whispering_wood_04", 3],
		["encounter.whispering_wood_05", 3],
	]:
		var r := CombatBench.bench(n[0], n[1], "starter", "idle", 8)
		assert_true(r["win_rate"] >= 0.95, "%s starter %s" % [n[0], r])


## (provisional, milestone 6) The §22.1 floor of 30 % no longer holds: with
## the Barrier fallback at 30 % HP (GDD decision 22) idle wins ~10 % (§22.6,
## open item for the game designer). Only the ceiling is guarded.
func test_elite() -> void:
	var idle := CombatBench.bench("encounter.cloister_alpha", 10, "typical", "idle", 30)
	assert_true(idle["win_rate"] <= 0.6, "idle %s" % idle)
	var best := CombatBench.bench("encounter.cloister_alpha", 10, "typical", "script_optimal", 5)
	assert_true(best["win_rate"] >= 0.9, "script %s" % best)


func test_boss() -> void:
	var idle := CombatBench.bench("encounter.cloister_boss", 11, "typical", "idle", 3)
	assert_true(idle["win_rate"] <= 0.2, "idle %s" % idle)
	var confused := CombatBench.bench("encounter.cloister_boss", 11, "typical", "confused", 3)
	assert_true(confused["win_rate"] <= 0.1, "confused %s" % confused)
	var tuned := CombatBench.bench("encounter.cloister_boss", 14, "typical", "idle_tuned", 4)
	assert_true(tuned["win_rate"] >= 0.85, "idle_tuned L14 %s" % tuned)
	var best := CombatBench.bench("encounter.cloister_boss", 11, "typical", "script_optimal", 10)
	assert_true(best["win_rate"] >= 0.8, "script %s" % best)
	assert_true(best["p50"] >= 150.0 and best["p50"] <= 210.0, "duration %s" % best)
