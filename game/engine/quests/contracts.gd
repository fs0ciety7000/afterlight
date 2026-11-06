class_name Contracts
extends RefCounted
## Daily contracts (docs/content/contracts.md). Pure: the clock arrives as
## (now_unix, tz_offset_s).
##
## progress.contracts = {day_index, offers: [{id, count, state, reward:
## {gold, dust, shards}}]}; state "active" -> "completed" -> "turned_in".
## day_index -1 means "never rolled" (new game, migrated save).
##
## Events: contracts_rolled {day_index, offers: [id]}, contracts_auto_claimed
## {gold, dust, shards, count}, contract_progress {id, count, target},
## contract_completed {id}.

const ACTIVE := "active"
const COMPLETED := "completed"
const TURNED_IN := "turned_in"


## Pool entries whose eligibility condition holds now, sorted by id.
static func eligible(state: Dictionary, content: Dictionary) -> Array:
	var out := []
	for id in content:
		var q: Dictionary = content[id]
		if q.get("_type", "") == "quest" and q["kind"] == "daily":
			if QuestRules.prerequisites_met(state, q, content):
				out.append(id)
	out.sort()
	return out


## Up to CONTRACTS_PER_DAY ids drawn without replacement, weighted, from
## `pool`, with at most CONTRACT_MAX_LONG of tier L (a second L is set aside
## and the draw goes on). Same seed, day and pool: same contracts.
static func roll(seed_value: int, day: int, pool: Array, content: Dictionary) -> Array:
	var rng := SeededRng.new(SeededRng.derive_seed(seed_value, "contracts", day))
	var weights := {}
	for id in pool:
		weights[id] = float(content[id].get("weight", 1.0))
	var out := []
	var longs := 0
	while out.size() < BalanceStory.CONTRACTS_PER_DAY and not weights.is_empty():
		var id: String = rng.pick_weighted(weights)
		weights.erase(id)
		if content[id]["tier"] == "L":
			if longs >= BalanceStory.CONTRACT_MAX_LONG:
				continue
			longs += 1
		out.append(id)
	return out


## Rolls a new day when the local day moved forward: yesterday's completed
## contracts are claimed for the player, unfinished ones vanish. A clock moved
## back keeps the current contracts; several days away give a single draw.
## Never call it during a fight. Mutates `next`.
static func refresh(
	next: Dictionary, now_unix: int, tz_offset_s: int, content: Dictionary, events: Array
) -> void:
	var book: Dictionary = next["progress"]["contracts"]
	var day := BalanceStory.day_index(now_unix, tz_offset_s)
	if day <= int(book["day_index"]):
		return
	var claimed := {"gold": 0, "dust": 0, "shards": 0, "count": 0}
	for offer in book["offers"]:
		if offer["state"] == COMPLETED:
			_credit(next, offer["reward"])
			for k in ["gold", "dust", "shards"]:
				claimed[k] += int(offer["reward"][k])
			claimed["count"] += 1
	if claimed["count"] > 0:
		claimed["type"] = "contracts_auto_claimed"
		events.append(claimed)
	var level := int(next["characters"][next["party"][0]]["level"])
	var offers := []
	for id in roll(int(next["meta"]["seed"]), day, eligible(next, content), content):
		(
			offers
			. append(
				{
					"id": id,
					"count": 0,
					"state": ACTIVE,
					"reward": BalanceStory.contract_reward(content[id]["tier"], level),
				}
			)
		)
	book["day_index"] = day
	book["offers"] = offers
	events.append(
		{
			"type": "contracts_rolled",
			"day_index": day,
			"offers": offers.map(func(o: Dictionary) -> String: return o["id"])
		}
	)


## Counts a played fight (encounter_completed) for the active contracts.
static func on_event(
	next: Dictionary, event: Dictionary, content: Dictionary, events: Array
) -> void:
	for offer in next["progress"]["contracts"]["offers"]:
		if offer["state"] != ACTIVE or not content.has(offer["id"]):
			continue
		var o: Dictionary = content[offer["id"]]["objectives"][0]
		var add := QuestRules.gain(o, event, content)
		if add <= 0:
			continue
		offer["count"] = mini(int(o["count"]), int(offer["count"]) + add)
		events.append(
			{
				"type": "contract_progress",
				"id": offer["id"],
				"count": offer["count"],
				"target": int(o["count"])
			}
		)
		if int(offer["count"]) >= int(o["count"]):
			offer["state"] = COMPLETED
			events.append({"type": "contract_completed", "id": offer["id"]})


## "Récupérer": credits a completed contract once. Result extra: {id, reward}.
static func claim(state: Dictionary, contract_id: String) -> Dictionary:
	var offers: Array = state["progress"]["contracts"]["offers"]
	for i in offers.size():
		if offers[i]["id"] != contract_id:
			continue
		if offers[i]["state"] != COMPLETED:
			return ActionResult.refuse("error.contract.not_completed")
		var next := state.duplicate(true)
		var offer: Dictionary = next["progress"]["contracts"]["offers"][i]
		_credit(next, offer["reward"])
		offer["state"] = TURNED_IN
		return ActionResult.success(
			next, {"id": contract_id, "reward": offer["reward"].duplicate()}
		)
	return ActionResult.refuse("error.contract.unknown")


static func _credit(next: Dictionary, reward: Dictionary) -> void:
	next["wallet"]["gold"] = int(next["wallet"]["gold"]) + int(reward["gold"])
	Inventory.add_material(next, BalanceItems.DUST_ID, int(reward["dust"]))
	Inventory.add_material(next, BalanceGrimoire.SHARD_ID, int(reward["shards"]))


## Contract cards: [{id, tier, count, needed, state, reward, key}].
static func view(state: Dictionary, content: Dictionary) -> Array:
	var out := []
	for offer in state["progress"]["contracts"]["offers"]:
		var q: Dictionary = content.get(offer["id"], {})
		if q.is_empty():
			continue
		(
			out
			. append(
				{
					"id": offer["id"],
					"tier": q["tier"],
					"count": int(offer["count"]),
					"needed": int(q["objectives"][0]["count"]),
					"state": offer["state"],
					"reward": offer["reward"].duplicate(),
					"key": "%s.objective_main" % offer["id"],
				}
			)
		)
	return out


## True when a contract waits for "Récupérer" (the discreet journal icon).
static func has_claimable(state: Dictionary) -> bool:
	for offer in state["progress"]["contracts"]["offers"]:
		if offer["state"] == COMPLETED:
			return true
	return false
