class_name ActionResult
extends RefCounted
## Uniform result of a progression action (equip, enhance, fuse, buy...).
## {ok, error, params, state, ...}: on success `state` is the new game state
## (the input is never mutated); on refusal `error` is a translation key
## (game/i18n/strings.csv, "error.*") and `params` fills its placeholders, so
## a disabled button can show its reason ("Or insuffisant : 141 requis").


static func success(state: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var out := {"ok": true, "error": "", "params": {}, "state": state}
	out.merge(extra, true)
	return out


static func refuse(error: String, params: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": error, "params": params, "state": {}}


## Refusal when `wallet` lacks gold or a material, or {} when it can pay.
## `cost` = {gold: int, materials: {id: qty}}.
static func check_cost(wallet: Dictionary, cost: Dictionary) -> Dictionary:
	var gold := int(cost.get("gold", 0))
	if int(wallet["gold"]) < gold:
		return refuse("error.not_enough_gold", {"required": gold, "owned": int(wallet["gold"])})
	var materials: Dictionary = cost.get("materials", {})
	var ids := materials.keys()
	ids.sort()
	for id in ids:
		var owned := int(wallet["materials"].get(id, 0))
		if owned < int(materials[id]):
			return refuse(
				"error.not_enough_material",
				{"material": id + ".name", "required": int(materials[id]), "owned": owned}
			)
	return {}


## Takes a cost the wallet can pay (check_cost first).
static func pay(wallet: Dictionary, cost: Dictionary) -> void:
	wallet["gold"] = int(wallet["gold"]) - int(cost.get("gold", 0))
	var materials: Dictionary = cost.get("materials", {})
	for id in materials:
		wallet["materials"][id] = int(wallet["materials"].get(id, 0)) - int(materials[id])
