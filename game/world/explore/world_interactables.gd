class_name WorldInteractables
extends Node3D
## Things Fern can use in a place: NPCs (figure, name plate, quest marker),
## discoveries, chests and herbs, the dungeon postern, the fountain and the
## campfire. Built from entries the app gives (it reads the content API);
## this node only draws them and answers « what is near / under the cursor ».
## Missing anchors or models degrade to nothing or to a placeholder figure.
##
## Entry: {id, kind (npc, discovery, chest, herb, gate, fountain, campfire),
## anchor (Node3D), name (plate text), prompt (action text), radius (m),
## trigger (interact, interact_hold, zone), marker ("", offer, active,
## turn_in), model (res:// path or "")}.
## A rigged NPC model loops its `idle` clip (each NPC starts at its own offset
## so they don't breathe in sync) and plays `talk`, when it has one, during a
## dialogue with it (set_talking).

const PLATE_DISTANCE_M := 9.0
const MARKER_HEIGHT_M := 2.55
const NPC_HEIGHT_M := 1.7
const COLORS := {
	"offer": Color("#6b4f8f"),
	"active": Color("#b9a8d0"),
	"turn_in": Color("#c79a3c"),
}

var _entries := {}
var _nodes := {}
var _markers := {}
var _plates := {}
var _anims := {}
var _time := 0.0


func build(entries: Array) -> void:
	clear()
	for e: Dictionary in entries:
		var anchor: Node3D = e.get("anchor")
		if anchor == null or not is_instance_valid(anchor):
			continue
		var root := Node3D.new()
		root.name = "I_" + str(e["id"]).replace(".", "_")
		add_child(root)
		root.global_transform = anchor.global_transform
		_entries[e["id"]] = e
		_nodes[e["id"]] = root
		_add_visual(root, e)
		var plate := Label3D.new()
		plate.text = str(e.get("name", ""))
		plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		plate.no_depth_test = true
		plate.fixed_size = true
		plate.pixel_size = 0.0009
		plate.font_size = 22
		plate.outline_size = 8
		plate.modulate = Color("#f3ead6")
		plate.outline_modulate = Toon.INK_DAY
		plate.position = Vector3(0, NPC_HEIGHT_M + 0.35 if e["kind"] == "npc" else 1.2, 0)
		plate.visible = false
		root.add_child(plate)
		_plates[e["id"]] = plate
		set_marker(e["id"], str(e.get("marker", "")))


## Plays `talk` (if the NPC's model has it) while `on`, else back to `idle`.
func set_talking(id: String, on: bool) -> void:
	var anim := _anims.get(id) as AnimationPlayer
	if anim == null or not is_instance_valid(anim):
		return
	var clip := "talk" if on and anim.has_animation("talk") else "idle"
	if anim.current_animation != clip:
		anim.play(clip, 0.3)


## Current clip of an NPC's model ("" without a rigged model).
func clip_of(id: String) -> String:
	var anim := _anims.get(id) as AnimationPlayer
	return anim.current_animation if anim and is_instance_valid(anim) else ""


func clear() -> void:
	for id in _nodes:
		(_nodes[id] as Node).queue_free()
	_entries.clear()
	_nodes.clear()
	_markers.clear()
	_plates.clear()
	_anims.clear()


func has(id: String) -> bool:
	return _entries.has(id)


func entry(id: String) -> Dictionary:
	return _entries.get(id, {})


func ids() -> Array:
	return _entries.keys()


func remove(id: String) -> void:
	if _nodes.has(id):
		(_nodes[id] as Node).queue_free()
	_entries.erase(id)
	_nodes.erase(id)
	_markers.erase(id)
	_plates.erase(id)
	_anims.erase(id)


func position_of(id: String) -> Vector3:
	return (_nodes[id] as Node3D).global_position if _nodes.has(id) else Vector3.ZERO


## Quest marker over an NPC: offer (full diamond), active (pale), turn_in
## (gold), "" (none).
func set_marker(id: String, marker: String) -> void:
	if not _nodes.has(id):
		return
	if _markers.has(id):
		(_markers[id] as Node).queue_free()
		_markers.erase(id)
	_entries[id]["marker"] = marker
	if not COLORS.has(marker):
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.26, 0.26)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COLORS[marker]
	mi.material_override = mat
	mi.rotation = Vector3(0.0, 0.0, PI / 4.0)
	mi.scale = Vector3(1.0, 1.5, 1.0)
	mi.position = Vector3(0, MARKER_HEIGHT_M, 0)
	mi.name = "QuestMarker"
	(_nodes[id] as Node3D).add_child(mi)
	_markers[id] = mi


func marker_of(id: String) -> String:
	return str(_entries.get(id, {}).get("marker", ""))


## The closest entry Fern can use from `pos` ({} if none in reach).
func nearest(pos: Vector3, kinds: Array = []) -> Dictionary:
	var best := {}
	var best_d := INF
	for id in _entries:
		var e: Dictionary = _entries[id]
		if e.get("trigger", "") == "zone" or (not kinds.is_empty() and not kinds.has(e["kind"])):
			continue
		var d := _flat_distance(pos, position_of(id))
		if d <= float(e.get("radius", 2.5)) and d < best_d:
			best = e
			best_d = d
	return best


