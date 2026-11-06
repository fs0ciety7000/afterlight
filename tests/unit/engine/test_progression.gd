extends TestCase
## GAME_BALANCE §12 table: xp_to_next rounded to tens.

## Criterion 4.1: GAME_BALANCE §12 table, L1 to L19.
const XP_TABLE := [
	40,
	240,
	700,
	1470,
	2630,
	4220,
	6300,
	8920,
	12100,
	15920,
	20400,
	25580,
	31500,
	38190,
	45700,
	54050,
	63270,
	73400,
	84470,
]


func test_xp_curve_matches_the_balance_table() -> void:
	for level in range(1, 20):
		assert_eq(BalanceProgression.xp_to_next(level), XP_TABLE[level - 1], "L%d" % level)
	assert_eq(BalanceProgression.xp_to_next(20), 0, "cap")
	var total := 0
	for v in XP_TABLE:
		total += v
	assert_eq(total, 489100, "cumulated XP to reach L20")


func test_grant_xp_levels_up_once_or_several_times() -> void:
	assert_eq(
		BalanceProgression.grant_xp(1, 0, 30),
		{"level": 1, "xp": 30, "levels_gained": 0, "wasted": 0},
		"no level"
	)
	assert_eq(
		BalanceProgression.grant_xp(1, 30, 20),
		{"level": 2, "xp": 10, "levels_gained": 1, "wasted": 0},
		"one level"
	)
	assert_eq(
		BalanceProgression.grant_xp(1, 0, 980),
		{"level": 4, "xp": 0, "levels_gained": 3, "wasted": 0},
		"three levels"
	)


func test_surplus_at_the_cap_is_wasted() -> void:
	var r := BalanceProgression.grant_xp(19, 0, BalanceProgression.xp_to_next(19) + 500)
	assert_eq(r["level"], 20, "capped")
	assert_eq(r["wasted"], 500, "wasted")
