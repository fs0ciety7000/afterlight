class_name ExploreView
extends Node3D
## Renders one location: loads its scene, places Fern at the spawn point,
## follows her with the camera and reports exits. It never changes the game
## state itself: it emits exit_reached and the app asks GameState to travel.

signal exit_reached(to_location: String, spawn: String)
signal location_ready(location_id: String)
signal location_failed(location_id: String, reason: String)
signal encounter_engaged(encounter_id: String, anchor: Node3D)

## Exploration aggro radius multiplier from Fern's passive (GDD §6, Mana voilé).
const VEILED_AGGRO_MULT := 0.7
const PACK_RADIUS_M := 1.6
## Patrols (anchor metadata `patrol: [[x, z], ...]`, docs/content/dungeon.md
## §4.3): walking speed and the pause at each end.
const PATROL_SPEED := 1.5
const PATROL_PAUSE_S := 3.0

var location_id := ""
## Encounter being fought ("" when exploring).
var engaged := ""
var player: ExplorePlayer
var rig: CameraRig
## The exit area Fern walked into last (its metadata: shortcut, requires...).
var last_exit: Area3D
## NPCs, discoveries, postern, fountain, campfire (filled by the app).
var interactables: WorldInteractables
var _scene: Node3D
var _exit_armed := false
var _nav_region: NavigationRegion3D
## encounter id -> {anchor, node, radius}. Packs defeated during this visit
## are removed and come back when the place is entered again.
var _packs := {}


## `encounters`: the packs to show instead of the place's own list (the
## rooms of a dungeon not won yet); null keeps the place's list.
func load_location(
	id: String, spawn: String, content: Dictionary, move_speed: float, encounters: Variant = null
) -> void:
	location_id = id
	if _scene:
		_scene.queue_free()
		_scene = null
	if interactables:
		interactables.clear()
	var path: String = content.get(id, {}).get("scene", "")
	if ResourceLoader.exists(path):
		_scene = (load(path) as PackedScene).instantiate()
	elif OS.is_debug_build():
		push_warning("Location scene %s missing: using the debug greybox" % path)
		_scene = Greybox.build(id, content)
	else:
		location_failed.emit(id, "scene_missing")
		return
	add_child(_scene)
	GraphicsQuality.apply(Settings.graphics_quality, get_viewport(), _scene)
	_bake_navigation()
	if player == null:
		player = ExplorePlayer.new()
		player.name = "Player"
		add_child(player)
		rig = CameraRig.new()
		rig.name = "CameraRig"
		add_child(rig)
		rig.target = player
	player.move_speed = move_speed
	var marker := _spawn_marker(spawn)
	player.global_transform = Transform3D(
		marker.global_basis.orthonormalized(), marker.global_position
	)
	player.velocity = Vector3.ZERO
	player.stop()
	# Hair and coat springs must not swing from the old position.
	for sim in player.find_children("*", "SpringBoneSimulator3D", true, false):
		sim.call_deferred("reset")
	rig.snap()
	for area in _exits():
		area.collision_mask = 2
		# The dungeon postern opens on « interact », not by walking in.
		if area.get_meta("interact", false):
			continue
		if not area.body_entered.is_connected(_on_exit_body):
			area.body_entered.connect(_on_exit_body.bind(area))
	# Exits fire only once Fern is out of the arrival area.
	_exit_armed = false
	get_tree().create_timer(0.5).timeout.connect(func() -> void: _exit_armed = true)
	if interactables == null:
		interactables = WorldInteractables.new()
		interactables.name = "Interactables"
		add_child(interactables)
	_spawn_packs(id, content, encounters)
	location_ready.emit(id)


