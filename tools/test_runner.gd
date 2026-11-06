extends SceneTree
## Headless test runner.
## Usage: godot --headless --path . --script res://tools/test_runner.gd
## Discovers res://tests/unit/**/test_*.gd. Each file extends TestCase and
## defines `test_*` methods. Exits 1 if any assertion fails. Optional user
## arguments keep only the files whose name contains one of them:
## godot --headless --path . --script res://tools/test_runner.gd -- test_content

const TESTS_DIR := "res://tests/unit"

var _done := false


## Tests run on the first frame, once the autoloads (Content, GameState,
## UiProbe...) are in the tree and ready, so UI screens can be built.
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var files := _collect(TESTS_DIR)
	files.sort()
	var only := Array(OS.get_cmdline_user_args())
	if not only.is_empty():
		files = PackedStringArray(
			Array(files).filter(
				func(p: String) -> bool: return only.any(func(o: String) -> bool: return o in p)
			)
		)
	var passed := 0
	var failed := 0
	for path in files:
		var script: GDScript = load(path)
		if script == null:
			push_error("Cannot load %s" % path)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var case: TestCase = script.new()
			case.call(name)
			if case.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in case.failures:
					push_error("FAIL %s::%s: %s" % [path.get_file(), name, f])
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _collect(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_collect(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out
