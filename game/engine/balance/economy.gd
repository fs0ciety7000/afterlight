class_name BalanceEconomy
extends RefCounted
## Artifacts and prices (docs/GAME_BALANCE.md §18-§19). Artifact values per
## level live in artifacts.json, consumable base prices in consumables.json.

const ARTIFACT_MAX_LEVEL := 5
## Essences to go from level n to n+1 (index 0 is 1 → 2).
const ARTIFACT_ESSENCE_COST := [1, 2, 3, 5]
const ARTIFACT_GOLD_BASE := 500
## Character level that opens each artifact slot. Slot 1 opens when the
## clockmaker's quest (available at level 6) is handed in: its reward unlocks
## the ARTIFACT_SLOT_1_TOKEN (GDD decision 14, jalon 6).
const ARTIFACT_SLOT_1_LEVEL := 6
const ARTIFACT_SLOT_1_TOKEN := "artifact_slot_1"
const ARTIFACT_SLOT_1_QUEST := "quest.side_clockmaker"
const ARTIFACT_SLOT_2_LEVEL := 15
const ARTIFACT_SLOT_LEVELS := [ARTIFACT_SLOT_1_LEVEL, ARTIFACT_SLOT_2_LEVEL]
const ESSENCE_ID := "material.ashen_essence"

## Price = roundi(price_base × (1 + PRICE_LEVEL_GROWTH × (L − 1))).
## price_base: PRICE_HEALING_DRAUGHT_BASE = 30, PRICE_MANA_ELIXIR_BASE = 25
## (consumables.json).
const PRICE_LEVEL_GROWTH := 0.1


## Gold to go from level n to n+1: 500 × n²
static func artifact_gold(level: int) -> int:
	return ARTIFACT_GOLD_BASE * level * level


static func artifact_essence(level: int) -> int:
	return int(ARTIFACT_ESSENCE_COST[clampi(level, 1, ARTIFACT_MAX_LEVEL - 1) - 1])


static func price(price_base: int, level: int) -> int:
	return roundi(float(price_base) * (1.0 + PRICE_LEVEL_GROWTH * float(level - 1)))
