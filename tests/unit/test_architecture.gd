extends TestCase
## Guards the layer rules from docs/ARCHITECTURE.md: game/engine is pure,
## deterministic logic with no scene tree, rendering, I/O or wall clock.

const ENGINE_DIR := "res://game/engine"
## Regexes; `(?<![\w.])` means "a global call", not a method on an object.
const FORBIDDEN := [
	"extends\\s+(Node|Node2D|Node3D|Control|Resource)\\b",
	"(?<![\\w.])get_tree\\(",
	"(?<![\\w.])get_node\\(",
	"(?<![\\w.])(randf|randi|randf_range|randi_range|randomize|randfn)\\(",
	"\\b(Time|OS|FileAccess|DirAccess|Engine|JavaScriptBridge|ResourceLoader|Input)\\.",
	'preload\\("res://game/(app|ui|state|world|combat|persistence)',
	'load\\("res://game/(app|ui|state|world|combat|persistence)',
]


func test_engine_has_no_forbidden_dependencies() -> void:
	var patterns := []
	for source in FORBIDDEN:
		patterns.append(RegEx.create_from_string(source))
	for path in _scripts(ENGINE_DIR):
		var text := FileAccess.get_file_as_string(path)
		for re: RegEx in patterns:
			var hit := re.search(text)
			assert_true(
				hit == null, "%s must not use `%s`" % [path, hit.get_string() if hit else ""]
			)


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
