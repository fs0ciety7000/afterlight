extends TestCase
## Every NPC's `model` (game/data/original/npcs.json) resolves to an imported
## scene: the six Aubelin villagers (assets/models/npcs) and the notice board
## (assets/models/props), built by tools/fal/npcs.sh.


func test_every_npc_model_resolves_to_a_scene() -> void:
	var r := ContentLoader.load_roots(["res://game/data/canon", "res://game/data/original"])
	var npcs: Array = r["by_type"].get("npc", [])
	assert_true(npcs.size() >= 7, "expected the 7 Aubelin NPCs, got %d" % npcs.size())
	for e in npcs:
		var path: String = e.get("model", "")
		assert_true(path != "", "%s: no model" % e["id"])
		assert_true(FileAccess.file_exists(path), "%s: missing %s" % [e["id"], path])
		assert_true(ResourceLoader.exists(path), "%s: %s not imported" % [e["id"], path])
		var scene := load(path) as PackedScene
		assert_true(scene != null, "%s: %s is not a scene" % [e["id"], path])
		if scene:
			var inst := scene.instantiate()
			var meshes := inst.find_children("*", "MeshInstance3D", true, false)
			assert_true(meshes.size() > 0, "%s: %s has no mesh" % [e["id"], path])
			inst.free()
