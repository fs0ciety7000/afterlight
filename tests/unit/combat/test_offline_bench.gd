extends TestCase
## Offline model against the simulation (ROADMAP 5.6, GAME_BALANCE §22.1):
## the analytical clear_time of each offline-eligible encounter of the slice
## is within 15 % of the simulated p50 (typical gear, idle tactics, same
## level as in test_combat_bench). Fixed seeds: reproducible.

const MAX_GAP := 0.15
const SEEDS := 16
## Encounter -> Fern's level (the bench's "same level" profile).
const LEVELS := {
	"encounter.whispering_wood_01": 1,
	"encounter.whispering_wood_02": 1,
	"encounter.whispering_wood_03": 2,
	"encounter.whispering_wood_04": 2,
	"encounter.whispering_wood_05": 3,
	"encounter.lantern_mire_01": 4,
	"encounter.watch_ruins_01": 7,
}


func test_every_eligible_encounter_is_benched() -> void:
	var c := CombatBench.content()
	for id in c:
		var e: Dictionary = c[id]
		if e.get("_type", "") == "encounter" and e.get("offline_eligible", false):
			assert_true(LEVELS.has(id), "%s has a bench level" % id)


func test_clear_time_matches_the_simulated_p50() -> void:
	var c := CombatBench.content()
	for id in LEVELS:
		var level: int = LEVELS[id]
		var est := OfflineModel.estimate(CombatBench.fern(level, "typical"), id, c)
		var sim := CombatBench.bench(id, level, "typical", "idle", SEEDS)
		var gap := absf(float(est["clear_time_s"]) - float(sim["p50"])) / float(sim["p50"])
		assert_true(
			gap <= MAX_GAP,
			(
				"%s L%d: analytic %.2f s vs p50 %.2f s (%.0f %%)"
				% [id, level, est["clear_time_s"], sim["p50"], gap * 100.0]
			)
		)
