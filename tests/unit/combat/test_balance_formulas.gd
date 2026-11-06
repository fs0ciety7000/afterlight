extends TestCase
## Worked examples of docs/GAME_BALANCE.md, to the hundredth (ROADMAP 3.2).


func test_stat_derivation_example_2_2() -> void:
	# Fern L10: power (70.5 + 20.98) × 1.08, max_hp (762 + 108.4) × 1.05.
	var staff := 6.0 * 2.35 * 1.2 * (1.0 + 0.06 * 4)
	var robe := 40.0 * 2.20 * 1.1 * 1.12
	var s := BalanceStats.derive(
		{"power": 30, "max_hp": 420},
		{"power": 4.5, "max_hp": 38},
		10,
		{"power": staff, "max_hp": robe},
		{"power": 0.08, "max_hp": 0.05}
	)
	assert_near(s["power"], 98.80, 0.01, "power")
	assert_near(s["max_hp"], 913.9, 0.05, "max_hp")


func test_stat_caps() -> void:
	var s := BalanceStats.derive({"crit_chance": 0.9, "haste": 2.0}, {}, 1)
	assert_eq(s["crit_chance"], BalanceStats.CRIT_CHANCE_CAP, "crit cap")
	assert_eq(s["haste"], BalanceStats.HASTE_CAP, "haste cap")


func test_damage_example_3() -> void:
	# Zoltraak (power 98.8, rank 2, veiled) on a level 10 sentinel.
	assert_near(BalanceCombat.defense_k(10), 120.0, 0.001, "K(10)")
	var defense := BalanceEnemies.defense(0.6, 10)
	assert_near(defense, 72.0, 0.001, "sentinel defense")
	var mit := BalanceCombat.mitigation(10, defense)
	assert_near(mit, 0.625, 0.0001, "mitigation")
	var raw := BalanceCombat.raw_damage(98.8, 3.2, 2, 0.30)
	assert_near(raw, 460.3, 0.05, "raw")
	var final := BalanceCombat.final_damage(raw, mit, 1.0, 1.0, 0.0, 1.0, 1.03, 0.0, 0.0)
	assert_near(final, 296.3, 0.05, "final with variance 1.03")
	var crit := BalanceCombat.final_damage(raw, mit, 1.0, 1.0, 0.0, 1.5, 1.03, 0.0, 0.0)
	assert_near(crit, 444.5, 0.05, "critical")
	var barrier := BalanceEnemies.barrier(0.25, 1222.0)
	assert_near(barrier, 305.5, 0.001, "barrier")
	var r := BalanceCombat.absorb(final, barrier, BalanceCombat.BARRIER_ARCANE_MULT)
	assert_eq(r["layer_left"], 0.0, "barrier broken")
	assert_near(r["hp_damage"], 143.6, 0.05, "surplus")
	assert_eq(roundi(r["hp_damage"]), 144, "HP lost")


func test_crit_and_variance_rolls() -> void:
	assert_true(BalanceCombat.is_crit(0.04, 0.05), "under chance")
	assert_true(not BalanceCombat.is_crit(0.05, 0.05), "at chance")
	assert_true(not BalanceCombat.is_crit(0.61, 0.9), "capped at 0.60")
	assert_near(BalanceCombat.variance_from_roll(0.0), 0.92, 0.0001, "low")
	assert_near(BalanceCombat.variance_from_roll(0.5), 1.0, 0.0001, "mid")
	assert_eq(BalanceCombat.round_damage(0.2), 1, "minimum 1")


func test_affinities_reactions_and_reduction() -> void:
	assert_eq(BalanceCombat.affinity_mult("weak"), 1.5, "weak")
	assert_eq(BalanceCombat.affinity_mult("resist"), 0.6, "resist")
	assert_eq(BalanceCombat.affinity_mult("neutral"), 1.0, "neutral")
	var melt := BalanceCombat.final_damage(100.0, 1.0, 1.0, 1.5, 0.15, 1.0, 1.0, 0.0, 0.0)
	assert_near(melt, 172.5, 0.001, "melt and shock")
	var capped := BalanceCombat.final_damage(100.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 0.9, 0.9)
	assert_near(capped, 100.0 * 0.5 * 0.55, 0.001, "resist and reduction caps")