func _spawn_packs(id: String, content: Dictionary, encounters: Variant = null) -> void:
	for old in _packs:
		(_packs[old]["node"] as Node).queue_free()
	_packs.clear()
	engaged = ""
	var anchors := _scene.get_node_or_null("Anchors")
	var list: Array = (
		encounters if encounters is Array else content.get(id, {}).get("encounters", [])
	)
	for enc_id in list:
		var enc: Dictionary = content.get(enc_id, {})
		if anchors == null or not anchors.has_node(str(enc.get("anchor", ""))):
			continue
		var anchor: Node3D = anchors.get_node(str(enc["anchor"]))
		var pack := Node3D.new()
		pack.name = "Pack_" + str(enc["anchor"])
		add_child(pack)
		pack.global_transform = anchor.global_transform
		var radius := 0.0
		var members := []
		for group in enc["enemies"]:
			for i in int(group["count"]):
				members.append(group["enemy"])
		for i in members.size():
			var def: Dictionary = content.get(members[i], {})
			var a := CombatActor.new()
			pack.add_child(a)
			a.setup(def, "")
			var angle := TAU * i / maxf(members.size(), 1)
			a.position = Vector3(sin(angle), 0.0, cos(angle)) * PACK_RADIUS_M
			a.rotation.y = randf() * TAU
			radius = maxf(radius, float(def.get("stats_l1", {}).get("aggro_m", 8.0)))
		radius *= VEILED_AGGRO_MULT
		# The boss engages when Fern crosses the dial's circle (scene metadata).
		if anchor.has_meta("trigger_radius"):
			radius = float(anchor.get_meta("trigger_radius"))
		_packs[enc_id] = {
			"anchor": anchor,
			"node": pack,
			"radius": radius,
			"patrol": _patrol_points(anchor),
			"leg": 1,
			"wait": 0.0,
		}


## Patrol path of an encounter anchor in world space (empty: the pack stays).
func _patrol_points(anchor: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var raw: Variant = anchor.get_meta("patrol", [])
	if not raw is Array:
		return out
	for p: Variant in raw:
		if p is Array and (p as Array).size() >= 2:
			out.append(Vector3(float(p[0]), anchor.global_position.y, float(p[1])))
		elif p is Vector2:
			out.append(Vector3((p as Vector2).x, anchor.global_position.y, (p as Vector2).y))
	if out.size() < 2:
		out.clear()
	return out


## Moves the patrolling packs along their path while nobody fights them.
func _move_patrols(delta: float) -> void:
	for id in _packs:
		var pack: Dictionary = _packs[id]
		var points: Array[Vector3] = pack["patrol"]
		if points.is_empty() or id == engaged:
			continue
		if float(pack["wait"]) > 0.0:
			pack["wait"] = float(pack["wait"]) - delta
			continue
		var node := pack["node"] as Node3D
		var target: Vector3 = points[int(pack["leg"])]
		target.y = node.global_position.y
		var to := target - node.global_position
		var step := PATROL_SPEED * delta
		if to.length() <= step:
			node.global_position = target
			pack["wait"] = PATROL_PAUSE_S
			pack["leg"] = (int(pack["leg"]) + 1) % points.size()
		else:
			node.global_position += to.normalized() * step
			node.rotation.y = atan2(to.x, to.z)


## Where a pack stands now (its anchor, or along its patrol).
func pack_node(encounter_id: String) -> Node3D:
	return _packs[encounter_id]["node"] if _packs.has(encounter_id) else null


## Removes a pack once its encounter is won (it returns on the next visit).
func clear_pack(encounter_id: String) -> void:
	if _packs.has(encounter_id):
		(_packs[encounter_id]["node"] as Node).queue_free()
		_packs.erase(encounter_id)


## Hides an engaged pack while the combat view shows the fight.
func hide_pack(encounter_id: String) -> void:
	if _packs.has(encounter_id):
		(_packs[encounter_id]["node"] as Node3D).visible = false


func show_pack(encounter_id: String) -> void:
	if _packs.has(encounter_id):
		(_packs[encounter_id]["node"] as Node3D).visible = true


func pack_positions() -> Dictionary:
	var out := {}
	for id in _packs:
		out[id] = (_packs[id]["node"] as Node3D).global_position
	return out


func _physics_process(delta: float) -> void:
	if player == null or player.combat_driven:
		return
	if engaged != "":
		return
	_move_patrols(delta)
	for id in _packs:
		var anchor: Node3D = _packs[id]["anchor"]
		# A patrolling pack is fought where it walks, not at its anchor.
		var at: Node3D = _packs[id]["node"] if not _packs[id]["patrol"].is_empty() else anchor
		var d := player.global_position.distance_to(at.global_position)
		if d <= float(_packs[id]["radius"]):
			engaged = id
			player.stop()
			encounter_engaged.emit(id, at)
			return


## Puts Fern at a spawn point of the current scene (dungeon shortcut, room
## pushed back). False when the scene has no such point.
func place_at(spawn: String) -> bool:
	var spawns := _scene.get_node_or_null("Spawns") if _scene else null
	if spawns == null or not spawns.has_node(spawn):
		return false
	var marker: Node3D = spawns.get_node(spawn)
	teleport(marker.global_position, marker.global_basis)
	return true


func teleport(at: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	player.global_transform = Transform3D(basis.orthonormalized(), at)
	player.velocity = Vector3.ZERO
	player.stop()
	rig.snap()


## An anchor of the current scene by name (null if missing).
func anchor(anchor_name: String) -> Node3D:
	var anchors := _scene.get_node_or_null("Anchors") if _scene else null
	if anchors == null or not anchors.has_node(anchor_name):
		return null
	return anchors.get_node(anchor_name) as Node3D


## A node of the current scene by path (null if missing): Rooms, Gates...
func scene_node(path: String) -> Node:
	return _scene.get_node_or_null(path) if _scene else null


## Anchors of the current scene ([] if none).
func anchors() -> Array:
	var node := _scene.get_node_or_null("Anchors") if _scene else null
	return node.get_children() if node else []


## Exits used with « interact » (the dungeon postern): [Area3D].
func interact_exits() -> Array:
	return _exits().filter(func(a: Area3D) -> bool: return a.get_meta("interact", false))


func _spawn_marker(spawn: String) -> Node3D:
	var spawns := _scene.get_node_or_null("Spawns")
	if spawns and spawns.has_node(spawn):
		return spawns.get_node(spawn)
	if spawns and spawns.has_node("default"):
		return spawns.get_node("default")
	return _scene


func _exits() -> Array:
	var exits := _scene.get_node_or_null("Exits") if _scene else null
	if exits == null:
		return []
	return exits.get_children().filter(func(n: Node) -> bool: return n is Area3D)


func _on_exit_body(body: Node3D, area: Area3D) -> void:
	if body == player and _exit_armed:
		_exit_armed = false
		last_exit = area
		exit_reached.emit(str(area.get_meta("to", "")), str(area.get_meta("spawn", "default")))
		# Re-armed shortly so a refused exit (locked grille) works again.
		get_tree().create_timer(1.0).timeout.connect(func() -> void: _exit_armed = true)


## Builds a navigation mesh from the location's static collisions (calque 1),
## so click-to-move walks around houses, trees and rocks.
func _bake_navigation() -> void:
	if _nav_region:
		_nav_region.queue_free()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.6
	mesh.agent_max_climb = 0.4
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.1
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, _scene)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "Navigation"
	_nav_region.navigation_mesh = mesh
	_nav_region.navigation_layers = 1
	add_child(_nav_region)
	# Make sure the map uses the new region before the first path request.
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)


