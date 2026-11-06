class_name BalanceStats
extends RefCounted
## Stat caps and derivation (docs/GAME_BALANCE.md §2). Base values and growth
## of each character live in game/data (characters.json, base_stats/growth).

const BASE_CRIT_CHANCE := 0.05
const BASE_CRIT_DAMAGE := 1.5
const CRIT_CHANCE_CAP := 0.60
const CRIT_DAMAGE_CAP := 3.0
const HASTE_CAP := 0.50
const RESIST_CAP := 0.50
const GOLD_FIND_CAP := 1.0

## Stats every combatant carries, with their default when absent.
const DEFAULTS := {
	"max_hp": 1.0,
	"max_mana": 0.0,
	"mana_regen": 0.0,
	"power": 0.0,
	"defense": 0.0,
	"crit_chance": BASE_CRIT_CHANCE,
	"crit_damage": BASE_CRIT_DAMAGE,
	"haste": 0.0,
	"damage_bonus": 0.0,
	"element_bonus_arcane": 0.0,
	"element_bonus_fire": 0.0,
	"element_bonus_frost": 0.0,
	"element_bonus_lightning": 0.0,
	"resist_all": 0.0,
	"shield_bonus": 0.0,
	"gold_find": 0.0,
	"move_speed": 5.0,
}

const CAPS := {
	"crit_chance": CRIT_CHANCE_CAP,
	"crit_damage": CRIT_DAMAGE_CAP,
	"haste": HASTE_CAP,
	"resist_all": RESIST_CAP,
	"gold_find": GOLD_FIND_CAP,
}


## stat_base(L) = BASE + PER_LEVEL × (L − 1)
static func stat_base(base: float, per_level: float, level: int) -> float:
	return base + per_level * float(level - 1)


## final = clamp((stat_base(L) + Σ flat) × (1 + Σ percent), 0, CAP), for every
## stat of DEFAULTS. `flat` and `percent` map stat ids to summed modifiers.
static func derive(
	base_stats: Dictionary,
	growth: Dictionary,
	level: int,
	flat: Dictionary = {},
	percent: Dictionary = {}
) -> Dictionary:
	var out := {}
	for stat in DEFAULTS:
		var base := stat_base(
			float(base_stats.get(stat, DEFAULTS[stat])), float(growth.get(stat, 0.0)), level
		)
		var value := (base + float(flat.get(stat, 0.0))) * (1.0 + float(percent.get(stat, 0.0)))
		out[stat] = clampf(value, 0.0, float(CAPS.get(stat, INF)))
	return out
