class_name DungeonRun
extends RefCounted
## A dungeon expedition (docs/content/dungeon.md §2.3). Pure.
##
## progress.dungeon_run = {} outside, else {dungeon_id, checkpoint ("entrance"
## or a checkpoint room id), room (current room id), cleared_rooms: [room id],
## fountain_used, vitals: {hp_pct, mana_pct, ult_charge}}.
## HP do not come back between rooms (vitals carry over to the next fight);
## a defeat sends Fern back to the checkpoint, full, rooms kept; leaving resets
## everything. While inside, world.location_id stays the dungeon's location
## with spawn "from_cloister": a save without the run falls back there.
##
## Events: dungeon_entered {dungeon_id, first}, dungeon_room_entered {room,
## kind}, dungeon_checkpoint {room}, dungeon_room_cleared {room, encounter},
## dungeon_respawn {checkpoint, room}, dungeon_shortcut_opened {dungeon_id},
## dungeon_left {dungeon_id}.

const ENTRANCE := "entrance"
const FALLBACK_SPAWN := "from_cloister"
const COMBAT_KINDS := ["encounter", "elite", "boss"]


static func run(state: Dictionary) -> Dictionary:
	return state["progress"].get("dungeon_run", {})


static func inside(state: Dictionary) -> bool:
	return not run(state).is_empty()


static func full_vitals(ult_charge: float = 0.0) -> Dictionary:
	return {"hp_pct": 1.0, "mana_pct": 1.0, "ult_charge": ult_charge}


static func rooms(dungeon: Dictionary) -> Array:
	return dungeon.get("rooms", [])


static func room_index(dungeon: Dictionary, room_id: String) -> int:
	var list := rooms(dungeon)
	for i in list.size():
		if list[i]["id"] == room_id:
			return i
	return -1


## Room id where a checkpoint puts Fern back.
static func checkpoint_room(dungeon: Dictionary, checkpoint: String) -> String:
	if checkpoint != ENTRANCE and room_index(dungeon, checkpoint) >= 0:
		return checkpoint
	return rooms(dungeon)[0]["id"] if not rooms(dungeon).is_empty() else ""


## The shortcut (bell-ringer's stair, vestibule to campfire) opens after the
## first victory over the dungeon's boss.
static func shortcut_open(state: Dictionary, dungeon: Dictionary) -> bool:
	for room in rooms(dungeon):
		if room["kind"] == "boss":
			return int(state["progress"]["cleared_encounters"].get(room["encounter"], 0)) > 0
	return false


## Rooms Fern can walk into from the first room. The door between two rooms
## opens once the first of them is won (rest rooms need no fight); a rest or
## checkpoint room also opens its door back to the room before it. The
## shortcut joins the first room, once won, to the first checkpoint room.
static func accessible(state: Dictionary, dungeon: Dictionary) -> Array:
	var r := run(state)
	var list := rooms(dungeon)
	if r.is_empty() or list.is_empty():
		return []
	var cleared: Array = r["cleared_rooms"]
	var open := {0: true}
	var stack := [0]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var links := []
		var passed := _passed(list[i], cleared)
		if i > 0 and (_passed(list[i - 1], cleared) or not COMBAT_KINDS.has(list[i]["kind"])):
			links.append(i - 1)
		if i + 1 < list.size() and passed:
			links.append(i + 1)
		if i == 0 and passed and shortcut_open(state, dungeon):
			for j in list.size():
				if list[j]["kind"] == "checkpoint":
					links.append(j)
					break
		for j in links:
			if not open.has(j):
				open[j] = true
				stack.append(j)
	var out := []
	for i in list.size():
		if open.has(i):
			out.append(list[i]["id"])
	return out


static func _passed(room: Dictionary, cleared: Array) -> bool:
	return not COMBAT_KINDS.has(room["kind"]) or cleared.has(room["id"])


