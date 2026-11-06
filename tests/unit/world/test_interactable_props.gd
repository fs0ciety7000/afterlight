extends TestCase
## Chests, herbs and discoveries use the hand-built props
## (tools/blender/build_interactable_props.py); a taken chest stays in place with
## its lid open but can no longer be used.


func _entry(id: String, kind: String, anchor: Node3D) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"anchor": anchor,
		"name": "",
		"prompt": "",
		"radius": 2.5,
		"trigger": "interact",
		"marker": "",
		"model": "",
	}


func test_props_are_drawn_and_a_taken_chest_stays_open() -> void:
	var world := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	var anchor := Marker3D.new()
	world.add_child(anchor)
	var items := WorldInteractables.new()
	world.add_child(items)
	var opened := _entry("discovery.old_chest", "chest", anchor)
	opened["opened"] = true
	(
		items
		. build(
			[
				_entry("discovery.chest", "chest", anchor),
				_entry("discovery.herb", "herb", anchor),
				_entry("discovery.lore", "discovery", anchor),
				opened,
			]
		)
	)
	for id in ["discovery.chest", "discovery.herb", "discovery.lore"]:
		var root := items.get_node("I_" + id.replace(".", "_"))
		assert_true(root.has_node("Prop"), "%s uses its GLB" % id)
	var lid := items.get_node("I_discovery_chest").find_child("ChestLid", true, false) as Node3D
	assert_true(lid != null, "chest has a lid node")
	assert_near(lid.rotation.x, 0.0, 0.01, "closed before it is taken")
	var old_lid := (
		items.get_node("I_discovery_old_chest").find_child("ChestLid", true, false) as Node3D
	)
	assert_near(old_lid.rotation.x, WorldInteractables.LID_OPEN_RAD, 0.01, "opened entry")
	items.remove("discovery.chest")
	assert_true(not items.has("discovery.chest"), "taken chest no longer usable")
	assert_true(items.has_node("I_discovery_chest"), "taken chest stays as decor")
	assert_true(
		items.nearest(anchor.global_position, ["chest"]).get("id", "") != "discovery.chest",
		"no reach"
	)
	items.remove("discovery.herb")
	assert_true(
		(
			not items.has_node("I_discovery_herb")
			or items.get_node("I_discovery_herb").is_queued_for_deletion()
		),
		"herb gone"
	)
	world.get_parent().remove_child(world)
	world.free()
