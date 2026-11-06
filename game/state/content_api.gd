class_name ContentApi
extends RefCounted
## Milestone 6 actions and views for the UI: NPCs and dialogues, quests, daily
## contracts, bestiary, discoveries and the dungeon. Thin wrappers around the
## pure engine (game/engine/quests, game/engine/world), reached as
## `GameState.content_api`.
##
## Actions return {ok, error, params, ...} without the state, like
## ProgressionApi; on success GameState adopts the new state, saves it and
## emits `story_events(events)` with what changed (quest_activated,
## quest_progress, quest_completed, quest_turned_in, bestiary_tier_unlocked,
## discovery_found, contracts_rolled, dungeon_room_cleared...). A refusal's
## `error` is a strings.csv key filled by `params` (GameState.reason_text).

var _owner: Node


func _init(owner: Node) -> void:
	_owner = owner


func _data() -> Dictionary:
	return _owner.data


func _c() -> Dictionary:
	return Content.index()


## Adopts a successful result, emits its events, strips the state.
func _commit(r: Dictionary, events: Array = []) -> Dictionary:
	var out := r.duplicate()
	out.erase("state")
	if r["ok"]:
		var all: Array = events.duplicate()
		all.append_array(r.get("events", []))
		if r.has("event"):
			all.append(r["event"])
		_owner.commit_action(r["state"])
		_owner.emit_story_events(all)
	return out


# --- NPCs and dialogues --------------------------------------------------------


## What an NPC says now: {ok, error, params, npc_id, dialogue, lines:
## [{speaker, key}], offers, turns_in, role, opens_panel (smith, runecarver,
## merchant: open the service panel after the dialogue; board: the journal on
## the Contracts tab)}. Nothing changes until finish_talk().
func talk(npc_id: String) -> Dictionary:
	if not _owner.has_game():
		return ActionResult.refuse("error.npc.unknown")
	var pick := NpcRules.select(_data(), npc_id, _c())
	if pick.is_empty():
		return ActionResult.refuse("error.npc.unknown")
	var out := ActionResult.success({}, pick)
	out.erase("state")
	out["opens_panel"] = pick["role"] in ["smith", "runecarver", "merchant", "board"]
	return out


## End of the dialogue (read or skipped): TalkedTo objectives, quest offer or
## hand-in, save. {ok, error, params, events, offered, turned_in, rewards
## (quest_turned_in event or {}), next_dialogue (play it right after, "" if
## none)}.
func finish_talk(npc_id: String, dialogue_id: String) -> Dictionary:
	return _commit(NpcRules.finish(_data(), npc_id, dialogue_id, _c()))


## Quest marker over an NPC: "offer", "active", "turn_in" or "".
func npc_marker(npc_id: String) -> String:
	return NpcRules.marker(_data(), npc_id, _c()) if _owner.has_game() else ""


## NPCs of the current location: [{id, anchor, role, marker, name_key}].
func npcs_here() -> Array:
	var out := []
	if not _owner.has_game():
		return out
	var here: String = _data()["world"]["location_id"]
	for id in Content.get_entity(here).get("npcs", []):
		var npc := Content.get_entity(id)
		(
			out
			. append(
				{
					"id": id,
					"anchor": npc["anchor"],
					"role": npc["role"],
					"marker": npc_marker(id),
					"name_key": npc["name_key"],
				}
			)
		)
	return out


# --- Quests -----------------------------------------------------------------------


## "locked", "available", "active", "completed" or "turned_in".
func quest_state(quest_id: String) -> String:
	return QuestRules.state_of(_data(), quest_id, _c()) if _owner.has_game() else "locked"


## Accepts an available quest directly (the offer dialogue does it itself).
func accept_quest(quest_id: String) -> Dictionary:
	return _commit(QuestRules.accept(_data(), quest_id, _c()))


## Hands in a completed quest directly (the giver's dialogue does it itself).
func turn_in_quest(quest_id: String) -> Dictionary:
	return _commit(QuestRules.turn_in(_data(), quest_id, _c()))


## Journal: started quests, main first ([{id, kind, state, step, giver, level,
## objectives: [{id, key, count, needed, done, visible, step}]}]).
## Objective text: tr(key).format({"n": count}).
func quest_log() -> Array:
	return QuestRules.log_view(_data(), _c()) if _owner.has_game() else []


## The quest the HUD follows ("" if none).
func tracked_quest() -> String:
	return QuestRules.tracked(_data(), _c()) if _owner.has_game() else ""


## {xp, gold, materials, runes, artifacts, unlocks, memory} of a quest.
func quest_rewards(quest_id: String) -> Dictionary:
	return QuestRules.reward_preview(_data(), quest_id, _c()) if _owner.has_game() else {}


# --- Daily contracts ----------------------------------------------------------------


## Rolls the day's contracts when the local day moved on (call it when the
## journal or the board opens, never during a fight). {ok, new_day,
## auto_claimed: {gold, dust, shards, count} or {}, events}.
func refresh_contracts() -> Dictionary:
	if not _owner.has_game():
		return {"ok": false, "new_day": false, "auto_claimed": {}, "events": []}
	var next: Dictionary = _data().duplicate(true)
	var events := []
	Contracts.refresh(next, _owner.now_unix(), _owner.tz_offset_s(), _c(), events)
	var out := {"ok": true, "new_day": not events.is_empty(), "auto_claimed": {}, "events": events}
	for e in events:
		if e["type"] == "contracts_auto_claimed":
			out["auto_claimed"] = e.duplicate()
	if not events.is_empty():
		_owner.commit_action(next)
		_owner.emit_story_events(events)
	return out


