class_name BalanceOffline
extends RefCounted
## Offline progression and the "Chasser ici" loop (docs/GAME_BALANCE.md §20).
## Values are hypotheses [H] except OFFLINE_CAP_S and OFFLINE_EFFICIENCY
## (owner decisions).

const OFFLINE_CAP_S := 28800
const OFFLINE_MIN_S := 60
## 8 h offline are worth 2 h of active hunting (owner decision, 2026-11-06).
const OFFLINE_EFFICIENCY := 0.25
## Calibrated on the simulation (§22, jalon 5): 1.0 once the hunting rotation
## follows the default tactics (was 0.85 with the sustained ROT).
const OFFLINE_DPS_CALIBRATION := 1.0
## First hit of a field fight in the simulation: ~0.35 s (jalon 5; was 2.0).
const ENGAGE_S := 0.5
const ENCOUNTER_RESPAWN_S := 6.0
const CLEAR_TIME_MIN_S := 8.0
const CLEAR_TIME_MAX_S := 120.0
const OFFLINE_INCOMING_ALIVE_FACTOR := 0.6
const OFFLINE_SAFETY_FACTOR := 1.25
const OFFLINE_ITEM_KEEP_MAX := 30
const OFFLINE_ITEM_SAMPLE_MAX := 500
const OFFLINE_RUNE_KEEP_MAX := 20
## Rune drops sampled one by one; beyond, salvaged at expectation
## (provisional, jalon 5: same bound as items).
const OFFLINE_RUNE_SAMPLE_MAX := 500
## Weight of the echo chance in ROT: (1 + echo × ECHO_WEIGHT).
const ECHO_WEIGHT := 0.5
## Fixed-point steps settling fight time and mana ratio (not a tuning value).
const FIXED_POINT_STEPS := 6
## Float fields of a saved summary are snapped to this step, so they survive
## the JSON round trip of the save checksum (see BalanceItems.AFFIX_VALUE_STEP).
const SUMMARY_FLOAT_STEP := 0.000001


## Share of the mana pool at the start of a hunting fight: out-of-combat
## regeneration during the respawn, min(1, (RESPAWN − OOC_DELAY) × OOC_MANA).
static func fight_start_mana() -> float:
	return clampf(
		(ENCOUNTER_RESPAWN_S - BalanceCombat.OOC_DELAY_S) * BalanceCombat.OOC_MANA_PCT_PER_S,
		0.0,
		1.0
	)


## Fight time without the approach: max(0, (Σ PV_effectifs − burst) / DPS).
static func fight_time(ehp: float, burst_damage: float, dps: float) -> float:
	if dps <= 0.0:
		return INF
	return maxf(0.0, (ehp - burst_damage) / dps)


## crit_factor = 1 + crit_chance × (crit_damage − 1), crit chance capped.
static func crit_factor(crit_chance: float, crit_damage: float) -> float:
	return 1.0 + clampf(crit_chance, 0.0, BalanceStats.CRIT_CHANCE_CAP) * (crit_damage - 1.0)


## clear_time = max((Σ PV_effectifs − burst) / DPS + ENGAGE_S, CLEAR_TIME_MIN_S)
static func clear_time(ehp: float, burst_damage: float, dps: float) -> float:
	return maxf(fight_time(ehp, burst_damage, dps) + ENGAGE_S, CLEAR_TIME_MIN_S)


## cycle = clear_time + ENCOUNTER_RESPAWN_S
static func cycle(clear_time_s: float) -> float:
	return clear_time_s + ENCOUNTER_RESPAWN_S


## Δ_eff = min(Δ, OFFLINE_CAP_S) (Δ ≥ 0)
static func counted_seconds(elapsed_s: int) -> int:
	return clampi(elapsed_s, 0, OFFLINE_CAP_S)


## N = Δ_eff × (OFFLINE_EFFICIENCY + bonus) / cycle (float)
static func clears(counted_s: int, efficiency: float, cycle_s: float) -> float:
	if cycle_s <= 0.0 or is_inf(cycle_s):
		return 0.0
	return float(counted_s) * efficiency / cycle_s


static func efficiency(bonus: float) -> float:
	return OFFLINE_EFFICIENCY + maxf(bonus, 0.0)


## survit = réserve / subi ≥ OFFLINE_SAFETY_FACTOR × clear_time
static func survives(reserve: float, incoming_dps: float, clear_time_s: float) -> bool:
	if incoming_dps <= 0.0:
		return true
	return reserve / incoming_dps >= OFFLINE_SAFETY_FACTOR * clear_time_s
