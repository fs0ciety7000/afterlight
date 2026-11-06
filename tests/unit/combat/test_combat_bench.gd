extends TestCase
## Reduced balance bench (GAME_BALANCE §22.1, ROADMAP 3.3): fewer seeds than
## tools/combat_bench.gd (200 per line), same targets. Seeds are fixed, so the
## result is reproducible; the full run gives the reported numbers.


func test_normal_encounters_idle_typical() -> void:
	for n in [
		["encounter.whispering_wood_02", 1],
		["encounter.whispering_wood_03", 2],
		["encounter.whispering_wood_04", 2],
		["encounter.whispering_wood_05", 3],
		["encounter.lantern_mire_01", 4],
		["encounter.watch_ruins_01", 7],
	]:
		var r := CombatBench.bench(n[0], n[1], "typical", "idle", 8)
		assert_true(r["win_rate"] >= 0.95, "%s win %s" % [n[0], r])
		assert_true(r["p50"] <= 30.0, "%s p50 %s" % [n[0], r])


func test_normal_encounters_idle_unlucky() -> void:
	for n in [["encounter.whispering_wood_02", 1], ["encounter.whispering_wood_04", 2]]:
		var r := CombatBench.bench(n[0], n[1], "unlucky", "idle", 8)
		assert_true(r["win_rate"] >= 0.85, "%s win %s" % [n[0], r])


func test_first_fight_is_won_without_gear() -> void:
	var r := CombatBench.bench("encounter.whispering_wood_01", 1, "bare", "idle", 8)
	assert_true(r["win_rate"] >= 0.95, "first fight %s" % r)


func test_elite() -> void:
	var idle := CombatBench.bench("encounter.cloister_alpha", 10, "typical", "idle", 30)
	assert_true(idle["win_rate"] >= 0.3 and idle["win_rate"] <= 0.6, "idle %s" % idle)
	var best := CombatBench.bench("encounter.cloister_alpha", 10, "typical", "script_optimal", 5)
	assert_true(best["win_rate"] >= 0.9, "script %s" % best)


func test_boss() -> void:
	var idle := CombatBench.bench("encounter.cloister_boss", 11, "typical", "idle", 3)
	assert_true(idle["win_rate"] <= 0.2, "idle %s" % idle)
	var confused := CombatBench.bench("encounter.cloister_boss", 11, "typical", "confused", 3)
	assert_true(confused["win_rate"] <= 0.1, "confused %s" % confused)
	var best := CombatBench.bench("encounter.cloister_boss", 11, "typical", "script_optimal", 10)
	assert_true(best["win_rate"] >= 0.8, "script %s" % best)
	assert_true(best["p50"] >= 150.0 and best["p50"] <= 210.0, "duration %s" % best)