## Contract cards [{id, tier, count, needed, state, reward: {gold, dust,
## shards}, key}]; text: tr(key).format({"n": count}).
func contracts() -> Array:
	return Contracts.view(_data(), _c()) if _owner.has_game() else []


## "Récupérer": {ok, error, params, id, reward}.
func claim_contract(contract_id: String) -> Dictionary:
	return _commit(Contracts.claim(_data(), contract_id))


## A contract waits for "Récupérer" (discreet icon on the Journal button).
func contracts_claimable() -> bool:
	return Contracts.has_claimable(_data()) if _owner.has_game() else false


# --- Bestiary -----------------------------------------------------------------------


## Met enemies: [{enemy_id, victories, tier (0-3), thresholds, next}].
func bestiary() -> Array:
	return Bestiary.view(_data(), _c()) if _owner.has_game() else []


# --- Discoveries --------------------------------------------------------------------


## Discoveries the scene of `place_id` shows: [{id, kind, trigger, anchor,
## counted, found}] (herbs only during the herbalist's quest).
func discoveries_in(place_id: String) -> Array:
	return Discoveries.in_place(_data(), place_id, _c()) if _owner.has_game() else []


## Why a discovery cannot be taken ({ok, error, params}).
func discovery_check(discovery_id: String) -> Dictionary:
	var r := Discoveries.check(_data(), discovery_id, _c())
	return {"ok": true, "error": "", "params": {}} if r.is_empty() else _strip(r)


## Takes a discovery, a chest or a herb: {ok, error, params, event:
## {discovery_id, location_id, counted, xp, gold, materials, items, runes,
## artifacts, reveals, levels_gained, lines}}. Quests see it; saves.
func take_discovery(discovery_id: String) -> Dictionary:
	var r := Discoveries.take(_data(), discovery_id, _c())
	if not r["ok"]:
		return _strip(r)
	var events := []
	var e: Dictionary = r["event"]
	StoryEvents.feed(r["state"], e, _c(), events)
	for id in e["materials"]:
		var collected := {"type": "item_collected", "item_id": id, "qty": int(e["materials"][id])}
		StoryEvents.feed(r["state"], collected, _c(), events)
	var out := _commit(r, events)
	out["events"] = [e] + events
	return out


## "Découvertes n/2" of a place: {found, total}.
func discovery_counts(place_id: String) -> Dictionary:
	return Discoveries.counts(_data(), place_id, _c()) if _owner.has_game() else {}


## Holes in the map veil: [{discovery_id, map_pos, radius}].
func fog_discs() -> Array:
	return Discoveries.fog_discs(_data(), _c()) if _owner.has_game() else []


## Counted discoveries not found yet in a place ("?" with the compass worn).
func compass_hints(place_id: String) -> Array:
	return Discoveries.hidden_in(_data(), place_id, _c()) if _owner.has_game() else []


# --- Dungeon --------------------------------------------------------------------------


## Enters the dungeon by its postern: {ok, error, params, events, first}
## (error.dungeon.locked names the quest to finish).
func enter_dungeon(dungeon_id: String) -> Dictionary:
	var r := DungeonRun.enter(_data(), dungeon_id, _c())
	if r["ok"]:
		StoryEvents.visited(r["state"], dungeon_id, _c(), r["events"])
	return _commit(r)


## {ok, error, params, confirm}: confirm = rooms were won, show
## ui.dungeon.leave_confirm first. Changes nothing.
func leave_dungeon_quote() -> Dictionary:
	return _strip(DungeonRun.leave(_data()))


## Leaves (door, exit after the boss, travel): the run is reset.
func leave_dungeon() -> Dictionary:
	return _commit(DungeonRun.leave(_data()))


## Walks into a room (door or shortcut): {ok, error, params, events, room, kind}.
func dungeon_move(room_id: String) -> Dictionary:
	return _commit(DungeonRun.move_to(_data(), room_id, _c()))


## Fountain: {ok, error, params, heal_pct, vitals}.
func use_fountain() -> Dictionary:
	return _commit(DungeonRun.use_fountain(_data(), _c()))


## Campfire: HP and mana full, save. {ok, error, params, vitals}.
func rest_at_campfire() -> Dictionary:
	return _commit(DungeonRun.rest(_data(), _c()))


## {dungeon_id, room, checkpoint, fountain_used, shortcut_open, vitals, rooms:
## [{id, kind, encounter, cleared, accessible, current, checkpoint, name_key}]}
## or {} outside.
func dungeon_view() -> Dictionary:
	return DungeonRun.view(_data(), _c()) if _owner.has_game() else {}


## {hp_pct, mana_pct, ult_charge} to merge into the party entry of the next
## room fight (HP do not come back between rooms).
func dungeon_vitals() -> Dictionary:
	return DungeonRun.vitals(_data()) if _owner.has_game() else DungeonRun.full_vitals()


func _strip(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out.erase("state")
	return out
