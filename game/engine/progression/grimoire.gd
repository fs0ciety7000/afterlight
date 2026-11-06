class_name Grimoire
extends RefCounted
## Spell ranks and rune slots (GDD §10.3-§10.4, GAME_BALANCE §16-§17).
## Ranks 1-5 for the active spells and the ultimate (gold + grimoire pages,
## level gate); runes are socketed in spell slots (1 / 2 / 3 at ranks 1 / 3 /
## 5) and removed for free; one conversion rune per spell, never the same rune
## twice on a spell, never on the auto attack.


## Spells of a character that take ranks and runes (actives + ultimate).
static func ranked_spells(character: String, content: Dictionary) -> Array:
	var def: Dictionary = content.get(character, {})
	var out: Array = def.get("spells", []).duplicate()
	if str(def.get("ultimate", "")) != "":
		out.append(def["ultimate"])
	return out


## Level at which `spell` is learned (character unlocks; 1 if not gated).
static func unlock_level(character: String, spell: String, content: Dictionary) -> int:
	for u in content.get(character, {}).get("unlocks", []):
		if u["ref"] == spell:
			return int(u["level"])
	return 1


static func rank_of(state: Dictionary, character: String, spell: String) -> int:
	return maxi(1, int(state["characters"][character]["spells"].get(spell, 1)))


static func socketed(state: Dictionary, character: String, spell: String) -> Array:
	return state["characters"][character]["runes"].get(spell, [])


## Refusal if `spell` is not a learned ranked spell of `character`, else {}.
static func _check_spell(
	state: Dictionary, character: String, spell: String, content: Dictionary
) -> Dictionary:
	if not state["characters"].has(character) or not ranked_spells(character, content).has(spell):
		return ActionResult.refuse("error.spell_unknown", {"spell": spell + ".name"})
	var need := unlock_level(character, spell, content)
	if int(state["characters"][character]["level"]) < need:
		return ActionResult.refuse("error.spell_locked", {"level": need})
	return {}


## Next rank: cost, level gate, slots after. Result extra: {spell, from, to,
## gold, pages, level_required, slots}.
static func rank_quote(
	state: Dictionary, character: String, spell: String, content: Dictionary
) -> Dictionary:
	var bad := _check_spell(state, character, spell, content)
	if not bad.is_empty():
		return bad
	var r := rank_of(state, character, spell)
	if r >= BalanceGrimoire.SPELL_RANK_MAX:
		return ActionResult.refuse("error.rank_max", {"max": BalanceGrimoire.SPELL_RANK_MAX})
	var info := {
		"spell": spell,
		"from": r,
		"to": r + 1,
		"gold": BalanceGrimoire.rank_gold(r),
		"pages": BalanceGrimoire.rank_pages(r),
		"level_required": BalanceGrimoire.rank_level(r),
		"slots": BalanceGrimoire.rune_slots(r + 1),
	}
	if int(state["characters"][character]["level"]) < int(info["level_required"]):
		var refused := ActionResult.refuse(
			"error.level_required", {"level": info["level_required"]}
		)
		refused.merge(info)
		return refused
	var lack := ActionResult.check_cost(state["wallet"], _rank_cost(info))
	if not lack.is_empty():
		lack.merge(info)
		return lack
	return ActionResult.success(state, info)


static func rank_up(
	state: Dictionary, character: String, spell: String, content: Dictionary
) -> Dictionary:
	var q := rank_quote(state, character, spell, content)
	if not q["ok"]:
		return q
	var next := state.duplicate(true)
	ActionResult.pay(next["wallet"], _rank_cost(q))
	next["characters"][character]["spells"][spell] = int(q["to"])
	var extra: Dictionary = q.duplicate()
	extra.erase("state")
	return ActionResult.success(next, extra)


static func _rank_cost(info: Dictionary) -> Dictionary:
	return {"gold": info["gold"], "materials": {BalanceGrimoire.PAGE_ID: info["pages"]}}


## Sockets a rune from the stock into `spell`. Result extra: {spell, slots}.
static func socket(
	state: Dictionary,
	character: String,
	spell: String,
	rune: String,
	tier: int,
	content: Dictionary
) -> Dictionary:
	var bad := _check_spell(state, character, spell, content)
	if not bad.is_empty():
		return bad
	var def: Dictionary = content.get(rune, {})
	if def.get("_type", "") != "rune" or Inventory.rune_count(state, rune, tier) < 1:
		return ActionResult.refuse("error.rune_not_owned", {"rune": rune + ".name", "tier": tier})
	var current := socketed(state, character, spell)
	for s in current:
		if s["id"] == rune:
			return ActionResult.refuse("error.rune_duplicate", {"rune": rune + ".name"})
		if def["group"] == "conversion" and content[s["id"]]["group"] == "conversion":
			return ActionResult.refuse("error.rune_conversion_taken", {"rune": s["id"] + ".name"})
	var slots := BalanceGrimoire.rune_slots(rank_of(state, character, spell))
	if current.size() >= slots:
		return ActionResult.refuse("error.rune_slots_full", {"slots": slots})
	var next := state.duplicate(true)
	next["runes"][rune][tier - 1] = int(next["runes"][rune][tier - 1]) - 1
	var runes: Dictionary = next["characters"][character]["runes"]
	if not runes.has(spell):
		runes[spell] = []
	runes[spell].append({"id": rune, "tier": tier})
	return ActionResult.success(next, {"spell": spell, "slots": slots})


## Removes the rune at `index` of `spell` (free) and puts it back in stock.
static func unsocket(state: Dictionary, character: String, spell: String, index: int) -> Dictionary:
	if not state["characters"].has(character):
		return ActionResult.refuse("error.rune_slot_empty")
	var current := socketed(state, character, spell)
	if index < 0 or index >= current.size():
		return ActionResult.refuse("error.rune_slot_empty")
	var next := state.duplicate(true)
	var runes: Dictionary = next["characters"][character]["runes"]
	var removed: Dictionary = runes[spell][index]
	runes[spell].remove_at(index)
	if runes[spell].is_empty():
		runes.erase(spell)
	Inventory.add_rune(next, removed["id"], int(removed["tier"]))
	return ActionResult.success(next, {"spell": spell, "rune": removed.duplicate()})


## Combat modifiers of each spell from its runes (CombatSim spell_mods):
## {spell: {element, status_chance, crit_bonus, cost_reduction,
## cooldown_reduction, echo_chance, damage_bonus}} (only the keys set).
static func spell_mods(state: Dictionary, character: String, content: Dictionary) -> Dictionary:
	var out := {}
	var runes: Dictionary = state["characters"][character].get("runes", {})
	for spell in runes:
		var mods := {}
		for s in runes[spell]:
			var def: Dictionary = content.get(s["id"], {})
			if def.is_empty():
				continue
			var value := float(def["values_by_tier"][int(s["tier"]) - 1])
			if def["group"] == "conversion":
				mods["element"] = def["element"]
				mods[BalanceGrimoire.CONVERSION_CHANCE_KEY] = value
			else:
				mods[def["stat"]] = float(mods.get(def["stat"], 0.0)) + value
		if not mods.is_empty():
			out[spell] = mods
	return out
