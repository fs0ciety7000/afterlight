class_name BalanceStatuses
extends RefCounted
## Status constants (docs/GAME_BALANCE.md §9, GDD §8). Durations, stacks and
## modifiers of each status live in game/data/original/statuses.json; the ids
## below are the mechanic contract the engine relies on (reactions, crowd
## control, shields).

const BURN_COEFF := 0.15
const FREEZE_IMMUNITY_S := 4.0
const BOSS_CC_DURATION_MULT := 0.5
## Bosses take at most this many Chill stacks and are never frozen.
const BOSS_CHILL_MAX_STACKS := 2

const BURN := "status.burn"
const CHILL := "status.chill"
const FROZEN := "status.frozen"
const SHOCK := "status.shock"
const WEAKEN := "status.weaken"
const STUN := "status.stun"
const HASTE_BUFF := "status.haste_buff"
const SHIELD := "status.shield"

## Status applied by each element (GDD §8, rune conversions).
const ELEMENT_STATUS := {"fire": BURN, "frost": CHILL, "lightning": SHOCK}


## Burn damage of one tick before mitigation:
## BURN_COEFF × power_source × stacks × tick_s.
static func burn_tick_raw(source_power: float, stacks: int, tick_s: float) -> float:
	return BURN_COEFF * source_power * float(stacks) * tick_s
