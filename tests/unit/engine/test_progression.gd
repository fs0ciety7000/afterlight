extends TestCase
## GAME_BALANCE §12 table: xp_to_next rounded to tens.


func test_xp_curve_matches_the_balance_table() -> void:
	assert_eq(BalanceProgression.xp_to_next(1), 40, "L1")
	assert_eq(BalanceProgression.xp_to_next(2), 240, "L2")
	assert_eq(BalanceProgression.xp_to_next(3), 700, "L3")
	assert_eq(BalanceProgression.xp_to_next(4), 1470, "L4")
	assert_eq(BalanceProgression.xp_to_next(20), 0, "cap")


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
