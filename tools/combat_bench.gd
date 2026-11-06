extends SceneTree
## Combat balance bench (docs/GAME_BALANCE.md §22.1), headless.
## Usage: godot --headless --path . --script res://tools/combat_bench.gd [-- seeds]
## Prints win rate, durations and HP left for every target of §22.1, then
## checks determinism on 50 seeds × 6 encounters (ROADMAP 3.1).

const NORMALS := [
	["encounter.whispering_wood_01", 1],
	["encounter.whispering_wood_02", 1],
	["encounter.whispering_wood_03", 2],
	["encounter.whispering_wood_04", 2],
	["encounter.whispering_wood_05", 3],
	["encounter.lantern_mire_01", 4],
	["encounter.watch_ruins_01", 7],
]
const ELITE := ["encounter.cloister_alpha", 10]
const BOSS := ["encounter.cloister_boss", 11]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 200
	print("seeds per line: %d" % seeds)
	_line(NORMALS[0][0], 1, "bare", "idle", seeds, "first fight, no gear yet (ROADMAP 3.5)")
	for n in NORMALS:
		_line(n[0], n[1], "typical", "idle", seeds, "win >= 95 %, p50 15-30 s")
		_line(n[0], n[1], "unlucky", "idle", seeds, "win >= 85 %")
	_line(ELITE[0], ELITE[1], "typical", "idle", seeds, "win 30-60 %")
	_line(ELITE[0], ELITE[1], "typical", "script_optimal", seeds, "win >= 90 %")
	_line(BOSS[0], BOSS[1], "typical", "idle", seeds, "win <= 20 %")
	_line(BOSS[0], BOSS[1], "typical", "script_optimal", seeds, "win >= 80 %, p50 150-210 s")
	_line(BOSS[0], BOSS[1], "typical", "confused", seeds, "win <= 10 %")
	_determinism()
	quit()


func _line(
	encounter: String, level: int, gear: String, player: String, seeds: int, target: String
) -> void:
	var t0 := Time.get_ticks_msec()
	var r := CombatBench.bench(encounter, level, gear, player, seeds)
	print(
		(
			(
				"%-30s L%-2d %-8s %-15s win %5.1f %%  p50 %6.1f s  p90 %6.1f s"
				+ "  HP p50 %3d %%  int %.1f  low mana %2d %%  [%s]  (%d ms)"
			)
			% [
				encounter.trim_prefix("encounter."),
				level,
				gear,
				player,
				r["win_rate"] * 100.0,
				r["p50"],
				r["p90"],
				roundi(r["hp_p50"] * 100.0),
				r["interrupts"],
				roundi(r["no_mana_pct"] * 100.0),
				target,
				Time.get_ticks_msec() - t0,
			]
		)
	)


func _determinism() -> void:
	var cases := [
		["encounter.whispering_wood_02", 1],
		["encounter.whispering_wood_05", 3],
		["encounter.lantern_mire_01", 4],
		["encounter.watch_ruins_01", 7],
		ELITE,
		BOSS,
	]
	var bad := 0
	for c in cases:
		for i in 50:
			var script: GDScript = load("res://tests/unit/combat/test_combat_determinism.gd")
			var a: String = script.run_hash(c[0], c[1], i)
			var b: String = script.run_hash(c[0], c[1], i)
			if a != b:
				bad += 1
	print("determinism: %d mismatches on 300 fights" % bad)
