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

var location_id := ""
## Encounter being fought ("" when exploring).
var engaged := ""
var player: ExplorePlayer
var rig: CameraRig
var _scene: Node3D
var _exit_armed := false
var _nav_region: NavigationRegion3D
## encounter id -> {anchor, node, radius}. Packs defeated during this visit
## are removed and come back when the place is entered again.
var _packs := {}


func load_location(id: String, spawn: String, content: Dictionary, move_speed: float) -> void:
	location_id = id
	if _scene:
		_scene.queue_free()
		_scene = null
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
		if not area.body_entered.is_connected(_on_exit_body):
			area.body_entered.connect(_on_exit_body.bind(area))
	# Exits fire only once Fern is out of the arrival area.
	_exit_armed = false
	get_tree().create_timer(0.5).timeout.connect(func() -> void: _exit_armed = true)
	_spawn_packs(id, content)
	location_ready.emit(id)


func _spawn_packs(id: String, content: Dictionary) -> void:
	_packs.clear()
	engaged = ""
	var anchors := _scene.get_node_or_null("Anchors")
	for enc_id in content.get(id, {}).get("encounters", []):
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
		_packs[enc_id] = {"anchor": anchor, "node": pack, "radius": radius * VEILED_AGGRO_MULT}


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
		out[id] = (_packs[id]["anchor"] as Node3D).global_position
	return out


func _physics_process(_delta: float) -> void:
	if player == null or engaged != "" or player.combat_driven:
		return
	for id in _packs:
		var anchor: Node3D = _packs[id]["anchor"]
		var d := player.global_position.distance_to(anchor.global_position)
		if d <= float(_packs[id]["radius"]):
			engaged = id
			player.stop()
			encounter_engaged.emit(id, anchor)
			return


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
		exit_reached.emit(str(area.get_meta("to", "")), str(area.get_meta("spawn", "default")))


## Builds a navigation mesh from the location's static collisions (calque 1),
## so click-to-move walks around houses, trees and rocks.
func _bake_navigation() -> void:
	if _nav_region:
		_nav_region.queue_free()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_radius = 0.4
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
