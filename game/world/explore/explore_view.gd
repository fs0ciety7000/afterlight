class_name ExploreView
extends Node3D
## Renders one location: loads its scene, places Fern at the spawn point,
## follows her with the camera and reports exits. It never changes the game
## state itself: it emits exit_reached and the app asks GameState to travel.

signal exit_reached(to_location: String, spawn: String)
signal location_ready(location_id: String)
signal location_failed(location_id: String, reason: String)

var location_id := ""
var player: ExplorePlayer
var rig: CameraRig
var _scene: Node3D
var _exit_armed := false
var _nav_region: NavigationRegion3D


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
	location_ready.emit(id)


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
