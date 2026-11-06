extends TestCase
## Checks every location scene against the contract in docs/ARCHITECTURE.md
## ("Scènes de lieu"). Locations reachable from a new game must have a scene. Dungeon scenes
## (dungeons.json `scene`) follow the same contract.

const CLOISTER := "res://game/world/dungeons/silent_dial_cloister.tscn"
const RUINS := "res://game/world/locations/watch_ruins.tscn"
## docs/content/dungeon.md 1: free arena disc of 34 m (ARENA_RADIUS_M 16 + 1 m) in combat rooms.
const ARENA_FREE_RADIUS_M := 17.0


func _content() -> Dictionary:
	return ContentLoader.load_roots(["res://game/data/canon", "res://game/data/original"])


func test_locations_open_at_start_have_scenes() -> void:
	var c := _content()
	for loc in c["by_type"]["location"]:
		if loc["unlock"].get("start", false):
			assert_true(
				ResourceLoader.exists(loc["scene"]), "%s needs %s" % [loc["id"], loc["scene"]]
			)


## Locations and dungeons that have a `scene` field.
func _places(c: Dictionary) -> Array:
	return c["by_type"]["location"] + c["by_type"].get("dungeon", [])


func test_scenes_follow_the_contract() -> void:
	var c := _content()
	var spawns_of := {}
	var scenes := {}
	for loc in _places(c):
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
	for loc in _places(c):
		if ResourceLoader.exists(loc["scene"]):
			roots[loc["id"]] = (load(loc["scene"]) as PackedScene).instantiate()
	# a dungeon room's encounter keeps its location (the Ruins) but is anchored in the dungeon
	var home := {}
	for d in c["by_type"].get("dungeon", []):
		for room in d["rooms"]:
			if room.has("encounter"):
				home[room["encounter"]] = d["id"]
	for enc in c["by_type"]["encounter"]:
		var place: String = home.get(enc["id"], enc["location"])
		if roots.has(place):
			assert_true(
				roots[place].has_node("Anchors/" + str(enc["anchor"])),
				"%s: no Anchors/%s in %s" % [enc["id"], enc["anchor"], place]
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


func test_npc_and_discovery_anchors_are_in_place() -> void:
	# npcs.json / discoveries.json `anchor` is a marker of the scene of their place
	var c := _content()
	var roots := {}
	for loc in _places(c):
		if ResourceLoader.exists(loc["scene"]):
			roots[loc["id"]] = (load(loc["scene"]) as PackedScene).instantiate()
	for type in ["npc", "discovery"]:
		for e in c["by_type"].get(type, []):
			var place := str(e.get("location", ""))
			if roots.has(place) and e.has("anchor"):
				assert_true(
					roots[place].has_node("Anchors/" + str(e["anchor"])),
					"%s: no Anchors/%s in %s" % [e["id"], e["anchor"], place]
				)
	for id in roots:
		roots[id].free()


func test_aubelin_npc_anchors() -> void:
	# docs/content/quests.md (NPC table) and dungeon.md 5
	var root: Node = (load("res://game/world/locations/aubelin.tscn") as PackedScene).instantiate()
	for a in [
		"npc_well",
		"npc_stall",
		"board",
		"npc_forge",
		"npc_runecarver",
		"npc_clockmaker",
		"npc_herbalist"
	]:
		assert_true(root.has_node("Anchors/" + a), "aubelin: Anchors/" + a)
	assert_true(not root.has_node("Anchors/discovery_bridge"), "aubelin: discovery_bridge renamed")
	root.free()


func _packs_apart(root: Node, place: String, packs: Array) -> void:
	# packs >= 22 m apart, >= 12 m from every spawn point (docs/content/dungeon.md 1)
	for i in packs.size():
		for j in range(i + 1, packs.size()):
			var d: float = packs[i].position.distance_to(packs[j].position)
			assert_true(d >= 22.0, "%s %s - %s: %.1f m" % [place, packs[i].name, packs[j].name, d])
		for spawn: Node3D in root.get_node("Spawns").get_children():
			var d: float = packs[i].position.distance_to(spawn.position)
			assert_true(d >= 12.0, "%s %s - %s: %.1f m" % [place, packs[i].name, spawn.name, d])


func _exit_map(root: Node) -> Dictionary:
	var exits := {}
	for area in root.get_node("Exits").get_children():
		exits[area.name] = [str(area.get_meta("to", "")), str(area.get_meta("spawn", ""))]
	return exits


func test_watch_ruins_layout() -> void:
	# docs/content/dungeon.md 3
	var root: Node = (load(RUINS) as PackedScene).instantiate()
	for spawn in ["default", "from_lantern_mire", "from_cloister"]:
		assert_true(root.has_node("Spawns/" + spawn), "watch_ruins: Spawns/" + spawn)
	var exits := _exit_map(root)
	assert_eq(exits.get("to_lantern_mire", []), ["location.lantern_mire", "from_watch_ruins"])
	assert_eq(exits.get("to_cloister", []), ["dungeon.silent_dial_cloister", "default"])
	assert_true(
		root.get_node("Exits/to_cloister").get_meta("interact", false), "postern is interactable"
	)
	var packs := []
	for anchor in [
		"encounter_01",
		"encounter_02",
		"encounter_03",
		"encounter_04",
		"encounter_05",
		"dungeon_gate",
		"discovery_01",
		"discovery_02",
		"chest_01"
	]:
		assert_true(root.has_node("Anchors/" + anchor), "watch_ruins: Anchors/" + anchor)
		if anchor.begins_with("encounter_") and root.has_node("Anchors/" + anchor):
			packs.append(root.get_node("Anchors/" + anchor))
	_packs_apart(root, "watch_ruins", packs)
	assert_true(root.has_node("Environment/WorldEnvironment"), "watch_ruins: WorldEnvironment")
	assert_true(
		root.get_node("Visuals/Grass").find_children("*", "MultiMeshInstance3D").size() > 0,
		"watch_ruins: grass MultiMeshes under Visuals/Grass"
	)
	root.free()


func test_cloister_layout() -> void:
	# docs/content/dungeon.md 2.3-2.4: one scene, seven rooms
	var root: Node = (load(CLOISTER) as PackedScene).instantiate()
	for spawn in [
		"default",
		"from_watch_ruins",
		"checkpoint_campfire",
		"shortcut_vestibule",
		"shortcut_campfire"
	]:
		assert_true(root.has_node("Spawns/" + spawn), "cloister: Spawns/" + spawn)
	var exits := _exit_map(root)
	assert_eq(exits.get("to_watch_ruins", []), ["location.watch_ruins", "from_cloister"])
	assert_eq(exits.get("to_watch_ruins_back", []), ["location.watch_ruins", "from_cloister"])
	# the bell-ringer's stair: an exit flagged as the post-boss shortcut, gated by state
	assert_eq(
		exits.get("shortcut_to_campfire", []), ["dungeon.silent_dial_cloister", "shortcut_campfire"]
	)
	assert_eq(
		exits.get("shortcut_to_vestibule", []),
		["dungeon.silent_dial_cloister", "shortcut_vestibule"]
	)
	for e in ["shortcut_to_campfire", "shortcut_to_vestibule"]:
		var area := root.get_node("Exits/" + e)
		assert_true(area.get_meta("shortcut", false), "%s flagged as shortcut" % e)
		assert_eq(area.get_meta("requires_cleared", ""), "encounter.cloister_boss", e)
	for anchor in [
		"room1_encounter",
		"room2_encounter",
		"room3_fountain",
		"room4_encounter",
		"room4_chest",
		"room5_encounter",
		"room6_campfire",
		"room7_encounter",
		"room7_lantern_a",
		"room7_lantern_b",
		"room7_lantern_c",
		"room7_lantern_d"
	]:
		assert_true(root.has_node("Anchors/" + anchor), "cloister: Anchors/" + anchor)
	var fountain := root.get_node("Anchors/room3_fountain")
	assert_eq(fountain.get_meta("interact", ""), "fountain", "fountain interactable")
	assert_near(float(fountain.get_meta("heal_pct", 0.0)), 0.3, 0.001, "fountain heals 30 %")
	var fire := root.get_node("Anchors/room6_campfire")
	assert_eq(fire.get_meta("interact", ""), "campfire", "campfire interactable")
	assert_eq(fire.get_meta("checkpoint", ""), "campfire", "campfire is the checkpoint")
	assert_eq(fire.get_meta("spawn", ""), "checkpoint_campfire", "campfire spawn")
	assert_true(root.get_node("Anchors/room7_encounter").get_meta("trigger_radius", 0.0) > 0.0)
	# room areas, in the order of dungeons.json, and the grilles the app opens
	var c := _content()
	var rooms: Array = c["by_id"]["dungeon.silent_dial_cloister"]["rooms"]
	for i in rooms.size():
		var area := root.get_node_or_null("Rooms/" + str(rooms[i]["id"]))
		assert_true(area != null, "cloister: Rooms/%s" % rooms[i]["id"])
		if area:
			assert_eq(area.get_meta("index", 0), i + 1, "room %s index" % rooms[i]["id"])
	for gate: StaticBody3D in root.get_node("Gates").get_children():
		assert_eq(gate.collision_layer, 16, "gate %s on layer 5 (not blocking)" % gate.name)
		assert_true(
			c["by_id"].has(str(gate.get_meta("opens_on", ""))),
			"gate %s opens on a known encounter" % gate.name
		)
	# night: moon light and the warm after-light kept off until Morvaine falls
	assert_true(root.has_node("Environment/Sun"), "cloister: moon")
	assert_true(
		not root.get_node("Environment/Rooms/dial/AfterLight").visible, "after-light off at first"
	)
	root.free()


func test_cloister_combat_rooms_have_a_free_arena_disc() -> void:
	# no layer-1 collider (walls, pillars, props) within 17 m of a combat room's anchor: the
	# simulation knows nothing of the decor (docs/content/dungeon.md 1)
	var root: Node = (load(CLOISTER) as PackedScene).instantiate()
	var shapes := []
	for body: CollisionObject3D in root.find_children("*", "CollisionObject3D", true, false):
		if body is Area3D or (body.collision_layer & 1) == 0:
			continue
		for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
			if not shape.shape is HeightMapShape3D:
				shapes.append(shape)
	assert_true(shapes.size() > 50, "cloister: wall colliders found (%d)" % shapes.size())
	for anchor: Node3D in root.get_node("Anchors").get_children():
		if not str(anchor.name).ends_with("_encounter"):
			continue
		var centre := anchor.position
		var nearest := INF
		var culprit := ""
		for shape: CollisionShape3D in shapes:
			var d := _horizontal_distance(_xform(shape), shape.shape, centre)
			if d < nearest:
				nearest = d
				culprit = str(root.get_path_to(shape))
		assert_true(
			nearest >= ARENA_FREE_RADIUS_M,
			"%s: %s at %.2f m (< %.0f)" % [anchor.name, culprit, nearest, ARENA_FREE_RADIUS_M]
		)
	root.free()


## Transform of a node relative to the scene root (the scene is not in the tree).
func _xform(node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n is Node3D and n.get_parent() != null:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Distance on the ground plane from `p` to a box or cylinder collider (0 if inside).
func _horizontal_distance(xf: Transform3D, shape: Shape3D, p: Vector3) -> float:
	var local := xf.affine_inverse() * p
	if shape is BoxShape3D:
		var h: Vector3 = (shape as BoxShape3D).size * 0.5
		var dx := maxf(absf(local.x) - h.x, 0.0)
		var dz := maxf(absf(local.z) - h.z, 0.0)
		return Vector2(dx, dz).length()
	if shape is CylinderShape3D:
		return maxf(Vector2(local.x, local.z).length() - (shape as CylinderShape3D).radius, 0.0)
	if shape is CapsuleShape3D:
		return maxf(Vector2(local.x, local.z).length() - (shape as CapsuleShape3D).radius, 0.0)
	# any other shape: its vertices' footprint
	var best := INF
	for v in shape.get_debug_mesh().get_faces():
		var w := xf * v
		best = minf(best, Vector2(w.x - p.x, w.z - p.z).length())
	return best
