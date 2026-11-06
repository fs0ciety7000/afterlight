class_name RuneRules
extends RefCounted
## Rune fusion and salvage at the runecarver (GDD §10.4, GAME_BALANCE §17):
## 3 identical runes of tier n (from the stock, never socketed ones) give one
## of tier n+1 for gold and rune shards, always successfully.


## Result extra: {rune, tier, to, gold, shards, required, owned}.
static func fusion_quote(
	state: Dictionary, rune: String, tier: int, content: Dictionary
) -> Dictionary:
	if content.get(rune, {}).get("_type", "") != "rune" or tier < 1:
		return ActionResult.refuse("error.rune_not_owned", {"rune": rune + ".name", "tier": tier})
	if tier >= BalanceGrimoire.RUNE_TIER_MAX:
		return ActionResult.refuse("error.rune_tier_max", {"max": BalanceGrimoire.RUNE_TIER_MAX})
	var info := {
		"rune": rune,
		"tier": tier,
		"to": tier + 1,
		"gold": BalanceGrimoire.fusion_gold(tier),
		"shards": BalanceGrimoire.fusion_shards(tier),
		"required": BalanceGrimoire.FUSION_INPUT,
		"owned": Inventory.rune_count(state, rune, tier),
	}
	if int(info["owned"]) < BalanceGrimoire.FUSION_INPUT:
		var refused := ActionResult.refuse(
			"error.fusion_not_enough_runes", {"required": info["required"], "owned": info["owned"]}
		)
		refused.merge(info)
		return refused
	var lack := ActionResult.check_cost(state["wallet"], _cost(info))
	if not lack.is_empty():
		lack.merge(info)
		return lack
	return ActionResult.success(state, info)


static func fuse(state: Dictionary, rune: String, tier: int, content: Dictionary) -> Dictionary:
	var q := fusion_quote(state, rune, tier, content)
	if not q["ok"]:
		return q
	var next := state.duplicate(true)
	ActionResult.pay(next["wallet"], _cost(q))
	Inventory.add_rune(next, rune, tier, -BalanceGrimoire.FUSION_INPUT)
	Inventory.add_rune(next, rune, tier + 1)
	var extra: Dictionary = q.duplicate()
	extra.erase("state")
	return ActionResult.success(next, extra)


## Salvages `qty` stock runes of (rune, tier) into shards. Result extra:
## {shards}.
static func salvage(state: Dictionary, rune: String, tier: int, qty: int = 1) -> Dictionary:
	if qty < 1:
		return ActionResult.refuse("error.invalid_quantity")
	if Inventory.rune_count(state, rune, tier) < qty:
		return ActionResult.refuse("error.rune_not_owned", {"rune": rune + ".name", "tier": tier})
	var next := state.duplicate(true)
	Inventory.add_rune(next, rune, tier, -qty)
	var shards := BalanceGrimoire.rune_salvage_shards(tier) * qty
	Inventory.add_material(next, BalanceGrimoire.SHARD_ID, shards)
	return ActionResult.success(next, {"shards": shards})


static func _cost(info: Dictionary) -> Dictionary:
	return {"gold": info["gold"], "materials": {BalanceGrimoire.SHARD_ID: info["shards"]}}
