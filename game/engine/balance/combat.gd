class_name BalanceCombat
extends RefCounted
## Combat constants and formulas (docs/GAME_BALANCE.md §0 and §3-§8, GDD §7).
## Values are hypotheses [H] until the bench (§22) and playtests confirm them.
## Every formula takes its random draws as parameters, so it stays pure and
## its worked examples can be tested exactly.

# --- §0 Conventions -----------------------------------------------------------
const TICK_SECONDS := 0.05

# --- §3 Damage ----------------------------------------------------------------
const DEFENSE_K_BASE := 40.0
const DEFENSE_K_PER_LEVEL := 8.0
const DAMAGE_VARIANCE := 0.08
const ENEMY_DAMAGE_REDUCTION_CAP := 0.45

# --- §4 Elements and reactions -----------------------------------------------
const AFFINITY_WEAK := 1.5
const AFFINITY_NEUTRAL := 1.0
const AFFINITY_RESIST := 0.6
const BARRIER_ARCANE_MULT := 2.0
const REACTION_MELT_MULT := 1.5
const REACTION_OVERLOAD_COEFF := 0.8
const REACTION_OVERLOAD_RADIUS_M := 3.0
const SHOCK_BONUS := 0.15

# --- §5 Fern's kit ------------------------------------------------------------
const GLOBAL_COOLDOWN_S := 0.5
const REPOSITION_HOLD_S := 4.0
const INPUT_BUFFER_S := 0.30
const INTERRUPT_STUN_S := 1.0
const VEILED_MANA_BONUS := 0.30
const VEILED_MANA_DELAY_S := 4.0
const ALLY_DODGE_REACTION_S := 0.4
## Share of the ultimate's rays aimed at the focused target (§5).
const ULT_FOCUS_SHARE := 0.5

# --- §6 Mana, cooldowns, haste ------------------------------------------------
const AUTO_MANA_RESTORE := 3.0
const OOC_DELAY_S := 2.0
const OOC_HP_PCT_PER_S := 0.10
const DUNGEON_OOC_HP_PCT_PER_S := 0.0
const OOC_MANA_PCT_PER_S := 0.20
const MANA_COST_REDUCTION_CAP := 0.40
const COOLDOWN_REDUCTION_CAP := 0.40

# --- §7 Ultimate charge -------------------------------------------------------
const ULT_CHARGE_MAX := 100.0
const ULT_CHARGE_PER_AUTO := 2.0
const ULT_CHARGE_PER_ACTIVE := 5.0
const ULT_CHARGE_PER_HP_PCT_LOST := 0.5
const FRONT_ROW_ULT_CHARGE_MULT := 1.2

# --- §8 Heals and shields -----------------------------------------------------
const SHIELD_HP_RATIO := 0.25
const SHIELD_POWER_COEFF := 1.5
const SHIELD_DURATION_S := 4.0
const HEALING_DRAUGHT_PCT := 0.35
const MANA_ELIXIR_AMOUNT := 50.0
const CONSUMABLE_SHARED_CD_S := 20.0
const CONSUMABLE_CARRY_MAX := 5

# --- §16 Spell ranks ----------------------------------------------------------
const SPELL_RANK_STEP := 0.12

# --- Simulation layout (GDD §7.3, §9.1; not tuned by the bench) ---------------
## Front row defense bonus (GDD §7.3).
const FRONT_ROW_DEFENSE_BONUS := 0.15
## Distance between the front row and the centre of the pack at contact.
const FORMATION_FRONT_DISTANCE_M := 6.0
## The back row starts this much further from the enemies (GDD §7.3).
const BACK_ROW_EXTRA_DISTANCE_M := 4.0
const FORMATION_SLOT_SPACING_M := 2.0
const ENEMY_SPAWN_SPACING_M := 2.0
## Combat area bounded by the mist ring (GDD §5.4).
const ARENA_RADIUS_M := 16.0
const UNIT_RADIUS_M := 0.5
## Units stop this far inside their range when they approach.
const RANGE_MARGIN_M := 0.5
const PROJECTILE_SPEED_MPS := 25.0
const TELEGRAPH_MIN_S := 0.6
const TELEGRAPH_LINE_WIDTH_M := 1.5
const TELEGRAPH_CONE_DEG := 60.0
## Extra distance taken when stepping out of a zone.
const DODGE_MARGIN_M := 0.3
## A fight without enrage stops as a defeat after this long.
const COMBAT_TIMEOUT_S := 600.0

# --- Tactics defaults (GDD §7.4) ----------------------------------------------
## (provisoire, jalon 6) 0.5 -> 0.3: under 30 % an unshielded Ash Seal kills
## anyway, so the fallback never steals the Barrier from a survivable Seal.
const TACTIC_BARRIER_HP_DEFAULT := 0.3
const TACTIC_BARRIER_HP_MIN := 0.3
const TACTIC_BARRIER_HP_MAX := 0.7
const TACTIC_MANA_RESERVE_DEFAULT := 0.2
const TACTIC_MANA_RESERVE_MAX := 0.5
const TACTIC_MIN_ENEMIES_DEFAULT := 3
## "Auto before a telegraphed hit": cast the shield when the hit lands within.
const TACTIC_BARRIER_PRECAST_S := 1.0


