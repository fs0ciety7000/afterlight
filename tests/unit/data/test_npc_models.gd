extends TestCase
## Every NPC's `model` (game/data/original/npcs.json) resolves to an imported
## scene: the six Aubelin villagers (assets/models/npcs) and the notice board
## (assets/models/props), built by tools/fal/npcs.sh (rigged by tools/fal/npcs_rig.sh).
## Lot 2: every villager is rigged with a looping `idle`; Odile and Maëlle also
## `talk` during their dialogues.

const VILLAGERS := ["odile", "bastien", "maelle", "rosalie", "tobias", "ysaline"]
const TALKERS := ["odile", "maelle"]


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


func test_every_villager_model_has_an_idle_clip() -> void:
	for n: String in VILLAGERS:
		var path := "res://assets/models/npcs/%s.glb" % n
		var inst := (load(path) as PackedScene).instantiate()
		var players := inst.find_children("*", "AnimationPlayer", true, false)
		assert_true(not players.is_empty(), "%s: no AnimationPlayer" % n)
		if not players.is_empty():
			var anim := players[0] as AnimationPlayer
			assert_true(anim.has_animation("idle"), "%s: no idle clip" % n)
			if n in TALKERS:
				assert_true(anim.has_animation("talk"), "%s: no talk clip" % n)
		inst.free()


func test_interactables_loop_idle_and_talk_in_dialogue() -> void:
	var world := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	var anchor := Marker3D.new()
	world.add_child(anchor)
	var items := WorldInteractables.new()
	world.add_child(items)
	var npc := {"kind": "npc", "anchor": anchor, "name": "", "radius": 3.0, "trigger": "interact"}
	var odile := npc.duplicate()
	odile.merge({"id": "npc.odile", "model": "res://assets/models/npcs/odile.glb"})
	var tobias := npc.duplicate()
	tobias.merge({"id": "npc.tobias", "model": "res://assets/models/npcs/tobias.glb"})
	var stand_in := npc.duplicate()
	stand_in.merge({"id": "npc.none", "model": ""})
	items.build([odile, tobias, stand_in])
	assert_eq(items.clip_of("npc.odile"), "idle", "idle plays")
	items.set_talking("npc.odile", true)
	assert_eq(items.clip_of("npc.odile"), "talk", "talk in dialogue")
	items.set_talking("npc.odile", false)
	assert_eq(items.clip_of("npc.odile"), "idle", "back to idle")
	items.set_talking("npc.tobias", true)
	assert_eq(items.clip_of("npc.tobias"), "idle", "no talk clip: keeps idle")
	items.set_talking("npc.none", true)
	assert_eq(items.clip_of("npc.none"), "", "placeholder figure: no clip")
	world.get_parent().remove_child(world)
	world.free()
