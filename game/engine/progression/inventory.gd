class_name Inventory
extends RefCounted
## Bag, stocks and salvage (GDD §10.6, GAME_BALANCE §13). Every item instance
## lives in state.inventory; the bag is the part nobody wears and holds
## BalanceItems.INVENTORY_SLOTS items. Materials, runes and consumables are
## stackable stocks outside the bag. Loot that does not fit is salvaged into
## mana dust and reported: nothing is lost silently.


## {uid: character id} of every worn item.
static func worn(state: Dictionary) -> Dictionary:
	var out := {}
	for id in state["characters"]:
		var equipment: Dictionary = state["characters"][id]["equipment"]
		for slot in equipment:
			if str(equipment[slot]) != "":
				out[equipment[slot]] = id
	return out


static func index_of(state: Dictionary, uid: String) -> int:
	var items: Array = state["inventory"]
	for i in items.size():
		if items[i]["uid"] == uid:
			return i
	return -1


static func find(state: Dictionary, uid: String) -> Dictionary:
	var i := index_of(state, uid)
	return state["inventory"][i] if i >= 0 else {}


## Items in the bag (not worn), in inventory order.
static func bag(state: Dictionary) -> Array:
	var on := worn(state)
	var out := []
	for item in state["inventory"]:
		if not on.has(item["uid"]):
			out.append(item)
	return out


static func bag_count(state: Dictionary) -> int:
	return state["inventory"].size() - worn(state).size()


static func is_full(state: Dictionary) -> bool:
	return bag_count(state) >= BalanceItems.INVENTORY_SLOTS


## Next stable item uid ("i1", "i2"...), from the "item" counter of state.rng.
static func next_uid(state: Dictionary) -> String:
	var n := int(state["rng"].get("item", 0)) + 1
	state["rng"]["item"] = n
	return "i%d" % n


static func add_material(state: Dictionary, id: String, qty: int) -> void:
	var materials: Dictionary = state["wallet"]["materials"]
	materials[id] = int(materials.get(id, 0)) + qty


static func rune_count(state: Dictionary, id: String, tier: int) -> int:
	var counts: Array = state["runes"].get(id, [])
	return int(counts[tier - 1]) if counts.size() >= tier else 0


static func add_rune(state: Dictionary, id: String, tier: int, qty: int = 1) -> void:
	if not state["runes"].has(id):
		var empty := []
		for i in StateSchema.RUNE_TIERS:
			empty.append(0)
		state["runes"][id] = empty
	state["runes"][id][tier - 1] = int(state["runes"][id][tier - 1]) + qty


## Adds up to the carry cap; returns how many did not fit.
static func add_consumable(state: Dictionary, id: String, qty: int, content: Dictionary) -> int:
	var cap := carry_max(id, content)
	var have := int(state["consumables"].get(id, 0))
	var taken := clampi(cap - have, 0, qty)
	if taken > 0:
		state["consumables"][id] = have + taken
	return qty - taken


static func carry_max(id: String, content: Dictionary) -> int:
	var def: Dictionary = content.get(id, {})
	return mini(int(def.get("carry_max", 0)), BalanceCombat.CONSUMABLE_CARRY_MAX)


## Puts the loot of a won encounter into `state` (mutated: pass a copy).
## Items get a uid; when the bag is full they are salvaged instead.
## Returns {items: [uid], auto_salvaged: [{item_id, rarity, item_level, dust}],
## salvage_dust, runes: [{id, tier}], artifacts: [id], consumables: {id: n},
## lines: [{key, params}]} (summary lines for the victory screen).
static func receive(state: Dictionary, rewards: Dictionary, content: Dictionary) -> Dictionary:
	var out := {
		"items": [],
		"auto_salvaged": [],
		"salvage_dust": 0,
		"runes": [],
		"artifacts": [],
		"consumables": {},
		"lines": [],
	}
	for drop in rewards.get("items", []):
		var item: Dictionary = drop.duplicate(true)
		if is_full(state):
			var dust := ItemFactory.salvage_value(item)
			out["auto_salvaged"].append(
				{
					"item_id": item["item_id"],
					"rarity": item["rarity"],
					"item_level": item["item_level"],
					"dust": dust
				}
			)
			out["salvage_dust"] += dust
			continue
		item["uid"] = next_uid(state)
		state["inventory"].append(item)
		out["items"].append(item["uid"])
	if out["salvage_dust"] > 0:
		add_material(state, BalanceItems.DUST_ID, out["salvage_dust"])
		var count: int = out["auto_salvaged"].size()
		(
			out["lines"]
			. append(
				{
					"key":
					"log.loot.auto_salvaged_one" if count == 1 else "log.loot.auto_salvaged_other",
					"params": {"count": count, "dust": out["salvage_dust"]},
				}
			)
		)
	for rune in rewards.get("runes", []):
		add_rune(state, rune["id"], int(rune["tier"]))
		out["runes"].append(rune.duplicate())
	for id in rewards.get("artifacts", []):
		if state["artifacts"].has(id):
			out["lines"].append(
				{"key": "log.loot.artifact_known", "params": {"artifact": id + ".name"}}
			)
			continue
		state["artifacts"][id] = 1
		out["artifacts"].append(id)
	var consumables: Dictionary = rewards.get("consumables", {})
	var ids := consumables.keys()
	ids.sort()
	for id in ids:
		var left := add_consumable(state, id, int(consumables[id]), content)
		var taken := int(consumables[id]) - left
		if taken > 0:
			out["consumables"][id] = taken
		if left > 0:
			(
				out["lines"]
				. append(
					{
						"key": "log.loot.consumable_overflow",
						"params":
						{"max": carry_max(id, content), "item": id + ".name", "count": left},
					}
				)
			)
	return out


## Dust and count a salvage of every bag item of these rarities would give
## (for the confirmation dialog).
static func salvage_quote(state: Dictionary, rarities: Array) -> Dictionary:
	var uids := []
	var dust := 0
	for item in bag(state):
		if rarities.has(item["rarity"]):
			uids.append(item["uid"])
			dust += ItemFactory.salvage_value(item)
	return {"uids": uids, "count": uids.size(), "dust": dust}


## Salvages bag items into mana dust. Worn or unknown items are refused.
## Result extra: {count, dust}.
static func salvage(state: Dictionary, uids: Array) -> Dictionary:
	if uids.is_empty():
		return ActionResult.refuse("error.nothing_to_salvage")
	var on := worn(state)
	for uid in uids:
		if index_of(state, uid) < 0 or on.has(uid):
			return ActionResult.refuse("error.item_not_found", {"uid": uid})
	var next := state.duplicate(true)
	var dust := 0
	for uid in uids:
		var i := index_of(next, uid)
		dust += ItemFactory.salvage_value(next["inventory"][i])
		next["inventory"].remove_at(i)
	add_material(next, BalanceItems.DUST_ID, dust)
	return ActionResult.success(next, {"count": uids.size(), "dust": dust})


## Bulk salvage of every bag item whose rarity is in `rarities`.
static func salvage_by_rarity(state: Dictionary, rarities: Array) -> Dictionary:
	return salvage(state, salvage_quote(state, rarities)["uids"])
