class_name Discoveries
extends RefCounted
## Discoveries, chests and quest pickups (docs/content/bestiary_discoveries.md
## §2). Pure. progress.discoveries lists what was found, once and for all; the
## map fog is derived from it (fog_discs), nothing else is saved.
##
## Event: discovery_found {discovery_id, location_id, counted, xp, gold,
## materials, items: [uid], runes, artifacts, reveals, levels_gained}.


static func found(state: Dictionary, discovery_id: String) -> bool:
	return state["progress"]["discoveries"].has(discovery_id)


## Why a discovery cannot be taken now ({} when it can). `dungeon_run` gates
## the chests of a dungeon room behind its victory.
static func check(state: Dictionary, discovery_id: String, content: Dictionary) -> Dictionary:
	var d: Dictionary = content.get(discovery_id, {})
	if d.get("_type", "") != "discovery":
		return ActionResult.refuse("error.discovery.unknown")
	if found(state, discovery_id):
		return ActionResult.refuse("error.discovery.found")
	if (
		not d["available_if"].is_empty()
		and not WorldRules.is_met(d["available_if"], state, content)
	):
		return ActionResult.refuse("error.discovery.unavailable")
	if d["room"] != "":
		var run: Dictionary = state["progress"]["dungeon_run"]
		if run.get("dungeon_id", "") != d["location"] or not run["cleared_rooms"].has(d["room"]):
			return ActionResult.refuse("error.discovery.room_not_cleared")
	return {}


## Whether the scene shows it (herbs only while the herbalist's quest runs;
## nothing found comes back).
static func visible(state: Dictionary, discovery_id: String, content: Dictionary) -> bool:
	var r := check(state, discovery_id, content)
	return r.is_empty() or r["error"] == "error.discovery.room_not_cleared"


## Takes a discovery: XP (DISCOVERY_XP), materials, artifacts, a chest's loot
## (seeded by the game seed and the discovery id: a reload rolls the same
## chest), fog. The quest and other effects are applied by StoryEvents.
static func take(state: Dictionary, discovery_id: String, content: Dictionary) -> Dictionary:
	var refusal := check(state, discovery_id, content)
	if not refusal.is_empty():
		return refusal
	var d: Dictionary = content[discovery_id]
	var next := state.duplicate(true)
	next["progress"]["discoveries"].append(discovery_id)
	var reward: Dictionary = d["reward"]
	var leader: String = next["party"][0]
	var hero: Dictionary = next["characters"][leader]
	var xp := BalanceStory.discovery_xp(int(d["level"])) if reward["xp"] else 0
	var leveled := BalanceProgression.grant_xp(hero["level"], hero["xp"], xp)
	hero["level"] = leveled["level"]
	hero["xp"] = leveled["xp"]
	var loot := {
		"gold": 0,
		"materials": reward["materials"].duplicate(),
		"items": [],
		"runes": [],
		"artifacts": reward["artifacts"].duplicate()
	}
	if reward["loot_table"] != "":
		_roll_chest(next, discovery_id, d, content, loot)
	next["wallet"]["gold"] = int(next["wallet"]["gold"]) + int(loot["gold"])
	for id in loot["materials"]:
		Inventory.add_material(next, id, int(loot["materials"][id]))
	var received := Inventory.receive(next, loot, content)
	for place in d["reveals"]:
		WorldRules.reveal(next, place)
	var event := {
		"type": "discovery_found",
		"discovery_id": discovery_id,
		"location_id": d["location"],
		"counted": d["counts_for_location"],
		"xp": xp,
		"gold": int(loot["gold"]),
		"materials": loot["materials"],
		"items": received["items"],
		"runes": received["runes"],
		"artifacts": received["artifacts"],
		"reveals": d["reveals"].duplicate(),
		"levels_gained": leveled["levels_gained"],
		"lines": received["lines"],
	}
	return ActionResult.success(next, {"event": event})


