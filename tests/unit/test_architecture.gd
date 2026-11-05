extends TestCase
## Guards the layer rules from docs/ARCHITECTURE.md: game/engine is pure,
## deterministic logic with no scene tree, rendering, I/O or wall clock.

const ENGINE_DIR := "res://game/engine"
const FORBIDDEN := [
	"extends Node",
	"extends Control",
	"extends Resource",
	"get_tree(",
	"get_node(",
	'preload("res://game/world',
	'preload("res://game/ui',
	"randf(",
	"randi(",
	"randf_range(",
	"randi_range(",
	"randomize(",
	"Time.",
	"OS.",
	"FileAccess",
	"DirAccess",
	"Engine.",
	"JavaScriptBridge",
]


func test_engine_has_no_forbidden_dependencies() -> void:
	for path in _scripts(ENGINE_DIR):
		var source := FileAccess.get_file_as_string(path)
		for token in FORBIDDEN:
			assert_true(not source.contains(token), "%s must not use `%s`" % [path, token])


func _scripts(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out
