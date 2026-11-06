class_name BalanceProgression
extends RefCounted
## Progression constants (docs/GAME_BALANCE.md §12). Values are hypotheses
## [H] until the balance bench runs (§22).

const LEVEL_CAP := 20
const XP_CURVE_BASE := 40.0
const XP_CURVE_EXPONENT := 2.6


## XP needed to go from `level` to `level + 1`.
static func xp_to_next(level: int) -> int:
	if level >= LEVEL_CAP:
		return 0
	return roundi(XP_CURVE_BASE * pow(level, XP_CURVE_EXPONENT))
