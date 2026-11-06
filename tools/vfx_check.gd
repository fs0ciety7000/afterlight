extends SceneTree
## Validates every VFX recipe (assets/vfx/recipes/*.json): loads, inheritance, known blocks,
## beats and anchors. Usage: godot --headless --path . --script res://tools/vfx_check.gd


func _initialize() -> void:
	var errors := PackedStringArray()
	var ids := VfxRecipes.list_ids()
	for id in ids:
		errors.append_array(VfxRecipes.validate(id, Vfx.BLOCKS.keys()))
	for e in errors:
		push_error(e)
	print("VFX recipes checked: %d, %d problem(s)" % [ids.size(), errors.size()])
	quit(1 if errors.size() > 0 else 0)