func test_mana_and_haste_section_6() -> void:
	assert_near(BalanceCombat.mana_income(4.0, 1.2), 6.5, 0.001, "income")
	var spend := 25.0 / 6.0 + 35.0 / 10.0 + 30.0 / 18.0
	assert_near(spend, 9.33, 0.005, "spend")
	assert_near(6.5 / spend, 0.696, 0.001, "sustained ratio")
	assert_near(100.0 / (spend - 6.5), 35.3, 0.05, "full pool lasts")
	assert_near(BalanceCombat.cooldown_eff(10.0, 0.25, 0.2), 6.4, 0.0001, "cooldown")
	assert_near(BalanceCombat.cooldown_eff(10.0, 0.0, 0.9), 6.0, 0.0001, "reduction cap")
	assert_near(BalanceCombat.hasted(1.2, 0.2), 1.0, 0.0001, "hasted interval")
	assert_near(BalanceCombat.mana_cost_eff(35.0, 0.5), 21.0, 0.0001, "cost cap")


func test_ult_charge_section_7() -> void:
	var rate := 2.0 / 1.2 + 5.0 * (1.0 / 6.0 + 1.0 / 10.0 + 1.0 / 18.0) * 0.696
	assert_near(rate, 2.79, 0.005, "sustained charge per second")
	assert_near(BalanceCombat.ult_charge_from_damage(100.0, 1000.0, false), 5.0, 0.0001, "back")
	assert_near(BalanceCombat.ult_charge_from_damage(100.0, 1000.0, true), 6.0, 0.0001, "front")


func test_shield_example_8() -> void:
	var s := BalanceCombat.shield_amount(914.0, 98.8, 1, 0.0)
	assert_near(s, 376.7, 0.01, "shield")
	assert_near(s / 914.0, 0.41, 0.005, "share of HP")
	assert_near(BalanceCombat.shield_amount(914.0, 98.8, 3, 0.1), 376.7 * 1.24 * 1.1, 0.02, "rank")


func test_burn_tick() -> void:
	# 0.15 × power per second and per stack, ticking every 0.5 s.
	assert_near(BalanceStatuses.burn_tick_raw(100.0, 2, 0.5), 15.0, 0.0001, "burn")


func test_enemy_scaling_example_10() -> void:
	assert_near(BalanceEnemies.hp(300, 5), 480.0, 0.001, "wolf L5 HP")
	assert_near(BalanceEnemies.power(14, 5), 19.32, 0.01, "wolf L5 power")
	assert_near(BalanceEnemies.defense(0.2, 5), 16.0, 0.001, "wolf L5 defense")
	assert_near(BalanceEnemies.hp(1800, 11), 4500.0, 0.001, "alpha L11")
	assert_near(BalanceEnemies.hp(7500, 12), 19875.0, 0.001, "Morvaine L12")


func test_encounter_budget_and_ehp_section_11() -> void:
	assert_near(BalanceEnemies.encounter_ehp_budget(1), 1080.0, 0.001, "L1")
	var m := BalanceCombat.mitigation(1, BalanceEnemies.defense(0.2, 1))
	assert_near(3.0 * BalanceEnemies.effective_hp(300, 0, m, 1.0, 2.0), 1080.0, 0.01, "3 wolves")
	var boss_m := BalanceCombat.mitigation(11, BalanceEnemies.defense(0.35, 12))
	assert_near(boss_m, 0.729, 0.001, "boss mitigation")
	var boss := BalanceEnemies.effective_hp(19875, 0, boss_m, 1.0, 2.0)
	assert_near(boss, 27263.0, 30.0, "boss EHP")


func test_xp_and_penalty_section_12() -> void:
	assert_near(BalanceEnemies.enemy_xp(1, 1.0), 8.0, 0.0001, "L1 wolf")
	assert_near(3.0 * BalanceEnemies.enemy_xp(10, 1.0), 78.0, 0.0001, "3 enemies L10")
	assert_eq(BalanceEnemies.xp_penalty(10, 8), 1.0, "gap 2")
	assert_near(BalanceEnemies.xp_penalty(10, 7), 0.8, 0.0001, "gap 3")
	assert_near(BalanceEnemies.xp_penalty(20, 1), 0.2, 0.0001, "floor")


func test_gold_section_13() -> void:
	assert_near(BalanceEnemies.enemy_gold(1, 1.0, 1.0, 0.0), 4.0, 0.0001, "L1")
	assert_near(BalanceEnemies.enemy_gold(7, 1.0, 1.0, 0.0), 8.8, 0.0001, "L7 (§20.4)")
	assert_near(BalanceEnemies.enemy_gold(1, 1.0, 1.0, 5.0), 8.0, 0.0001, "gold_find cap")


func test_ticks_and_ranks() -> void:
	assert_eq(BalanceCombat.ticks(0.3), 6, "0.3 s")
	assert_eq(BalanceCombat.ticks(1.2), 24, "1.2 s")
	assert_eq(BalanceCombat.ticks(0.61), 13, "ceil")
	assert_near(BalanceCombat.rank_mult(5), 1.48, 0.0001, "rank 5")
