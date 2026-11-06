class_name BalanceGrimoire
extends RefCounted
## Spell ranks, rune slots, runes and fusion (docs/GAME_BALANCE.md §16-§17).
## SPELL_RANK_STEP (damage per rank) lives in BalanceCombat. Rune values per
## tier live in runes.json.

const SPELL_RANK_MAX := 5
const RANK_GOLD_BASE := 250
const RANK_PAGES_PER_RANK := 2
const RANK_LEVEL_PER_RANK := 3
const PAGE_ID := "material.grimoire_page"
## Rune slots at rank 1 ... 5.
const RUNE_SLOTS_BY_RANK := [1, 1, 2, 2, 3]

const RUNE_TIER_MAX := 5
const FUSION_INPUT := 3
const FUSION_GOLD_BASE := 150
const FUSION_SHARD_BASE := 5
const RUNE_SALVAGE_SHARD_BASE := 2
const SHARD_ID := "material.rune_shard"
## Tier of a dropped rune, by loot profile (P1 / P2 / P3).
const RUNE_TIER_WEIGHTS := {
	"normal": {1: 90.0, 2: 10.0, 3: 0.0},
	"elite": {1: 60.0, 2: 35.0, 3: 5.0},
	"boss": {1: 0.0, 2: 70.0, 3: 30.0},
	"boss_first_kill": {1: 0.0, 2: 70.0, 3: 30.0},
	"chest": {1: 60.0, 2: 35.0, 3: 5.0},
}
## Spell kinds that take runes and ranks (never the auto attack).
const RANKED_KINDS := ["active", "ultimate"]
## Combat spell_mods key of each rune effect (CombatRules reads these).
const CONVERSION_CHANCE_KEY := "status_chance"


## coût(r → r+1): or = 250 × r²
static func rank_gold(rank: int) -> int:
	return RANK_GOLD_BASE * rank * rank


## coût(r → r+1): pages = 2 × r
static func rank_pages(rank: int) -> int:
	return RANK_PAGES_PER_RANK * rank


## niveau_requis(r+1) = 3 × r
static func rank_level(rank: int) -> int:
	return RANK_LEVEL_PER_RANK * rank


static func rune_slots(rank: int) -> int:
	return int(RUNE_SLOTS_BY_RANK[clampi(rank, 1, SPELL_RANK_MAX) - 1])


## Fusion n → n+1: or = FUSION_GOLD_BASE × 3^(n−1)
static func fusion_gold(tier: int) -> int:
	return FUSION_GOLD_BASE * int(pow(3, tier - 1))


## Fusion n → n+1: éclats = FUSION_SHARD_BASE × n
static func fusion_shards(tier: int) -> int:
	return FUSION_SHARD_BASE * tier


## Salvaging a rune of tier n gives 2 × 3^(n−1) shards.
static func rune_salvage_shards(tier: int) -> int:
	return RUNE_SALVAGE_SHARD_BASE * int(pow(3, tier - 1))
