class_name Equipment
extends RefCounted
## Worn equipment, stat aggregation and comparison (GDD §10.2,
## GAME_BALANCE §2.2). Modifiers are tagged by source ("item:<uid>",
## "artifact:<id>"): equipping adds a source's modifiers, unequipping removes
## exactly the same ones. Derived stats are recomputed, never saved.

const BETTER := "better"
const WORSE := "worse"
const EQUAL := "equal"
const EPSILON := 0.000001


static func slot_of(item: Dictionary, content: Dictionary) -> String:
	return str(content.get(item.get("item_id", ""), {}).get("slot", ""))


## Wears a bag item in its slot; the item already there goes back to the bag.
## Result extra: {slot, replaced (uid or "")}.
static func equip(
	state: Dictionary, character: String, uid: String, content: Dictionary
) -> Dictionary:
	var item := Inventory.find(state, uid)
	var slot := slot_of(item, content)
	if item.is_empty() or slot == "" or not state["characters"].has(character):
		return ActionResult.refuse("error.item_not_found", {"uid": uid})
	var next := state.duplicate(true)
	var wearer: String = Inventory.worn(next).get(uid, "")
	if wearer != "":
		next["characters"][wearer]["equipment"][slot] = ""
	var equipment: Dictionary = next["characters"][character]["equipment"]
	var replaced: String = equipment[slot]
	equipment[slot] = uid
	return ActionResult.success(next, {"slot": slot, "replaced": replaced})


## Takes off the item of `slot` (the bag must have room).
static func unequip(state: Dictionary, character: String, slot: String) -> Dictionary:
	if not state["characters"].has(character):
		return ActionResult.refuse("error.slot_empty", {"slot": slot})
	var uid: String = state["characters"][character]["equipment"].get(slot, "")
	if uid == "":
		return ActionResult.refuse("error.slot_empty", {"slot": slot})
	if Inventory.is_full(state):
		return ActionResult.refuse("error.inventory_full", {"max": BalanceItems.INVENTORY_SLOTS})
	var next := state.duplicate(true)
	next["characters"][character]["equipment"][slot] = ""
	return ActionResult.success(next, {"slot": slot, "uid": uid})


## Every stat modifier of a character: [{source, stat, layer, value, from}].
static func modifiers(state: Dictionary, character: String, content: Dictionary) -> Array:
	var out := []
	var hero: Dictionary = state["characters"].get(character, {})
	if hero.is_empty():
		return out
	for slot in StateSchema.EQUIPMENT_SLOTS:
		var uid: String = hero["equipment"].get(slot, "")
		var item := Inventory.find(state, uid) if uid != "" else {}
		if item.is_empty():
			continue
		for m in ItemFactory.modifiers(item, content):
			m["source"] = "item:" + uid
			out.append(m)
	return out


## {flat: {stat: sum}, percent: {stat: sum}} of a character's modifiers.
static func bonuses(state: Dictionary, character: String, content: Dictionary) -> Dictionary:
	return ItemFactory.sum_modifiers(modifiers(state, character, content))


## Final stats of a character (BalanceStats.derive with its modifiers).
static func stats(state: Dictionary, character: String, content: Dictionary) -> Dictionary:
	var def: Dictionary = content.get(character, {})
	var hero: Dictionary = state["characters"].get(character, {})
	if def.is_empty() or hero.is_empty():
		return {}
	var b := bonuses(state, character, content)
	return BalanceStats.derive(
		def.get("base_stats", {}),
		def.get("growth", {}),
		int(hero["level"]),
		b["flat"],
		b["percent"]
	)


## Per-stat delta between a candidate item and the item it would replace
## (`current` may be {}). Every stat is "higher is better". Returns
## [{stat, layer, candidate, current, delta, sign}] sorted by stat then layer.
static func compare(candidate: Dictionary, current: Dictionary, content: Dictionary) -> Array:
	var a := _by_key(ItemFactory.modifiers(candidate, content) if not candidate.is_empty() else [])
	var b := _by_key(ItemFactory.modifiers(current, content) if not current.is_empty() else [])
	var keys := a.keys()
	for k in b:
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	var out := []
	for k in keys:
		var va := float(a.get(k, 0.0))
		var vb := float(b.get(k, 0.0))
		var delta := va - vb
		var sign := EQUAL
		if delta > EPSILON:
			sign = BETTER
		elif delta < -EPSILON:
			sign = WORSE
		var parts: PackedStringArray = k.split("|")
		out.append(
			{
				"stat": parts[0],
				"layer": parts[1],
				"candidate": va,
				"current": vb,
				"delta": delta,
				"sign": sign
			}
		)
	return out


## Compares a bag item with what `character` wears in the same slot.
static func compare_with_worn(
	state: Dictionary, character: String, uid: String, content: Dictionary
) -> Array:
	var item := Inventory.find(state, uid)
	if item.is_empty():
		return []
	var worn_uid: String = state["characters"][character]["equipment"].get(
		slot_of(item, content), ""
	)
	var current := Inventory.find(state, worn_uid) if worn_uid != "" else {}
	return compare(item, current, content)


static func _by_key(mods: Array) -> Dictionary:
	var out := {}
	for m in mods:
		var k: String = "%s|%s" % [m["stat"], m["layer"]]
		out[k] = float(out.get(k, 0.0)) + float(m["value"])
	return out
