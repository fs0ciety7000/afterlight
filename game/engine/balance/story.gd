class_name BalanceStory
extends RefCounted
## Quests, discoveries, chests, contracts and bestiary (docs/GAME_BALANCE.md
## §12, §13, §23; docs/content/contracts.md §4). Values are hypotheses [H].

## Quest XP = factor × xp_to_next(quest level) (§12). QUEST_XP_MAIN raised from
## 0.6 after the milestone 6 bench so quests give ~30 % of the XP to level 12
## (§21.2, provisional).
const QUEST_XP_MAIN := 1.1
const QUEST_XP_SIDE := 0.3
## Discovery XP = DISCOVERY_XP × xp_to_next(discovery level).
const DISCOVERY_XP := 0.1
## Chest gold = CHEST_GOLD_MULT × enemy gold at the chest level.
const CHEST_GOLD_MULT := 5.0

## Daily contracts.
const CONTRACTS_PER_DAY := 3
const CONTRACT_MAX_LONG := 1
const CONTRACT_GOLD_BASE := 100.0
const CONTRACT_TIER_MULT := {"S": 0.75, "M": 1.0, "L": 1.5}
const CONTRACT_DUST := {"S": 4, "M": 6, "L": 10}
const CONTRACT_SHARDS := {"S": 1, "M": 2, "L": 3}
const SECONDS_PER_DAY := 86400

## Bestiary tiers when an enemy has no bestiary_thresholds (GDD §13).
const BESTIARY_THRESHOLDS := [1, 5, 25]


## XP of a quest of `kind` ("main" or "side") at `level`; `factor` overrides
## the kind's factor when >= 0.
static func quest_xp(kind: String, level: int, factor: float = -1.0) -> int:
	var f := factor
	if f < 0.0:
		f = QUEST_XP_MAIN if kind == "main" else (QUEST_XP_SIDE if kind == "side" else 0.0)
	return roundi(f * float(BalanceProgression.xp_to_next(level)))


static func discovery_xp(level: int) -> int:
	return roundi(DISCOVERY_XP * float(BalanceProgression.xp_to_next(level)))


## {gold, dust, shards} of a contract of `tier`, rolled with Fern at `level`.
static func contract_reward(tier: String, level: int) -> Dictionary:
	var gold := (
		CONTRACT_GOLD_BASE
		* (1.0 + BalanceEnemies.GOLD_GROWTH * float(level - 1))
		* float(CONTRACT_TIER_MULT.get(tier, 1.0))
	)
	return {
		"gold": roundi(gold),
		"dust": int(CONTRACT_DUST.get(tier, 0)),
		"shards": int(CONTRACT_SHARDS.get(tier, 0)),
	}


## Local day number: midnight in the player's time zone starts a new day.
static func day_index(now_unix: int, tz_offset_s: int) -> int:
	return floori(float(now_unix + tz_offset_s) / float(SECONDS_PER_DAY))


## Unlocked bestiary tier (0-3) for `victories` against an enemy.
static func bestiary_tier(victories: int, thresholds: Array) -> int:
	var tier := 0
	for t in thresholds:
		if victories >= int(t):
			tier += 1
	return tier
