extends Node
## Autoload "GameState": the single source of truth for the game in progress.
## Holds a plain, serializable Dictionary (see StateSchema). Nodes read it and
## request changes; they never keep their own authoritative copy.

signal changed
signal game_replaced

var data: Dictionary = {}
var dirty := false


func has_game() -> bool:
	return not data.is_empty()


func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


func start_new(start: Dictionary) -> void:
	var seed_value := randi() % 2147483647
	data = NewGame.create(start, seed_value, now_unix())
	dirty = true
	game_replaced.emit()
	changed.emit()


## Adopts a validated state (from a save file or an import).
func adopt(state: Dictionary) -> void:
	data = state
	data["meta"]["last_active_at"] = now_unix()
	dirty = false
	game_replaced.emit()
	changed.emit()


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
