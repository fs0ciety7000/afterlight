class_name Merchant
extends RefCounted
## Consumable shop (GDD §10.6, GAME_BALANCE §19). Prices grow with the
## party leader's level; carried consumables are capped (carry_max, 5).
## No item resale: only salvage exists.


static func price(state: Dictionary, consumable: String, content: Dictionary) -> int:
	var leader: String = state["party"][0]
	var level := int(state["characters"][leader]["level"])
	return BalanceEconomy.price(int(content.get(consumable, {}).get("price_base", 0)), level)


## Stock of a shop: [{id, price, carried, carry_max}].
static func stock(state: Dictionary, shop: String, content: Dictionary) -> Array:
	var out := []
	for id in content.get(shop, {}).get("stock", []):
		var line := {
			"id": id,
			"price": price(state, id, content),
			"carried": int(state["consumables"].get(id, 0)),
			"carry_max": Inventory.carry_max(id, content),
		}
		out.append(line)
	return out


## Result extra: {consumable, qty, price, gold (total), carried}.
static func buy_quote(
	state: Dictionary, shop: String, consumable: String, qty: int, content: Dictionary
) -> Dictionary:
	if not content.get(shop, {}).get("stock", []).has(consumable):
		return ActionResult.refuse("error.not_in_stock", {"item": consumable + ".name"})
	if qty < 1:
		return ActionResult.refuse("error.invalid_quantity")
	var cap := Inventory.carry_max(consumable, content)
	var carried := int(state["consumables"].get(consumable, 0))
	var info := {
		"consumable": consumable,
		"qty": qty,
		"price": price(state, consumable, content),
		"gold": price(state, consumable, content) * qty,
		"carried": carried,
	}
	if carried + qty > cap:
		var refused := ActionResult.refuse("error.carry_max", {"max": cap})
		refused.merge(info)
		return refused
	var lack := ActionResult.check_cost(state["wallet"], {"gold": info["gold"]})
	if not lack.is_empty():
		lack.merge(info)
		return lack
	return ActionResult.success(state, info)


static func buy(
	state: Dictionary, shop: String, consumable: String, qty: int, content: Dictionary
) -> Dictionary:
	var q := buy_quote(state, shop, consumable, qty, content)
	if not q["ok"]:
		return q
	var next := state.duplicate(true)
	ActionResult.pay(next["wallet"], {"gold": q["gold"]})
	Inventory.add_consumable(next, consumable, qty, content)
	var extra: Dictionary = q.duplicate()
	extra.erase("state")
	extra["carried"] = int(next["consumables"][consumable])
	return ActionResult.success(next, extra)
