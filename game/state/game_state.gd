extends Node
## Autoload "GameState": the single source of truth for the game in progress.
## Holds a plain, serializable Dictionary (see StateSchema). Nodes read it and
## request changes; they never keep their own authoritative copy.

signal changed
signal game_replaced
## Emitted after a progression action changed the state (SaveService saves
## right away, so a forge attempt or a purchase is never replayed).
signal save_requested

var data: Dictionary = {}
var dirty := false
## Where Fern stands in the current location. Not saved: a reload puts her
## back at the spawn point.
var runtime_position: Variant = null
## Inventory, forge, grimoire, runes, artifacts and shop actions.
var progression := ProgressionApi.new(self)
## Test channel only (`?test=1`, see UiProbe.test_handlers): the next won
## encounter drops at least one item, so E2E runs do not hang on the 25 %
## drop chance of a field pack.
var test_force_item_drop := false
## Test channel only: set by UiProbe when the page has `?test=1`. Without it,
## debug_clock_offset_s is ignored.
var test_channel := false
## Test channel only: seconds added to the wall clock by now_unix(), so an
## E2E run can "come back 3 h later" (`?test=1&clock_offset_s=10800`).
var debug_clock_offset_s := 0


func has_game() -> bool:
	return not data.is_empty()


## The game clock: wall time, plus the test offset on the test channel.
func now_unix() -> int:
	var now := int(Time.get_unix_time_from_system())
	return now + (debug_clock_offset_s if test_channel else 0)


## Test channel only: moves the game clock forward (or back) by `seconds`.
func test_advance_clock(seconds: int) -> void:
	if test_channel:
		debug_clock_offset_s += seconds


func start_new(start: Dictionary) -> void:
	var seed_value := randi() % 2147483647
	data = NewGame.create(start, seed_value, now_unix(), Content.index())
	runtime_position = null
	dirty = true
	game_replaced.emit()
	changed.emit()


## Adopts a validated state (from a save file or an import). A loaded save
## settles the absence first (compute_offline); an import does not, or
## importing the same file again would replay the same absence.
func adopt(state: Dictionary, settle_offline: bool = true) -> void:
	data = state
	runtime_position = null
	dirty = false
	if settle_offline:
		compute_offline()
	mark_active(now_unix())
	game_replaced.emit()
	changed.emit()
	if dirty:
		save_requested.emit()  # keep the new pending summary


## Stamps the last active time, never backwards (a clock moved back keeps the
## stored stamp, GAME_BALANCE §20.1).
func mark_active(now: int) -> void:
	if has_game():
		data["meta"]["last_active_at"] = maxi(int(data["meta"]["last_active_at"]), now)


# --- Idle (Milestone 5) -------------------------------------------------------


## The offline hunt (encounter id) or "".
func offline_hunt() -> String:
	return str(data.get("farming", "")) if has_game() else ""


## Quote of the offline hunt button: {ok, error, params, encounter,
## clear_time_s, cycle_s, efficiency, clears_per_hour, xp_per_hour,
## gold_per_hour, survives, survival_s, required_s, warning, warning_params}.
## A refusal's reason_text() is the disabled button's explanation.
func offline_hunt_quote(encounter_id: String) -> Dictionary:
	return _without_state(OfflineCalc.quote(data, encounter_id, Content.index()))


## Chooses the offline hunt. Same result as the quote; saves on success.
func set_offline_hunt(encounter_id: String) -> Dictionary:
	var r := OfflineCalc.set_hunt(data, encounter_id, Content.index())
	if r["ok"]:
		commit_action(r["state"])
	return _without_state(r)


## Settles the absence since meta.last_active_at at `now` (the game clock by
## default) and returns the pending summary. While a summary waits for its
## claim, nothing new is computed (no double credit).
func compute_offline(now: int = -1) -> Dictionary:
	if not has_game():
		return {}
	if not OfflineCalc.pending(data).is_empty():
		return pending_offline_summary()
	var r := OfflineCalc.compute(data, now_unix() if now < 0 else now, Content.index())
	data["meta"]["last_active_at"] = r["last_active_at"]
	if not r["summary"].is_empty():
		OfflineCalc.store(data, r["summary"])
		dirty = true
	return pending_offline_summary()


## The summary waiting for "Récupérer" ({} if none), with its text lines:
## OfflineCalc summary fields + lines [{key, params}] (reason_text()).
func pending_offline_summary() -> Dictionary:
	if not has_game():
		return {}
	var summary := OfflineCalc.pending(data).duplicate(true)
	if not summary.is_empty():
		summary["lines"] = OfflineCalc.lines(summary)
	return summary


## Credits the pending summary once, clears it and saves. Returns
## {ok, error, params, summary, xp, gold, materials, levels_gained, level,
## items: [uid], auto_salvaged, salvage_dust, runes, lines}.
func claim_offline() -> Dictionary:
	if not has_game():
		return ActionResult.refuse("error.offline.nothing_to_claim")
	var r := OfflineCalc.claim(data, Content.index())
	if r["ok"]:
		commit_action(r["state"])
	return _without_state(r)


## "Chasser ici" may start on this encounter: {ok, error, params}.
func hunt_here_check(encounter_id: String) -> Dictionary:
	return _without_state(HuntLoop.check(data, encounter_id, Content.index()))