## Zone entries Fern stands in.
func zones_at(pos: Vector3) -> Array:
	var out := []
	for id in _entries:
		var e: Dictionary = _entries[id]
		if e.get("trigger", "") == "zone":
			if _flat_distance(pos, position_of(id)) <= float(e.get("radius", 3.0)):
				out.append(id)
	return out


## Entry under a click or tap (within `px` of its projected position).
func at_screen(cam: Camera3D, screen_pos: Vector2, px: float = 48.0) -> String:
	var best := ""
	var best_d := px
	for id in _entries:
		var p := position_of(id) + Vector3(0, 1.0, 0)
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(screen_pos)
		if d < best_d:
			best = id
			best_d = d
	return best


## Screen points of the entries (tests click them like a player).
func screen_points(cam: Camera3D) -> Dictionary:
	var out := {}
	for id in _entries:
		var p := position_of(id) + Vector3(0, 1.0, 0)
		if not cam.is_position_behind(p):
			out[id] = cam.unproject_position(p)
	return out


func _process(delta: float) -> void:
	_time += delta
	for id in _markers:
		var m := _markers[id] as Node3D
		if is_instance_valid(m):
			m.position.y = MARKER_HEIGHT_M + sin(_time * 2.0) * 0.08
			m.rotation.y = _time
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var focus := cam.global_position
	var player := get_parent().get_node_or_null("Player") as Node3D
	if player:
		focus = player.global_position
	for id in _plates:
		var plate := _plates[id] as Label3D
		if is_instance_valid(plate):
			var near := _flat_distance(focus, position_of(id)) <= PLATE_DISTANCE_M
			plate.visible = near and plate.text != ""


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


# --- Placeholders -------------------------------------------------------------


func _add_visual(root: Node3D, e: Dictionary) -> void:
	var model := str(e.get("model", ""))
	if model != "" and ResourceLoader.exists(model):
		var scene := load(model) as PackedScene
		if scene:
			var inst := scene.instantiate()
			root.add_child(inst)
			if str(e["kind"]) == "npc" and inst is Node3D:
				# NPC GLBs face +Z; anchors use the characters' -Z forward (as Fern).
				(inst as Node3D).rotation.y = PI
			Toon.apply(inst)
			_start_idle(str(e["id"]), inst)
			return
	match str(e["kind"]):
		"npc":
			_figure(root, e)
		"discovery":
			_crystal(root, Color("#e8e2f4"))
		"herb":
			_herb(root)
		"chest":
			_chest(root)
		"board":
			_board(root)


## Loops `idle` from an offset seeded by the id (stable, but not in sync).
func _start_idle(id: String, inst: Node) -> void:
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var anim := players[0] as AnimationPlayer
	if not anim.has_animation("idle"):
		return
	for clip in ["idle", "talk"]:
		if anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	var length := anim.get_animation("idle").length
	anim.seek(float(absi(hash(id)) % 1000) / 1000.0 * length, true)
	_anims[id] = anim


## A villager stand-in: robe, head and a coloured shawl (seeded by the id, so
## each NPC keeps its colours).
func _figure(root: Node3D, e: Dictionary) -> void:
	var hue := float(absi(hash(str(e["id"]))) % 360) / 360.0
	var body := _mesh(root, _capsule(0.32, 1.35), Color.from_hsv(hue, 0.35, 0.62))
	body.position.y = 0.68
	var shawl := _mesh(root, _cylinder(0.36, 0.3, 0.22), Color.from_hsv(hue, 0.5, 0.45))
	shawl.position.y = 1.18
	var head := _mesh(root, _sphere(0.2), Color("#e9c9a8"))
	head.position.y = 1.5
	Toon.apply(root)


func _crystal(root: Node3D, color: Color) -> void:
	var m := _mesh(root, _sphere(0.18), color)
	m.position.y = 1.0
	var mat := m.get_surface_override_material(0) as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6


func _herb(root: Node3D) -> void:
	for i in 3:
		var leaf := _mesh(root, _cylinder(0.0, 0.07, 0.45), Color("#9fc3e6"))
		leaf.position = Vector3(cos(i * 2.1) * 0.12, 0.22, sin(i * 2.1) * 0.12)
		leaf.rotation.z = 0.25 * (i - 1)
		var mat := leaf.get_surface_override_material(0) as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = Color("#bcd0ff")
		mat.emission_energy_multiplier = 0.35


func _chest(root: Node3D) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.55, 0.6)
	var m := _mesh(root, box, Color("#7a5634"))
	m.position.y = 0.28
	var lid := BoxMesh.new()
	lid.size = Vector3(0.95, 0.12, 0.65)
	var l := _mesh(root, lid, Color("#b39253"))
	l.position.y = 0.6
	Toon.apply(root)


func _board(root: Node3D) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 1.0, 0.12)
	var m := _mesh(root, box, Color("#8a6a45"))
	m.position.y = 1.4
	var post := _mesh(root, _cylinder(0.07, 0.07, 1.4), Color("#5e4630"))
	post.position.y = 0.7
	Toon.apply(root)


func _mesh(root: Node3D, mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.set_surface_override_material(0, mat)
	root.add_child(mi)
	return mi


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	return c


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	return c


static func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return s
