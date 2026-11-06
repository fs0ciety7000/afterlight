extends Node
## Autoload "GameState": the single source of truth for the game in progress.
## Holds a plain, serializable Dictionary (see StateSchema). Nodes read it and
## request changes; they never keep their own authoritative copy.

signal changed
signal game_replaced

var data: Dictionary = {}
var dirty := false
## Where Fern stands in the current location. Not saved: a reload puts her
## back at the spawn point.
var runtime_position: Variant = null


func has_game() -> bool:
	return not data.is_empty()


func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


func start_new(start: Dictionary) -> void:
	var seed_value := randi() % 2147483647
	data = NewGame.create(start, seed_value, now_unix(), Content.index())
	runtime_position = null
	dirty = true
	game_replaced.emit()
	changed.emit()


## Adopts a validated state (from a save file or an import).
func adopt(state: Dictionary) -> void:
	data = state
	data["meta"]["last_active_at"] = now_unix()
	runtime_position = null
	dirty = false
	game_replaced.emit()
	changed.emit()


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
	var r := CombatOutcome.apply(data, completed)
	data = r["state"]
	mark_changed()
	return r["summary"]


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
	}
