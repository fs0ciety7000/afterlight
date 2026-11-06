class_name HuntLoop
extends RefCounted
## Engine side of "Chasser ici" (GDD §12, ROADMAP 5.8): the encounter is
## replayed in real time in the scene, each victory gives its loot through
## CombatOutcome, a defeat stops the loop. The real-time loop belongs to the
## app; these helpers keep its rules pure and testable.


## Can the party hunt `encounter_id` here? Only an encounter already won
## (elites and bosses included: only the offline hunt excludes them), never a
## normal dungeon room (docs/content/dungeon.md §2.2: an expedition).
static func check(state: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var e: Dictionary = content.get(encounter_id, {})
	if e.get("_type", "") != "encounter":
		return ActionResult.refuse("error.hunt.unknown_encounter")
	if e["kind"] == "normal" and _in_dungeon(encounter_id, content):
		return ActionResult.refuse("error.hunt.dungeon_room")
	if int(state["progress"]["cleared_encounters"].get(encounter_id, 0)) <= 0:
		return ActionResult.refuse("error.hunt.not_cleared", {"encounter": e["name_key"]})
	return ActionResult.success({})


static func _in_dungeon(encounter_id: String, content: Dictionary) -> bool:
	for id in content:
		if content[id].get("_type", "") == "dungeon":
			for room in content[id]["rooms"]:
				if room.get("encounter", "") == encounter_id:
					return true
	return false


## Starts hunting here. The encounter also becomes the offline hunt when
## OfflineCalc accepts it (GDD §4: the last "Chasser ici" is the offline
## hunt). Result extra: {encounter, offline_hunt (bool), offline_error,
## offline_params}.
static func start(state: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var r := check(state, encounter_id, content)
	if not r["ok"]:
		return r
	var offline := OfflineCalc.set_hunt(state, encounter_id, content)
	var next: Dictionary = offline["state"] if offline["ok"] else state.duplicate(true)
	var extra := {
		"encounter": encounter_id,
		"offline_hunt": offline["ok"],
		"offline_error": offline["error"],
		"offline_params": offline["params"],
	}
	return ActionResult.success(next, extra)


## Setup of the next fight of the loop: the saved party, a fresh seed from the
## persistent "combat" counter (so no two iterations, or two sessions, replay
## the same fight) and never a first clear. Result extra: {setup} where setup
## is ready for CombatSim.create; the state has its counter advanced.
static func next_fight(state: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var r := check(state, encounter_id, content)
	if not r["ok"]:
		return r
	var next := state.duplicate(true)
	var counter := int(next["rng"].get("combat", 0))
	next["rng"]["combat"] = counter + 1
	var setup := PartyBuild.setup(next, content)
	setup["encounter"] = encounter_id
	setup["seed"] = fight_seed(int(next["meta"]["seed"]), counter)
	setup["first_clear"] = false
	return ActionResult.success(next, {"setup": setup})


## Same derivation as a field fight (explore screen): "combat" stream.
static func fight_seed(game_seed: int, counter: int) -> int:
	return absi(SeededRng.derive_seed(game_seed, "combat", counter))


## Whether the loop goes on after a fight (encounter_completed event).
static func continues(completed: Dictionary) -> bool:
	return completed.get("result", "") == "victory"
