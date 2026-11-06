extends SceneTree
## Loads every script under res://game so parse errors fail fast.
## Usage: godot --headless --path . --script res://tools/check_scripts.gd


func _initialize() -> void:
	var failed := 0
	for path in _scripts("res://game"):
		var s: GDScript = load(path)
		if s == null or not s.can_instantiate():
			push_error("Script failed to load: %s" % path)
			failed += 1
	print("Scripts checked, %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _scripts(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	return out
