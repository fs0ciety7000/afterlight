extends TestCase
## Checks every location scene against the contract in docs/ARCHITECTURE.md
## ("Scènes de lieu"). Locations reachable from a new game must have a scene.


func _content() -> Dictionary:
	return ContentLoader.load_roots(["res://game/data/canon", "res://game/data/original"])


func test_locations_open_at_start_have_scenes() -> void:
	var c := _content()
	for loc in c["by_type"]["location"]:
		if loc["unlock"].get("start", false):
			assert_true(
				ResourceLoader.exists(loc["scene"]), "%s needs %s" % [loc["id"], loc["scene"]]
			)


func test_scenes_follow_the_contract() -> void:
	var c := _content()
	var spawns_of := {}
	var scenes := {}
	for loc in c["by_type"]["location"]:
		if not ResourceLoader.exists(loc["scene"]):
			continue
		var root: Node = (load(loc["scene"]) as PackedScene).instantiate()
		scenes[loc["id"]] = root
		var spawns := root.get_node_or_null("Spawns")
		assert_true(spawns != null and spawns.has_node("default"), "%s: Spawns/default" % loc["id"])
		spawns_of[loc["id"]] = (
			spawns.get_children().map(func(n: Node) -> String: return n.name) if spawns else []
		)
		assert_true(root.get_node_or_null("Exits") != null, "%s: Exits" % loc["id"])
		assert_true(
			root.find_children("*", "StaticBody3D", true, false).size() > 0,
			"%s: collisions" % loc["id"]
		)
	for id in scenes:
		var exits: Node = scenes[id].get_node_or_null("Exits")
		for area in exits.get_children() if exits else []:
			assert_true(area is Area3D, "%s: %s is an Area3D" % [id, area.name])
			var to := str(area.get_meta("to", ""))
			var spawn := str(area.get_meta("spawn", ""))
			assert_true(
				c["by_id"].has(to), "%s exit %s: unknown location '%s'" % [id, area.name, to]
			)
			if spawns_of.has(to):
				assert_true(
					spawns_of[to].has(spawn),
					"%s exit %s: no spawn '%s' in %s" % [id, area.name, spawn, to]
				)
		scenes[id].free()


func test_encounter_anchors_and_exits_are_in_place() -> void:
	# every encounter's `anchor` is a marker of its location's scene; every exit is on layer 4 with
	# a shape, and a scene reached by an exit has an exit back
	var c := _content()
	var roots := {}
	for loc in c["by_type"]["location"]:
		if ResourceLoader.exists(loc["scene"]):
			roots[loc["id"]] = (load(loc["scene"]) as PackedScene).instantiate()
	for enc in c["by_type"]["encounter"]:
		if roots.has(enc["location"]):
			assert_true(
				roots[enc["location"]].has_node("Anchors/" + str(enc["anchor"])),
				"%s: no Anchors/%s in its scene" % [enc["id"], enc["anchor"]]
			)
	for id in roots:
		for area: Area3D in roots[id].get_node("Exits").get_children():
			assert_eq(area.collision_layer, 8, "%s exit %s on layer 4" % [id, area.name])
			assert_true(
				area.find_children("*", "CollisionShape3D", false, false).size() > 0,
				"%s exit %s has a shape" % [id, area.name]
			)
			var to := str(area.get_meta("to", ""))
			if roots.has(to):
				var back: Array = roots[to].get_node("Exits").get_children().filter(
					func(n: Node) -> bool: return str(n.get_meta("to", "")) == id
				)
				assert_true(back.size() > 0, "%s has no exit back to %s" % [to, id])
	for id in roots:
		roots[id].free()


func test_lantern_mire_layout() -> void:
	var root: Node = (
		(load("res://game/world/locations/lantern_mire.tscn") as PackedScene).instantiate()
	)
	for spawn in ["default", "from_aubelin", "from_watch_ruins"]:
		assert_true(root.has_node("Spawns/" + spawn), "lantern_mire: Spawns/" + spawn)
	var exits := {}
	for area in root.get_node("Exits").get_children():
		exits[str(area.get_meta("to", ""))] = str(area.get_meta("spawn", ""))
	assert_eq(exits.get("location.aubelin", ""), "from_lantern_mire", "exit to Aubelin")
	assert_eq(exits.get("location.watch_ruins", ""), "from_lantern_mire", "exit to the Ruins")
	# docs/content/dungeon.md 4: five packs, two discoveries, a chest, three herb spots
	var packs := []
	for anchor in [
		"encounter_01",
		"encounter_02",
		"encounter_03",
		"encounter_04",
		"encounter_05",
		"discovery_01",
		"discovery_02",
		"chest_01",
		"herb_01",
		"herb_02",
		"herb_03"
	]:
		assert_true(root.has_node("Anchors/" + anchor), "lantern_mire: Anchors/" + anchor)
		if anchor.begins_with("encounter_") and root.has_node("Anchors/" + anchor):
			packs.append(root.get_node("Anchors/" + anchor))
	assert_true(
		(
			root.has_node("Anchors/encounter_04")
			and root.get_node("Anchors/encounter_04").get_meta("patrol", []).size() >= 2
		),
		"lantern_mire: encounter_04 patrols"
	)
	# packs >= 22 m apart, >= 12 m from every spawn point
	for i in packs.size():
		for j in range(i + 1, packs.size()):
			var d: float = packs[i].position.distance_to(packs[j].position)
			assert_true(d >= 22.0, "%s - %s: %.1f m" % [packs[i].name, packs[j].name, d])
		for spawn: Node3D in root.get_node("Spawns").get_children():
			var d: float = packs[i].position.distance_to(spawn.position)
			assert_true(d >= 12.0, "%s - %s: %.1f m" % [packs[i].name, spawn.name, d])
	# grass is instanced under Visuals/Grass so GraphicsQuality can thin it
	assert_true(
		root.get_node("Visuals/Grass").find_children("*", "MultiMeshInstance3D").size() > 0,
		"lantern_mire: grass MultiMeshes under Visuals/Grass"
	)
	assert_true(root.has_node("Environment/WorldEnvironment"), "lantern_mire: WorldEnvironment")
	assert_true(root.has_node("Environment/Sun"), "lantern_mire: Sun")
	root.free()