## Starts "Chasser ici"; the encounter also becomes the offline hunt when it
## is eligible. {ok, error, params, encounter, offline_hunt, offline_error,
## offline_params}.
func start_hunt_here(encounter_id: String) -> Dictionary:
	var r := HuntLoop.start(data, encounter_id, Content.index())
	if r["ok"]:
		commit_action(r["state"])
	return _without_state(r)


## CombatSim setup of the next fight of the loop ({} if refused): fresh seed,
## saved party, never a first clear. Advances the "combat" counter.
func next_hunt_setup(encounter_id: String) -> Dictionary:
	var r := HuntLoop.next_fight(data, encounter_id, Content.index())
	if not r["ok"]:
		return {}
	data = r["state"]
	mark_changed()
	return r["setup"]


## Whether "Chasser ici" goes on after this encounter_completed event (it stops
## at the first defeat). Apply the result first (apply_combat_result).
func hunt_continues(completed: Dictionary) -> bool:
	return HuntLoop.continues(completed)


func _without_state(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out.erase("state")
	return out


## Moves the party to a location through WorldRules. Returns the error code
## ("" on success).
func travel(location_id: String, spawn: String) -> String:
	var r := WorldRules.travel(location_id, spawn, data, Content.index())
	if not r["ok"]:
		return r["error"]
	data = r["state"]
	runtime_position = null
	mark_changed()
	return ""


## Applies a finished encounter (CombatSim's encounter_completed event).
## Returns the summary shown on the victory screen.
func apply_combat_result(completed: Dictionary) -> Dictionary:
	if test_force_item_drop and completed.get("result", "") == "victory":
		test_force_item_drop = false
		completed = _with_test_item(completed)
	var r := CombatOutcome.apply(data, completed, Content.index())
	data = r["state"]
	mark_changed()
	return r["summary"]


## Adds one seeded item to the rewards of a won encounter that dropped none.
func _with_test_item(completed: Dictionary) -> Dictionary:
	var out := completed.duplicate(true)
	var rewards: Dictionary = out.get("rewards", {})
	if not rewards.get("items", []).is_empty():
		return out
	var counter := int(data["rng"].get("item", 0))
	var rng := SeededRng.new(SeededRng.derive_seed(int(data["meta"]["seed"]), "test_item", counter))
	var level := int(data["characters"][data["party"][0]]["level"])
	var item := ItemFactory.roll_item(rng, Content.index(), "normal", level)
	if not item.is_empty():
		rewards["items"] = [item]
	out["rewards"] = rewards
	return out


## Test channel only: adds gold and materials, then saves (E2E forge runs).
func test_grant(gold: int, materials: Dictionary) -> void:
	if not has_game():
		return
	var next := data.duplicate(true)
	next["wallet"]["gold"] = int(next["wallet"]["gold"]) + gold
	for id in materials:
		var have := int(next["wallet"]["materials"].get(id, 0))
		next["wallet"]["materials"][id] = have + int(materials[id])
	commit_action(next)


## Translated text of a refusal or summary line: tr(key) with its params,
## where "<id>.name" params are translated too ("Or insuffisant : 141 requis").
func reason_text(r: Dictionary) -> String:
	var key: String = r.get("error", r.get("key", ""))
	if key == "":
		return ""
	var params: Dictionary = r.get("params", {}).duplicate()
	for k in params:
		if typeof(params[k]) == TYPE_STRING and str(params[k]).ends_with(".name"):
			params[k] = tr(params[k])
	return tr(key).format(params)


## Adopts the state of a successful progression action (ProgressionApi),
## marks it dirty and asks for a save.
func commit_action(next_state: Dictionary) -> void:
	data = next_state
	mark_changed()
	save_requested.emit()


func location_status(location_id: String) -> String:
	return WorldRules.status(location_id, data, Content.index())


## Translated reason why a location is locked.
func lock_reason(location_id: String) -> String:
	var unlock: Dictionary = Content.get_entity(location_id).get("unlock", {})
	var r := WorldRules.reason(unlock, data, Content.index())
	var params: Dictionary = r["params"].duplicate()
	for k in params:
		if typeof(params[k]) == TYPE_STRING and str(params[k]).ends_with(".name"):
			params[k] = tr(params[k])
	return tr(r["key"]).format(params)


func clear() -> void:
	data = {}
	dirty = false
	game_replaced.emit()


func mark_changed() -> void:
	dirty = true
	changed.emit()


func _process(delta: float) -> void:
	if has_game() and not get_tree().paused:
		data["meta"]["play_time"] = float(data["meta"]["play_time"]) + delta


## Compact, display-friendly view used by screens and the test probe.
func summary() -> Dictionary:
	if not has_game():
		return {}
	var leader: String = data["party"][0]
	var hero: Dictionary = data["characters"].get(leader, {})
	return {
		"leader": leader,
		"level": hero.get("level", 0),
		"xp": hero.get("xp", 0),
		"gold": data["wallet"]["gold"],
		"region_id": data["world"]["region_id"],
		"location_id": data["world"]["location_id"],
		"play_time": int(data["meta"]["play_time"]),
		"created_at": data["meta"]["created_at"],
		"farming": data.get("farming", ""),
		"offline_pending": not OfflineCalc.pending(data).is_empty(),
	}
