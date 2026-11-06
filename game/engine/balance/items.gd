class_name BalanceItems
extends RefCounted
## Equipment loot, salvage and enhancement (docs/GAME_BALANCE.md §13-§15).
## Per-entity values (affix ranges, implicit bases) live in game/data.

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]

# --- §14.1 Rarity by source (weights out of 100) -------------------------------
const RARITY_WEIGHTS := {
	"normal": {"common": 68.0, "uncommon": 25.0, "rare": 6.0, "epic": 0.9, "legendary": 0.1},
	"elite": {"common": 0.0, "uncommon": 40.0, "rare": 42.0, "epic": 15.0, "legendary": 3.0},
	"boss": {"common": 0.0, "uncommon": 0.0, "rare": 50.0, "epic": 40.0, "legendary": 10.0},
	"boss_first_kill":
	{"common": 0.0, "uncommon": 0.0, "rare": 0.0, "epic": 80.0, "legendary": 20.0},
	"chest": {"common": 0.0, "uncommon": 30.0, "rare": 50.0, "epic": 17.0, "legendary": 3.0},
}
## GDD §11: the first kill of a boss guarantees epic or better.
const FIRST_KILL_PROFILE := {"boss": "boss_first_kill"}

# --- §14.2 Item level and implicit --------------------------------------------
const ILVL_ELITE_BONUS := 1
const ILVL_BOSS_BONUS := 2
const ILVL_GROWTH := 0.15
const RARITY_IMPLICIT_MULT := {
	"common": 1.0, "uncommon": 1.1, "rare": 1.2, "epic": 1.35, "legendary": 1.5
}
const AFFIX_COUNT := {"common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 4}
## Reference implicit per slot at ilvl 1 (item bases in equipment.json carry
## these values; a content test keeps them equal).
const SLOT_IMPLICIT := {
	"weapon": {"power": 6.0},
	"head": {"max_hp": 25.0, "defense": 2.0},
	"chest": {"max_hp": 40.0, "defense": 4.0},
	"hands": {"power": 2.0, "defense": 1.0},
	"feet": {"max_hp": 20.0, "defense": 2.0},
	"amulet": {"crit_chance": 0.02},
}
## Implicit stats that follow the affix tier (pct scale) instead of ilvl_mult.
const IMPLICIT_TIER_STATS := ["crit_chance"]

# --- §14.3 Affixes ---------------------------------------------------------------
const AFFIX_TIER_MAX := 4
const AFFIX_TIER_STEP_ILVL := 5
const AFFIX_PCT_SCALE_PER_TIER := 0.25
## Legendaries roll u in [LEGENDARY_ROLL_MIN, 1] (upper half of the range).
const LEGENDARY_ROLL_MIN := 0.5

# --- §13 Salvage and inventory (GDD §10.6) ----------------------------------------
const SALVAGE_DUST := {
	"common": 2.0, "uncommon": 5.0, "rare": 12.0, "epic": 30.0, "legendary": 80.0
}
const SALVAGE_ILVL_STEP := 0.1
const INVENTORY_SLOTS := 60
const DUST_ID := "material.mana_dust"

# --- §15 Enhancement ----------------------------------------------------------------
const ENH_MAX_BY_RARITY := {"common": 4, "uncommon": 6, "rare": 8, "epic": 10, "legendary": 10}
const ENH_STAT_PER_LEVEL := 0.06
const ENH_GOLD_BASE := 60.0
const ENH_GOLD_GROWTH := 1.35
const ENH_DUST_BASE := 4
## Chance of reaching +1 ... +10 (index 0 is +1).
const ENH_SUCCESS := [1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
const ENH_PITY_PER_FAIL := 0.10
const ENH_FAIL_GOLD_REFUND := 0.5


## ilvl = Le_source + (elite ? 1 : 0) + (boss ? 2 : 0)
static func item_level(source_level: int, kind: String) -> int:
	var bonus := 0
	if kind == "elite":
		bonus = ILVL_ELITE_BONUS
	elif kind == "boss":
		bonus = ILVL_BOSS_BONUS
	return maxi(1, source_level + bonus)


## ilvl_mult = 1 + ILVL_GROWTH × (ilvl − 1)
static func ilvl_mult(ilvl: int) -> float:
	return 1.0 + ILVL_GROWTH * float(ilvl - 1)


## palier = min(4, 1 + floor((ilvl − 1) / 5))
static func affix_tier(ilvl: int) -> int:
	return mini(AFFIX_TIER_MAX, 1 + floori(float(ilvl - 1) / AFFIX_TIER_STEP_ILVL))


## échelle_pct = 1 + 0.25 × (palier − 1)
static func pct_scale(ilvl: int) -> float:
	return 1.0 + AFFIX_PCT_SCALE_PER_TIER * float(affix_tier(ilvl) - 1)


## Scale of an affix value: ilvl_mult for "flat", tier scale for "pct".
static func affix_scale(scaling: String, ilvl: int) -> float:
	return ilvl_mult(ilvl) if scaling == "flat" else pct_scale(ilvl)


## (1 + ENH_STAT_PER_LEVEL × enhance): implicit and flat affixes only.
static func enhance_mult(enhance: int) -> float:
	return 1.0 + ENH_STAT_PER_LEVEL * float(enhance)


## implicit = base × scale × RARITY_IMPLICIT_MULT × enhance_mult
static func implicit_value(
	stat: String, base: float, ilvl: int, rarity: String, enhance: int
) -> float:
	var scale := pct_scale(ilvl) if IMPLICIT_TIER_STATS.has(stat) else ilvl_mult(ilvl)
	return base * scale * float(RARITY_IMPLICIT_MULT[rarity]) * enhance_mult(enhance)


## Mana dust from salvaging an item: SALVAGE_DUST × (1 + 0.1 × (ilvl − 1)), floored.
static func salvage_dust(rarity: String, ilvl: int) -> int:
	return floori(float(SALVAGE_DUST[rarity]) * (1.0 + SALVAGE_ILVL_STEP * float(ilvl - 1)))


static func enhance_max(rarity: String) -> int:
	return int(ENH_MAX_BY_RARITY[rarity])


## Gold for n → n+1: roundi(ENH_GOLD_BASE × ilvl_mult × ENH_GOLD_GROWTH ^ n)
static func enhance_gold(ilvl: int, n: int) -> int:
	return roundi(ENH_GOLD_BASE * ilvl_mult(ilvl) * pow(ENH_GOLD_GROWTH, n))


## Dust for n → n+1: ENH_DUST_BASE × (n + 1)
static func enhance_dust(n: int) -> int:
	return ENH_DUST_BASE * (n + 1)


## chance(n+1) = min(1, ENH_SUCCESS[n+1] + pity), pity = fails × ENH_PITY_PER_FAIL
static func enhance_chance(n: int, fails: int) -> float:
	var idx := clampi(n, 0, ENH_SUCCESS.size() - 1)
	return minf(1.0, float(ENH_SUCCESS[idx]) + ENH_PITY_PER_FAIL * float(fails))


## Gold given back on a failed attempt (floored).
static func enhance_refund(gold: int) -> int:
	return floori(float(gold) * ENH_FAIL_GOLD_REFUND)
