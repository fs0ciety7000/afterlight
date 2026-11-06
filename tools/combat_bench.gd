extends SceneTree
## Combat balance bench (docs/GAME_BALANCE.md §22.1), headless.
## Usage: godot --headless --path . --script res://tools/combat_bench.gd [-- seeds [section]]
## Prints win rate, durations and HP left for every target of §22.1 and
## §22.6, then checks determinism on 50 seeds × 6 encounters (ROADMAP 3.1).
## `section`: all (default), normals, starter, elite, boss, determinism.
## Boss lines add the defeat causes (Seal / Cendre totale / other) and the
## Ash Seals shielded / landed.

const NORMALS := [
	["encounter.whispering_wood_01", 1],
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
]
const ELITE := ["encounter.cloister_alpha", 10]
const BOSS := ["encounter.cloister_boss", 11]

## Boss lines of GAME_BALANCE §22.1 and §22.6: [player, level, target].
const BOSS_LINES := [
	["idle", 11, "win <= 20 %"],
	["idle", 14, "win >= 40 %"],
	["idle", 16, "win >= 70 %"],
	["idle", 20, "win >= 90 %"],
	["idle_tuned", 11, "win 40-65 %"],
	["idle_tuned", 12, "win >= 60 %"],
	["idle_tuned", 14, "win >= 85 %"],
	["script_optimal", 11, "win >= 80 %, p50 150-210 s"],
	["confused", 11, "win <= 10 %"],
	["confused", 12, "win <= 10 %"],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 200
	var section: String = args[1] if args.size() > 1 else "all"
	print("seeds per line: %d" % seeds)
	if section in ["all", "starter"]:
		for n in NORMALS.slice(0, 5):
			_line(n[0], n[1], "starter", "idle", seeds, "win >= 95 % (§22.6)")
		_line(NORMALS[3][0], 2, "starter", "idle", seeds, "measured, expected 30-60 %")
	if section in ["all", "normals"]:
		_line(NORMALS[0][0], 1, "bare", "idle", seeds, "first fight, no gear yet (ROADMAP 3.5)")
		for n in NORMALS:
			_line(n[0], n[1], "typical", "idle", seeds, "win >= 95 %, p50 15-30 s")
			_line(n[0], n[1], "unlucky", "idle", seeds, "win >= 85 %")
	if section in ["all", "elite"]:
		_line(ELITE[0], ELITE[1], "typical", "idle", seeds, "win 30-60 %")
		_line(ELITE[0], ELITE[1], "typical", "script_optimal", seeds, "win >= 90 %")
	if section in ["all", "boss"]:
		for b in BOSS_LINES:
			_line(BOSS[0], b[1], "typical", b[0], seeds, b[2])
	if section in ["all", "determinism"]:
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
				+ "  HP p50 %3d %%  int %.1f  low mana %2d %%%s  [%s]  (%d ms)"
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
				_boss_extra(encounter, r),
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


## Defeat causes and shielded / landed Seals (GAME_BALANCE §22.6), boss only.
func _boss_extra(encounter: String, r: Dictionary) -> String:
	if encounter != BOSS[0]:
		return ""
	var c: Dictionary = r["causes"]
	return (
		"  defeats seal %d / enrage %d / other %d  seals shielded %d / %d"
		% [c["seal"], c["enrage"], c["other"], r["seals_shielded"], r["seals"]]
	)
