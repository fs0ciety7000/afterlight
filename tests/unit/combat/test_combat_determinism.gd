extends TestCase
## Same seed + same command stream => same event log hash (ROADMAP 3.1,
## GAME_BALANCE §22.1). The full 50 seeds × 6 encounters run lives in
## tools/combat_bench.gd; this test keeps a fast subset.

const CASES := [
	["encounter.whispering_wood_02", 1, 8],
	["encounter.whispering_wood_05", 3, 8],
	["encounter.lantern_mire_01", 4, 8],
	["encounter.watch_ruins_01", 7, 8],
	["encounter.cloister_alpha", 10, 3],
	["encounter.cloister_boss", 11, 2],
]


## Runs a fight with a fixed command stream; returns the event log hash.
static func run_hash(encounter: String, level: int, seed_value: int) -> String:
	var sim := (
		CombatSim
		. create(
			{
				"encounter": encounter,
				"seed": seed_value,
				"party": [CombatBench.fern(level)],
				"consumables": {"consumable.healing_draught": 2},
			},
			CombatBench.content()
		)
	)
	while not sim.finished and sim.tick < 8000:
		match sim.tick:
			20:
				sim.command({"type": "cast", "spell": "spell.zoltraak"})
			60:
				sim.command({"type": "move_to", "x": 3.0, "z": 7.0})
			140:
				sim.command({"type": "set_tactic", "key": "targeting", "value": "lowest_hp"})
			200:
				sim.command({"type": "use_consumable", "consumable": "consumable.healing_draught"})
		sim.step()
	return CombatSim.hash_events(sim.event_log)


func test_same_seed_same_log() -> void:
	for c in CASES:
		for i in int(c[2]):
			var a := run_hash(c[0], c[1], 100 + i)
			var b := run_hash(c[0], c[1], 100 + i)
			assert_eq(a, b, "%s seed %d" % [c[0], 100 + i])


func test_different_seeds_differ() -> void:
	var a := run_hash("encounter.whispering_wood_02", 1, 1)
	var b := run_hash("encounter.whispering_wood_02", 1, 2)
	assert_true(a != b, "seeds 1 and 2 give different fights")


func test_simulation_runs_without_scene() -> void:
	var sim := CombatSim.create(
		{"encounter": "encounter.whispering_wood_01", "seed": 1, "party": [CombatBench.fern(1)]},
		CombatBench.content()
	)
	assert_true(sim is RefCounted, "plain object")
	sim.run(10)
	assert_eq(sim.tick, 10, "ten ticks")
	for u in sim.units:
		for key in u:
			var t := typeof(u[key])
			assert_true(t != TYPE_OBJECT, "unit field %s is plain data" % key)
