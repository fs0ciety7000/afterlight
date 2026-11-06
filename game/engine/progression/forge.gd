class_name Forge
extends RefCounted
## Enhancement at the forge (GDD §10.2, GAME_BALANCE §15). Success is
## guaranteed up to +5, then ENH_SUCCESS[n] + pity; a failure keeps the level,
## gives back part of the gold and adds pity, a success resets it.
## Anti-reload: the roll only depends on (game seed, item uid, attempt count),
## so reloading a save can never change the outcome of the next attempt.


## What the next attempt costs and its chance, or a refusal.
## Result extra: {uid, from, to, max, gold, dust, chance, pity_bonus}.
static func quote(state: Dictionary, uid: String) -> Dictionary:
	var item := Inventory.find(state, uid)
	if item.is_empty():
		return ActionResult.refuse("error.item_not_found", {"uid": uid})
	var n := int(item["enhance"])
	var top := BalanceItems.enhance_max(item["rarity"])
	var fails := int(item["pity"])
	var info := {
		"uid": uid,
		"from": n,
		"to": mini(n + 1, top),
		"max": top,
		"gold": BalanceItems.enhance_gold(int(item["item_level"]), n),
		"dust": BalanceItems.enhance_dust(n),
		"chance": BalanceItems.enhance_chance(n, fails),
		"pity_bonus": BalanceItems.ENH_PITY_PER_FAIL * float(fails),
	}
	if n >= top:
		var refused := ActionResult.refuse("error.enhance_max", {"max": top})
		refused.merge(info)
		return refused
	var lack := ActionResult.check_cost(state["wallet"], _cost(info))
	if not lack.is_empty():
		lack.merge(info)
		return lack
	return ActionResult.success(state, info)


## Rolls one attempt. Result extra: quote fields + {success, level, refund,
## attempt}. The new state carries the incremented attempt count and pity.
static func enhance(state: Dictionary, uid: String) -> Dictionary:
	var q := quote(state, uid)
	if not q["ok"]:
		return q
	var next := state.duplicate(true)
	var item: Dictionary = next["inventory"][Inventory.index_of(next, uid)]
	var attempt := int(item["enhance_attempts"])
	var success := roll(int(next["meta"]["seed"]), uid, attempt) < float(q["chance"])
	ActionResult.pay(next["wallet"], _cost(q))
	var refund := 0
	item["enhance_attempts"] = attempt + 1
	if success:
		item["enhance"] = int(item["enhance"]) + 1
		item["pity"] = 0
	else:
		item["pity"] = int(item["pity"]) + 1
		refund = BalanceItems.enhance_refund(int(q["gold"]))
		next["wallet"]["gold"] = int(next["wallet"]["gold"]) + refund
	var extra: Dictionary = q.duplicate()
	extra.erase("state")
	extra.erase("ok")
	extra.merge(
		{"success": success, "level": item["enhance"], "refund": refund, "attempt": attempt}, true
	)
	return ActionResult.success(next, extra)


## Uniform [0, 1) draw of attempt `attempt` on item `uid`, independent of
## every other stream.
static func roll(game_seed: int, uid: String, attempt: int) -> float:
	return SeededRng.new(SeededRng.derive_seed(game_seed, "enhance:" + uid, attempt)).next_float()


static func _cost(info: Dictionary) -> Dictionary:
	return {"gold": info["gold"], "materials": {BalanceItems.DUST_ID: info["dust"]}}
