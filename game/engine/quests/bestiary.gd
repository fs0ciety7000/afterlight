class_name Bestiary
extends RefCounted
## Bestiary (docs/content/bestiary_discoveries.md §1): progress.bestiary maps
## an enemy id to its victories in played fights (normal or "Chasser ici";
## offline victories never count). An entry at 0 means "met, never beaten".
## Tiers come from the count and the enemy's bestiary_thresholds.
##
## Event: bestiary_tier_unlocked {enemy_id, tier}.


static func thresholds(enemy_id: String, content: Dictionary) -> Array:
	var t: Array = content.get(enemy_id, {}).get("bestiary_thresholds", [])
	return t if not t.is_empty() else BalanceStory.BESTIARY_THRESHOLDS


static func victories(state: Dictionary, enemy_id: String) -> int:
	return int(state["progress"]["bestiary"].get(enemy_id, 0))


static func tier(state: Dictionary, enemy_id: String, content: Dictionary) -> int:
	return BalanceStory.bestiary_tier(victories(state, enemy_id), thresholds(enemy_id, content))


## Records a played fight (CombatSim's encounter_completed): every enemy of
## the encounter is met, every kill (summons included) counts. Mutates `next`.
static func record(
	next: Dictionary, completed: Dictionary, content: Dictionary, events: Array
) -> void:
	var book: Dictionary = next["progress"]["bestiary"]
	for group in content.get(str(completed.get("encounter", "")), {}).get("enemies", []):
		if not book.has(group["enemy"]):
			book[group["enemy"]] = 0
	var defeated: Dictionary = completed.get("tally", {}).get("defeated", {})
	var ids := defeated.keys()
	ids.sort()
	for id in ids:
		var before := tier(next, id, content)
		book[id] = victories(next, id) + int(defeated[id])
		var after := tier(next, id, content)
		for t in range(before + 1, after + 1):
			events.append({"type": "bestiary_tier_unlocked", "enemy_id": id, "tier": t})


## Bestiary page: met enemies sorted by id, [{enemy_id, victories, tier,
## thresholds, next (victories for the next tier, 0 at the last)}].
static func view(state: Dictionary, content: Dictionary) -> Array:
	var out := []
	var ids: Array = state["progress"]["bestiary"].keys()
	ids.sort()
	for id in ids:
		if content.get(id, {}).get("_type", "") != "enemy":
			continue
		var t := thresholds(id, content)
		var current := tier(state, id, content)
		(
			out
			. append(
				{
					"enemy_id": id,
					"victories": victories(state, id),
					"tier": current,
					"thresholds": t.duplicate(),
					"next": int(t[current]) if current < t.size() else 0,
				}
			)
		)
	return out
