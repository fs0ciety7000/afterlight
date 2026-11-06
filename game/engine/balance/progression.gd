class_name BalanceProgression
extends RefCounted
## Progression constants (docs/GAME_BALANCE.md §12). Values are hypotheses
## [H] until playtests confirm them.

const LEVEL_CAP := 20
const XP_TO_NEXT_BASE := 40.0
const XP_EXPONENT := 2.6

## §12 table of xp_to_next for L1-L19. It is authoritative (criterion 4.1):
## the formula below drifts by 10-20 XP at L8, L9, L18 and L19.
const XP_TO_NEXT_TABLE := [
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


## XP needed to go from `level` to `level + 1` (§12 table; past it, the
## formula rounded to the nearest ten).
static func xp_to_next(level: int) -> int:
	if level >= LEVEL_CAP:
		return 0
	if level >= 1 and level <= XP_TO_NEXT_TABLE.size():
		return int(XP_TO_NEXT_TABLE[level - 1])
	return xp_formula(level)


## round_to_10(XP_TO_NEXT_BASE × L ^ XP_EXPONENT)
static func xp_formula(level: int) -> int:
	return roundi(XP_TO_NEXT_BASE * pow(level, XP_EXPONENT) / 10.0) * 10


## Adds `gained` XP to a character at (`level`, `xp`). Returns
## {level, xp, levels_gained, wasted}: several levels can be gained at once;
## at the cap the surplus is wasted (and reported).
static func grant_xp(level: int, xp: int, gained: int) -> Dictionary:
	var lvl := level
	var pool := xp + maxi(gained, 0)
	var start := level
	while lvl < LEVEL_CAP and pool >= xp_to_next(lvl):
		pool -= xp_to_next(lvl)
		lvl += 1
	var wasted := 0
	if lvl >= LEVEL_CAP:
		wasted = pool
		pool = 0
	return {"level": lvl, "xp": pool, "levels_gained": lvl - start, "wasted": wasted}