## Rolls a chest table (GAME_BALANCE §13): gold CHEST_GOLD_MULT × enemy gold
## at the chest level, then materials, items and runes. Fills `loot`.
static func _roll_chest(
	state: Dictionary, discovery_id: String, d: Dictionary, content: Dictionary, loot: Dictionary
) -> void:
	var table: Dictionary = content.get(d["reward"]["loot_table"], {})
	var rng := SeededRng.new(
		SeededRng.derive_seed(int(state["meta"]["seed"]), "chest:" + discovery_id)
	)
	var level := int(d["level"])
	var profile: String = table.get("rarity_profile", "chest")
	var ilvl := BalanceItems.item_level(level, "normal")
	var gold_find := float(Equipment.stats(state, state["party"][0], content).get("gold_find", 0.0))
	for entry in table.get("entries", []):
		if not rng.chance(float(entry["chance"])):
			continue
		var ref: String = entry.get("ref", "")
		match entry["kind"]:
			"gold":
				var roll := rng.range_float(
					BalanceEnemies.GOLD_ROLL_MIN, BalanceEnemies.GOLD_ROLL_MAX
				)
				loot["gold"] += roundi(
					(
						BalanceStory.CHEST_GOLD_MULT
						* BalanceEnemies.enemy_gold(level, 1.0, roll, gold_find)
					)
				)
			"material":
				var qty := rng.range_int(int(entry["qty"][0]), int(entry["qty"][1]))
				loot["materials"][ref] = int(loot["materials"].get(ref, 0)) + qty
			"item":
				for n in rng.range_int(int(entry["qty"][0]), int(entry["qty"][1])):
					var item := (
						ItemFactory.make_item(
							rng, content, ref, ItemFactory.roll_rarity(rng, profile), ilvl
						)
						if ref != ""
						else ItemFactory.roll_item(rng, content, profile, ilvl)
					)
					if not item.is_empty():
						loot["items"].append(item)
			"rune":
				for n in rng.range_int(int(entry["qty"][0]), int(entry["qty"][1])):
					var rune := ItemFactory.roll_rune(rng, content, profile)
					if not rune.is_empty():
						loot["runes"].append(rune)
			"artifact":
				if not loot["artifacts"].has(ref):
					loot["artifacts"].append(ref)


## "Découvertes n/2" of a place: counted discoveries only.
static func counts(state: Dictionary, place_id: String, content: Dictionary) -> Dictionary:
	var total := 0
	var have := 0
	for id in content.get(place_id, {}).get("discoveries", []):
		var d: Dictionary = content.get(id, {})
		if d.get("counts_for_location", false):
			total += 1
			if found(state, id):
				have += 1
	return {"found": have, "total": total}


## Holes in the painted map's veil: one disc per counted discovery found.
## [{discovery_id, map_pos: [x, y], radius}] (normalized 0-1).
static func fog_discs(state: Dictionary, content: Dictionary) -> Array:
	var out := []
	for id in state["progress"]["discoveries"]:
		var d: Dictionary = content.get(id, {})
		if d.is_empty() or float(d.get("fog_radius", 0.0)) <= 0.0 or d["map_pos"].is_empty():
			continue
		out.append(
			{"discovery_id": id, "map_pos": d["map_pos"].duplicate(), "radius": d["fog_radius"]}
		)
	return out


## Counted discoveries of a place not found yet (shown as "?" with the
## traveler's compass worn).
static func hidden_in(state: Dictionary, place_id: String, content: Dictionary) -> Array:
	var out := []
	for id in content.get(place_id, {}).get("discoveries", []):
		var d: Dictionary = content.get(id, {})
		if d.get("counts_for_location", false) and not found(state, id):
			out.append(id)
	return out


## Discoveries of a place the scene should show now:
## [{id, kind, trigger, anchor, counted, found}].
static func in_place(state: Dictionary, place_id: String, content: Dictionary) -> Array:
	var out := []
	var ids: Array = content.get(place_id, {}).get("discoveries", []).duplicate()
	for id in content:
		var d: Dictionary = content[id]
		if d.get("_type", "") == "discovery" and d["location"] == place_id and not ids.has(id):
			ids.append(id)
	for id in ids:
		var d: Dictionary = content.get(id, {})
		if d.is_empty() or not (found(state, id) or visible(state, id, content)):
			continue
		(
			out
			. append(
				{
					"id": id,
					"kind": d["kind"],
					"trigger": d["trigger"],
					"anchor": d["anchor"],
					"counted": d["counts_for_location"],
					"found": found(state, id),
				}
			)
		)
	return out