func path_to(target: Vector3) -> PackedVector3Array:
	var map := get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, player.global_position)
	var to := NavigationServer3D.map_get_closest_point(map, target)
	return NavigationServer3D.map_get_path(map, from, to, true)


## Ground point under a screen position, or null.
func ground_point(screen_point: Vector2) -> Variant:
	var cam := rig.camera
	var from := cam.project_ray_origin(screen_point)
	var dir := cam.project_ray_normal(screen_point)
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, 1)
	)
	if not hit.is_empty():
		return hit["position"]
	return Plane(Vector3.UP, player.global_position.y).intersects_ray(from, dir)


## Click or tap on the ground: walk there, around obstacles.
func click_to_move(screen_point: Vector2) -> bool:
	if rig == null:
		return false
	var cam := rig.camera
	var from := cam.project_ray_origin(screen_point)
	var dir := cam.project_ray_normal(screen_point)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var point: Variant = hit["position"] if not hit.is_empty() else null
	if point == null:
		point = Plane(Vector3.UP, player.global_position.y).intersects_ray(from, dir)
	if point == null:
		return false
	var path := path_to(point)
	if path.size() > 1:
		player.follow_path(path)
	else:
		player.move_to(point)
	return true


## Screen positions of exits (for tests), keyed by target location.
func exit_screen_points() -> Dictionary:
	var out := {}
	for area in _exits():
		if not rig.camera.is_position_behind(area.global_position):
			out[str(area.get_meta("to", ""))] = rig.camera.unproject_position(area.global_position)
	return out