## Enters a dungeon (the postern of its location). Result extra: {events}.
static func enter(state: Dictionary, dungeon_id: String, content: Dictionary) -> Dictionary:
	var d: Dictionary = content.get(dungeon_id, {})
	if d.get("_type", "") != "dungeon":
		return ActionResult.refuse("error.dungeon.unknown")
	if inside(state):
		return ActionResult.refuse("error.dungeon.already_inside")
	if not WorldRules.is_met(d["unlock"], state, content):
		var why := WorldRules.reason(d["unlock"], state, content)
		return ActionResult.refuse("error.dungeon.locked", why["params"])
	var next := state.duplicate(true)
	var first: bool = not next["world"]["discovered_locations"].has(dungeon_id)
	WorldRules.visit(dungeon_id, next, content)
	next["world"]["location_id"] = d["location"]
	next["world"]["spawn"] = FALLBACK_SPAWN
	next["progress"]["dungeon_run"] = {
		"dungeon_id": dungeon_id,
		"checkpoint": ENTRANCE,
		"room": checkpoint_room(d, ENTRANCE),
		"cleared_rooms": [],
		"fountain_used": false,
		"vitals": full_vitals(),
	}
	var events := [{"type": "dungeon_entered", "dungeon_id": dungeon_id, "first": first}]
	return ActionResult.success(next, {"events": events, "first": first})


## Leaving resets the expedition. Result extra: {events, confirm (rooms were
## won: ui.dungeon.leave_confirm before leaving)}.
static func leave(state: Dictionary) -> Dictionary:
	var r := run(state)
	if r.is_empty():
		return ActionResult.refuse("error.dungeon.not_inside")
	var next := state.duplicate(true)
	next["progress"]["dungeon_run"] = {}
	next["world"]["spawn"] = FALLBACK_SPAWN
	return (
		ActionResult
		. success(
			next,
			{
				"events": [{"type": "dungeon_left", "dungeon_id": r["dungeon_id"]}],
				"confirm": not r["cleared_rooms"].is_empty(),
			}
		)
	)


## Walks into a room (a door, the shortcut). The first checkpoint room reached
## becomes the checkpoint. Result extra: {events, room, kind}.
static func move_to(state: Dictionary, room_id: String, content: Dictionary) -> Dictionary:
	var r := run(state)
	if r.is_empty():
		return ActionResult.refuse("error.dungeon.not_inside")
	var d: Dictionary = content.get(r["dungeon_id"], {})
	var i := room_index(d, room_id)
	if i < 0 or not accessible(state, d).has(room_id):
		return ActionResult.refuse("error.dungeon.room_closed")
	var next := state.duplicate(true)
	var nr: Dictionary = next["progress"]["dungeon_run"]
	nr["room"] = room_id
	var kind: String = rooms(d)[i]["kind"]
	var events := [{"type": "dungeon_room_entered", "room": room_id, "kind": kind}]
	if kind == "checkpoint" and nr["checkpoint"] != room_id:
		nr["checkpoint"] = room_id
		events.append({"type": "dungeon_checkpoint", "room": room_id})
	return ActionResult.success(next, {"events": events, "room": room_id, "kind": kind})


## Fountain (rest room): +heal_pct of max HP, once per expedition.
static func use_fountain(state: Dictionary, content: Dictionary) -> Dictionary:
	var room := _current(state, content)
	if room.is_empty():
		return ActionResult.refuse("error.dungeon.not_inside")
	if room["kind"] != "rest":
		return ActionResult.refuse("error.dungeon.not_here")
	if run(state)["fountain_used"]:
		return ActionResult.refuse("error.dungeon.fountain_used")
	var next := state.duplicate(true)
	var nr: Dictionary = next["progress"]["dungeon_run"]
	nr["fountain_used"] = true
	var heal := float(room.get("heal_pct", 0.0))
	nr["vitals"]["hp_pct"] = minf(1.0, float(nr["vitals"]["hp_pct"]) + heal)
	return ActionResult.success(next, {"heal_pct": heal, "vitals": nr["vitals"].duplicate()})


## Campfire (checkpoint room): HP and mana full, at will.
static func rest(state: Dictionary, content: Dictionary) -> Dictionary:
	var room := _current(state, content)
	if room.is_empty():
		return ActionResult.refuse("error.dungeon.not_inside")
	if room["kind"] != "checkpoint":
		return ActionResult.refuse("error.dungeon.not_here")
	var next := state.duplicate(true)
	var nr: Dictionary = next["progress"]["dungeon_run"]
	nr["vitals"] = full_vitals(float(nr["vitals"]["ult_charge"]))
	nr["checkpoint"] = room["id"]
	return ActionResult.success(next, {"vitals": nr["vitals"].duplicate()})


static func _current(state: Dictionary, content: Dictionary) -> Dictionary:
	var r := run(state)
	if r.is_empty():
		return {}
	var d: Dictionary = content.get(r["dungeon_id"], {})
	var i := room_index(d, str(r["room"]))
	return rooms(d)[i] if i >= 0 else {}


