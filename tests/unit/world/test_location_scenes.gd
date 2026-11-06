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
