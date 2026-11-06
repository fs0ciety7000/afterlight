class_name Greybox
extends RefCounted
## Debug-only stand-in for a location scene that is not built yet. It follows
## the location scene contract (docs/ARCHITECTURE.md) so the exploration code
## can be exercised. Exported release builds never use it.


static func build(location_id: String, content: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Greybox"
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	root.add_child(spawns)
	var exits := Node3D.new()
	exits.name = "Exits"
	root.add_child(exits)
	var walkable := StaticBody3D.new()
	walkable.name = "Walkable"
	root.add_child(walkable)
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	ground_shape.shape = box
	ground_shape.position.y = -0.5
	walkable.add_child(ground_shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#b9c48a")
	ground.material_override = mat
	root.add_child(ground)
	_marker(spawns, "default", Vector3.ZERO)
	var neighbours := _neighbours(location_id, content)
	for i in neighbours.size():
		var angle := TAU * i / maxf(neighbours.size(), 1)
		var at := Vector3(sin(angle), 0, -cos(angle)) * 22.0
		var short: String = (neighbours[i] as String).get_slice(".", 1)
		_marker(spawns, "from_" + short, at * 0.8)
		var area := Area3D.new()
		area.name = "to_" + short
		area.collision_layer = 8
		area.collision_mask = 2
		area.position = at
		area.set_meta("to", neighbours[i])
		area.set_meta("spawn", "from_" + location_id.get_slice(".", 1))
		var shape := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = Vector3(3, 2, 3)
		shape.shape = s
		area.add_child(shape)
		exits.add_child(area)
		var post := MeshInstance3D.new()
		post.mesh = BoxMesh.new()
		post.position = at + Vector3(0, 0.5, 0)
		root.add_child(post)
	var world := WorldEnvironment.new()
	world.name = "Environment"
	var look := Environment.new()
	look.background_mode = Environment.BG_COLOR
	look.background_color = Color("#cfd8e6")
	look.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color = Color("#d8d0c0")
	world.environment = look
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color("#ffe2b0")
	world.add_child(sun)
	return root


static func _neighbours(location_id: String, content: Dictionary) -> Array:
	var out := []
	var region: String = content.get(location_id, {}).get("region", "")
	for id in content:
		var e: Dictionary = content[id]
		if e.get("_type") == "location" and e["region"] == region and id != location_id:
			out.append(id)
	out.sort()
	return out


static func _marker(parent: Node, marker_name: String, at: Vector3) -> void:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = at
	parent.add_child(m)
