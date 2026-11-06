class_name CombatTactics
extends RefCounted
## Combat priorities (GDD §7.4). Tactics are a plain dictionary:
##   targeting       "nearest" | "lowest_hp" | "elites_first" | "casters_first"
##   mana_reserve    0-0.5: automatic casts never take mana below this share
##   barrier_hp_pct  0.3-0.7: threshold of "auto_hp_below" and of the fallback
##                   of "auto_telegraph_or_hp"
##   min_enemies     enemy count of "auto_min_enemies"
##   spells          {spell_id: mode}
##   consumables     {consumable_id: mode}: "manual", "auto_low_hp" (healing,
##                   under TACTIC_HEAL_HP_PCT; the healing default, owner
##                   decision of 2026-11-06) or "auto_low_mana" (mana, under
##                   TACTIC_ELIXIR_MANA_PCT); owner answer 2 to GDD decisions 22-31
## Modes: "manual", "auto", "auto_elite_boss", "auto_interrupt",
## "auto_min_enemies", "auto_hp_below", "auto_before_telegraph",
## "auto_telegraph_or_hp", "auto_full".
## Defaults follow each spell's role, read from its data (no id in code):
## damage (Zoltraak included) -> auto, distributed damage -> auto_min_enemies,
## shield -> auto_telegraph_or_hp (GDD decision 22), ultimate -> manual,
## healing consumable -> auto_low_hp (GDD decision 32), other consumables ->
## manual. An interrupting spell on
## "auto" still turns to an enemy casting something interruptible first.
## Deviation from GDD §7.4 (Zoltraak "Auto pour interrompre" by default): with
## it, an idle player loses low-level normal fights (bench, GAME_BALANCE §22).

const TARGETING := ["nearest", "lowest_hp", "elites_first", "casters_first"]
const MODES := [
	"manual",
	"auto",
	"auto_elite_boss",
	"auto_interrupt",
	"auto_min_enemies",
	"auto_hp_below",
	"auto_before_telegraph",
	"auto_telegraph_or_hp",
	"auto_full",
	"auto_low_hp",
	"auto_low_mana",
]


## Role of a spell, or of a consumable ("heal", "mana", "consumable").
static func role_of(spell: Dictionary) -> String:
	if spell.get("_type", "") == "consumable":
		match str(spell.get("effect", {}).get("type", "")):
			"heal":
				return "heal"
			"restore_mana":
				return "mana"
		return "consumable"
	if spell.get("kind", "") == "ultimate":
		return "ultimate"
	for effect in spell.get("effects", []):
		if effect.get("type", "") == "shield":
			return "shield"
	if spell.get("interrupts", false):
		return "interrupt"
	if spell.get("targeting", "") == "distributed":
		return "area"
	return "damage"


## Modes a spell may use (GDD §7.4 table, by role).
static func modes_for(spell: Dictionary) -> Array:
	match role_of(spell):
		"heal":
			return ["manual", "auto_low_hp"]
		"mana":
			return ["manual", "auto_low_mana"]
		"consumable":
			return ["manual"]
		"ultimate":
			return ["manual", "auto_full"]
		"shield":
			return ["manual", "auto_hp_below", "auto_before_telegraph", "auto_telegraph_or_hp"]
		"interrupt":
			return ["manual", "auto", "auto_elite_boss", "auto_interrupt"]
		"area":
			return ["manual", "auto", "auto_min_enemies"]
	return ["manual", "auto", "auto_elite_boss"]


static func default_mode(spell: Dictionary) -> String:
	match role_of(spell):
		"ultimate", "mana", "consumable":
			return "manual"
		"heal":
			return "auto_low_hp"
		"shield":
			return "auto_telegraph_or_hp"
		"area":
			return "auto_min_enemies"
	return "auto"


static func is_consumable(spell: Dictionary) -> bool:
	return spell.get("_type", "") == "consumable"


## Full tactics for the given spells and consumables (`spell_defs`, by id),
## `overrides` applied on top (invalid override values are ignored).
static func build(spell_defs: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var t := {
		"targeting": "nearest",
		"mana_reserve": BalanceCombat.TACTIC_MANA_RESERVE_DEFAULT,
		"barrier_hp_pct": BalanceCombat.TACTIC_BARRIER_HP_DEFAULT,
		"min_enemies": BalanceCombat.TACTIC_MIN_ENEMIES_DEFAULT,
		"spells": {},
		"consumables": {},
	}
	for id in spell_defs:
		var group := "consumables" if is_consumable(spell_defs[id]) else "spells"
		t[group][id] = default_mode(spell_defs[id])
	for key in overrides:
		if key in ["spells", "consumables"]:
			if typeof(overrides[key]) != TYPE_DICTIONARY:
				continue
			for id in overrides[key]:
				set_value(t, spell_defs, str(id), overrides[key][id])
		else:
			set_value(t, spell_defs, key, overrides[key])
	return t


## Sets one tactic. `key` is a setting name, a spell id or a consumable id. Returns "" or the
## reason of a refusal ("unknown_key", "invalid_value").
static func set_value(t: Dictionary, spell_defs: Dictionary, key: String, value: Variant) -> String:
	var reason := ""
	match key:
		"targeting":
			reason = "" if TARGETING.has(value) else "invalid_value"
		"mana_reserve":
			reason = _check_range(value, 0.0, BalanceCombat.TACTIC_MANA_RESERVE_MAX)
		"barrier_hp_pct":
			reason = _check_range(
				value, BalanceCombat.TACTIC_BARRIER_HP_MIN, BalanceCombat.TACTIC_BARRIER_HP_MAX
			)
		"min_enemies":
			reason = _check_range(value, 1.0, 5.0)
		_:
			if not spell_defs.has(key):
				reason = "unknown_key"
			elif not modes_for(spell_defs[key]).has(value):
				reason = "invalid_value"
			else:
				t["consumables" if is_consumable(spell_defs[key]) else "spells"][key] = value
				return ""
	if reason == "":
		t[key] = int(value) if key == "min_enemies" else value
	return reason


static func _check_range(value: Variant, low: float, high: float) -> String:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return "invalid_value"
	if float(value) < low - 0.000001 or float(value) > high + 0.000001:
		return "invalid_value"
	return ""