## Seconds to ticks: ceil(s / TICK_SECONDS), robust to float noise.
static func ticks(seconds: float) -> int:
	return maxi(0, ceili(seconds / TICK_SECONDS - 0.000001))


## K(L_att) = DEFENSE_K_BASE + DEFENSE_K_PER_LEVEL × L_att
static func defense_k(attacker_level: int) -> float:
	return DEFENSE_K_BASE + DEFENSE_K_PER_LEVEL * float(attacker_level)


## mitigation = K / (K + defense)
static func mitigation(attacker_level: int, defense: float) -> float:
	var k := defense_k(attacker_level)
	return k / (k + maxf(defense, 0.0))


## rank_mult(r) = 1 + SPELL_RANK_STEP × (r − 1)
static func rank_mult(rank: int) -> float:
	return 1.0 + SPELL_RANK_STEP * float(maxi(rank, 1) - 1)


## brut = power × coeff × rank_mult × bonus, bonus = 1 + Σ additive bonuses.
static func raw_damage(power: float, coeff: float, rank: int, bonus_sum: float) -> float:
	return power * coeff * rank_mult(rank) * (1.0 + bonus_sum)


static func affinity_mult(affinity: String) -> float:
	match affinity:
		"weak":
			return AFFINITY_WEAK
		"resist":
			return AFFINITY_RESIST
	return AFFINITY_NEUTRAL


## True when the roll (uniform in [0, 1)) is a critical hit.
static func is_crit(roll: float, crit_chance: float, spell_crit_bonus: float = 0.0) -> bool:
	return roll < minf(crit_chance + spell_crit_bonus, BalanceStats.CRIT_CHANCE_CAP)


## variance = uniform(1 − V, 1 + V), from a roll in [0, 1).
static func variance_from_roll(roll: float) -> float:
	return 1.0 - DAMAGE_VARIANCE + 2.0 * DAMAGE_VARIANCE * roll


## final = brut × mitigation × affinity × reaction × (1 + shock) × crit × variance
##         × (1 − resist_all) × (1 − reduction)
static func final_damage(
	raw: float,
	mitigation_value: float,
	affinity: float,
	reaction: float,
	shock: float,
	crit: float,
	variance: float,
	resist_all: float,
	reduction: float
) -> float:
	return (
		raw
		* mitigation_value
		* affinity
		* reaction
		* (1.0 + shock)
		* crit
		* variance
		* (1.0 - clampf(resist_all, 0.0, BalanceStats.RESIST_CAP))
		* (1.0 - clampf(reduction, 0.0, ENEMY_DAMAGE_REDUCTION_CAP))
	)


## Displayed amount of a hit: one rounding at the end, minimum 1.
static func round_damage(value: float) -> int:
	return maxi(1, roundi(value))


## Applies `final` to an absorbing layer (shield or barrier). `layer_mult` is
## BARRIER_ARCANE_MULT for an arcane hit on a barrier, 1 otherwise.
## Returns {absorbed (layer points used), layer_left, hp_damage (float)}.
static func absorb(final: float, layer: float, layer_mult: float = 1.0) -> Dictionary:
	if layer <= 0.0:
		return {"absorbed": 0.0, "layer_left": 0.0, "hp_damage": final}
	var scaled := final * layer_mult
	if scaled <= layer:
		return {"absorbed": scaled, "layer_left": layer - scaled, "hp_damage": 0.0}
	return {"absorbed": layer, "layer_left": 0.0, "hp_damage": (scaled - layer) / layer_mult}


## Effective cooldown: cd × (1 − cooldown_reduction) / (1 + haste).
static func cooldown_eff(cooldown_s: float, haste: float, reduction: float = 0.0) -> float:
	return (
		cooldown_s
		* (1.0 - clampf(reduction, 0.0, COOLDOWN_REDUCTION_CAP))
		/ (1.0 + clampf(haste, 0.0, BalanceStats.HASTE_CAP))
	)


## Auto-attack interval, cast and channel times: s / (1 + haste).
static func hasted(seconds: float, haste: float) -> float:
	return seconds / (1.0 + clampf(haste, 0.0, BalanceStats.HASTE_CAP))


static func mana_cost_eff(cost: float, reduction: float = 0.0) -> float:
	return cost * (1.0 - clampf(reduction, 0.0, MANA_COST_REDUCTION_CAP))


## Mana income per second: mana_regen + AUTO_MANA_RESTORE / interval_eff.
static func mana_income(mana_regen: float, auto_interval_eff: float) -> float:
	return mana_regen + AUTO_MANA_RESTORE / auto_interval_eff


## shield = (SHIELD_HP_RATIO × max_hp + SHIELD_POWER_COEFF × power)
##          × rank_mult × (1 + shield_bonus)
static func shield_amount(max_hp: float, power: float, rank: int, shield_bonus: float) -> float:
	return (
		(SHIELD_HP_RATIO * max_hp + SHIELD_POWER_COEFF * power)
		* rank_mult(rank)
		* (1.0 + shield_bonus)
	)


## Ultimate charge gained when losing `hp_lost` of `max_hp`.
static func ult_charge_from_damage(hp_lost: float, max_hp: float, front_row: bool) -> float:
	if max_hp <= 0.0:
		return 0.0
	var pct := hp_lost / max_hp * 100.0
	return pct * ULT_CHARGE_PER_HP_PCT_LOST * (FRONT_ROW_ULT_CHARGE_MULT if front_row else 1.0)