## Room whose encounter this is, in the running dungeon ({} if none).
static func room_of(state: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var r := run(state)
	if r.is_empty():
		return {}
	for room in rooms(content.get(r["dungeon_id"], {})):
		if room.get("encounter", "") == encounter_id:
			return room
	return {}


## Applies a room fight (encounter_completed, after CombatOutcome counted the
## clear). Mutates `next`.
static func on_combat(
	next: Dictionary, completed: Dictionary, content: Dictionary, events: Array
) -> void:
	var room := room_of(next, str(completed.get("encounter", "")), content)
	if room.is_empty():
		return
	var nr: Dictionary = next["progress"]["dungeon_run"]
	var d: Dictionary = content[nr["dungeon_id"]]
	if completed.get("result", "") == "victory":
		if not nr["cleared_rooms"].has(room["id"]):
			nr["cleared_rooms"].append(room["id"])
		var leader: Dictionary = completed.get("leader", {})
		nr["vitals"] = {
			"hp_pct": clampf(float(leader.get("hp_pct", 1.0)), 0.0, 1.0),
			"mana_pct": clampf(float(leader.get("mana_pct", 1.0)), 0.0, 1.0),
			"ult_charge": float(leader.get("ult_charge", 0.0)),
		}
		events.append(
			{"type": "dungeon_room_cleared", "room": room["id"], "encounter": room["encounter"]}
		)
		if (
			room["kind"] == "boss"
			and int(next["progress"]["cleared_encounters"].get(room["encounter"], 0)) == 1
		):
			events.append({"type": "dungeon_shortcut_opened", "dungeon_id": nr["dungeon_id"]})
		return
	nr["vitals"] = full_vitals()
	nr["room"] = checkpoint_room(d, nr["checkpoint"])
	events.append({"type": "dungeon_respawn", "checkpoint": nr["checkpoint"], "room": nr["room"]})


## At load: Fern stands at the saved checkpoint, full; a run that no longer
## matches the content is dropped (fallback at the location's from_cloister).
## Mutates `next`; returns true when something changed.
static func settle_on_load(next: Dictionary, content: Dictionary) -> bool:
	var r := run(next)
	if r.is_empty():
		return false
	var d: Dictionary = content.get(str(r.get("dungeon_id", "")), {})
	var complete := true
	for key in ["checkpoint", "room", "cleared_rooms", "fountain_used", "vitals"]:
		complete = complete and r.has(key)
	if d.get("_type", "") != "dungeon" or not complete:
		next["progress"]["dungeon_run"] = {}
		next["world"]["spawn"] = FALLBACK_SPAWN
		return true
	var kept := []
	for room_id in r["cleared_rooms"]:
		if room_index(d, room_id) >= 0:
			kept.append(room_id)
	r["cleared_rooms"] = kept
	r["room"] = checkpoint_room(d, str(r["checkpoint"]))
	if r["room"] != str(r["checkpoint"]):
		r["checkpoint"] = ENTRANCE
	r["vitals"] = full_vitals(float(r["vitals"].get("ult_charge", 0.0)))
	return true


## Party entry fields for the next room fight: {hp_pct, mana_pct, ult_charge}.
static func vitals(state: Dictionary) -> Dictionary:
	var r := run(state)
	return r["vitals"].duplicate() if not r.is_empty() else full_vitals()


## Rooms for the UI: [{id, kind, encounter, cleared, accessible, current,
## checkpoint, name_key}] plus the run flags.
static func view(state: Dictionary, content: Dictionary) -> Dictionary:
	var r := run(state)
	if r.is_empty():
		return {}
	var d: Dictionary = content.get(r["dungeon_id"], {})
	var open := accessible(state, d)
	var list := []
	for room in rooms(d):
		(
			list
			. append(
				{
					"id": room["id"],
					"kind": room["kind"],
					"encounter": room.get("encounter", ""),
					"cleared": r["cleared_rooms"].has(room["id"]),
					"accessible": open.has(room["id"]),
					"current": r["room"] == room["id"],
					"checkpoint": r["checkpoint"] == room["id"],
					"name_key": "%s.room_%s" % [r["dungeon_id"], room["id"]],
				}
			)
		)
	return {
		"dungeon_id": r["dungeon_id"],
		"room": r["room"],
		"checkpoint": r["checkpoint"],
		"fountain_used": r["fountain_used"],
		"shortcut_open": shortcut_open(state, d),
		"vitals": r["vitals"].duplicate(),
		"rooms": list,
	}
