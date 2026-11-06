extends Node
## Autoload "Content": loads every JSON file under game/data/canon and
## game/data/original, validates each entity against ContentSchemas, checks
## unique ids and cross references, and indexes entities by id.

const ROOTS := ["res://game/data/canon", "res://game/data/original"]

var errors: PackedStringArray = []
var _by_id := {}
var _by_type := {}


func _ready() -> void:
	load_all(ROOTS)


func load_all(roots: Array) -> bool:
	var r := ContentLoader.load_roots(roots)
	errors = r["errors"]
	_by_id = r["by_id"]
	_by_type = r["by_type"]
	return errors.is_empty()


## All entities by id (read-only view for the engine).
func index() -> Dictionary:
	return _by_id


## Walking speed of a character, from its base stats (GAME_BALANCE §2.1).
func move_speed(character_id: String) -> float:
	return float(get_entity(character_id).get("base_stats", {}).get("move_speed", 5.0))


func is_valid() -> bool:
	return errors.is_empty()


func get_entity(id: String) -> Dictionary:
	return _by_id.get(id, {})


func has_entity(id: String) -> bool:
	return _by_id.has(id)


func all_of(type_name: String) -> Array:
	return _by_type.get(type_name, [])


## The single start definition (type "start").
func start() -> Dictionary:
	var starts := all_of("start")
	return starts[0] if starts.size() > 0 else {}


## Display name of an entity, translated from its name_key.
func display_name(id: String) -> String:
	var e := get_entity(id)
	return tr(e.get("name_key", id)) if not e.is_empty() else id
