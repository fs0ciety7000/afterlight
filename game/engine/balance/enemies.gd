class_name BalanceEnemies
extends RefCounted
## Enemy scaling, encounter budget and rewards (docs/GAME_BALANCE.md §10-§13).
## Per-enemy values (HP_L1, POWER_L1, def_ratio...) live in enemies.json.

const ENEMY_HP_GROWTH := 0.15
const ENEMY_POWER_GROWTH := 0.095

const MORVAINE_PHASE_2_HP := 0.65
const MORVAINE_PHASE_3_HP := 0.30

## §11: ENCOUNTER_EHP_BUDGET = 1080 × (1 + 0.15 × (Le − 1)) ± 25 %
const ENCOUNTER_EHP_BASE := 1080.0
const ENCOUNTER_EHP_TOLERANCE := 0.25

## §12 XP
const ENEMY_XP_BASE := 8.0
const ENEMY_XP_GROWTH := 0.25
const XP_PENALTY_PER_LEVEL := 0.20
const XP_PENALTY_FLOOR := 0.20
const XP_PENALTY_FREE_GAP := 2
const FIRST_CLEAR_XP_MULT := 3.0

## §13 Gold
const ENEMY_GOLD_BASE := 4.0
const GOLD_GROWTH := 0.20
const GOLD_ROLL_MIN := 0.8
const GOLD_ROLL_MAX := 1.2

## Simulation rules (GDD §9): enemy abilities start the fight with this share
## of their cooldown left, so the first telegraph does not land at once.
const ENEMY_OPENING_CD_FRACTION := 0.5
## A summoner keeps at most this many of its summons alive (bound lanterns,
## howl reinforcements).
const SUMMON_ALIVE_CAP := 4


## hp(Le) = HP_L1 × (1 + ENEMY_HP_GROWTH × (Le − 1))
static func hp(hp_l1: float, level: int) -> float:
	return hp_l1 * (1.0 + ENEMY_HP_GROWTH * float(level - 1))


## power(Le) = POWER_L1 × (1 + ENEMY_POWER_GROWTH × (Le − 1))
static func power(power_l1: float, level: int) -> float:
	return power_l1 * (1.0 + ENEMY_POWER_GROWTH * float(level - 1))


## defense(Le) = def_ratio × K(Le)
static func defense(def_ratio: float, level: int) -> float:
	return def_ratio * BalanceCombat.defense_k(level)


## barrier = barrier_ratio × hp(Le)
static func barrier(barrier_ratio: float, hp_value: float) -> float:
	return barrier_ratio * hp_value


static func encounter_ehp_budget(level: int) -> float:
	return ENCOUNTER_EHP_BASE * (1.0 + ENEMY_HP_GROWTH * float(level - 1))


## PV_effectifs = hp / (mitigation × affinity) + barrier / (mitigation × barrier_mult × affinity)
static func effective_hp(
	hp_value: float, barrier_value: float, mitigation: float, affinity: float, barrier_mult: float
) -> float:
	return (
		hp_value / (mitigation * affinity) + barrier_value / (mitigation * barrier_mult * affinity)
	)


## xp_ennemi(Le) = ENEMY_XP_BASE × (1 + ENEMY_XP_GROWTH × (Le − 1)) × xp_mult
static func enemy_xp(level: int, xp_mult: float) -> float:
	return ENEMY_XP_BASE * (1.0 + ENEMY_XP_GROWTH * float(level - 1)) * xp_mult


## 1 if L − Le ≤ 2, else max(FLOOR, 1 − PER_LEVEL × (gap − 2)).
static func xp_penalty(character_level: int, enemy_level: int) -> float:
	var gap := character_level - enemy_level
	if gap <= XP_PENALTY_FREE_GAP:
		return 1.0
	return maxf(XP_PENALTY_FLOOR, 1.0 - XP_PENALTY_PER_LEVEL * float(gap - XP_PENALTY_FREE_GAP))


## Gold before rounding; `roll` is uniform in [GOLD_ROLL_MIN, GOLD_ROLL_MAX].
static func enemy_gold(level: int, gold_mult: float, roll: float, gold_find: float) -> float:
	return (
		ENEMY_GOLD_BASE
		* (1.0 + GOLD_GROWTH * float(level - 1))
		* gold_mult
		* roll
		* (1.0 + clampf(gold_find, 0.0, BalanceStats.GOLD_FIND_CAP))
	)
