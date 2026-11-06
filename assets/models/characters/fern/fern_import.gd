@tool
extends EditorScenePostImport
## Post-import for fern.glb: adds the secondary-motion rig every user of the model gets for free.
##
## The GLB (tools/blender/build_character_v1.py) carries secondary bones:
## - HAIR_<BL|BC|BR|FL|FR>_1..3 under Head: simulated as a whole (springy hair strands);
## - SKIRT_<0..7>_1..3 under Hips: _1 is keyed in every clip (the hem clears the legs),
##   _2.._3 are simulated so the coat and dress tails sway and lag behind.
## A SpringBoneSimulator3D named "SpringBones" is added under the Skeleton3D. The staff is a rigid
## mesh skinned to RightHand (node "Staff"): hide it with `$Fern/.../Staff.visible = false`.

const HAIR := ["HAIR_BL", "HAIR_BC", "HAIR_BR", "HAIR_FL", "HAIR_FR"]
const SKIRT_CHAINS := 8
const HAIR_STIFFNESS := 3.5
const HAIR_DRAG := 0.7
const HAIR_GRAVITY := 0.0
const SKIRT_STIFFNESS := 4.0
const SKIRT_DRAG := 0.8
const SKIRT_GRAVITY := 0.15
## Collision spheres (bone, radius) for the coat tails only: the knees keep them off the legs.
## The hair has none: its chains hang from the chest bone and stay on the back by stiffness
## (body spheres pushed the front locks sideways).
const COLLIDERS := [
	["LeftLeg", 0.085],
	["RightLeg", 0.085],
]


func _post_import(scene: Node) -> Object:
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return scene
	var skel := skeletons[0] as Skeleton3D
	# Meshy rigs keep a 0.01 scale on the armature node: bone space is in centimetres, so every
	# length handed to the simulator (radius, tail, gravity, colliders) is divided by that scale.
	var unit := 1.0
	var n: Node = skel.get_parent()
	while n:
		if n is Node3D:
			unit *= (n as Node3D).scale.x
		n = n.get_parent()
	var k := 1.0 / maxf(unit, 1e-6)
	var chains: Array[Dictionary] = []
	for h: String in HAIR:
		if skel.find_bone(h + "_1") >= 0:
			(
				chains
				. append(
					{
						"root": h + "_1",
						"end": h + "_3",
						"stiffness": HAIR_STIFFNESS,
						"drag": HAIR_DRAG,
						"gravity": HAIR_GRAVITY,
						"radius": 0.03,
						"collide": false,
					}
				)
			)
	for i in SKIRT_CHAINS:
		var base := "SKIRT_%d" % i
		if skel.find_bone(base + "_2") >= 0:
			(
				chains
				. append(
					{
						"root": base + "_2",
						"end": base + "_3",
						"stiffness": SKIRT_STIFFNESS,
						"drag": SKIRT_DRAG,
						"gravity": SKIRT_GRAVITY,
						"radius": 0.04,
						"collide": true,
					}
				)
			)
	if chains.is_empty():
		return scene
	var sim := SpringBoneSimulator3D.new()
	sim.name = "SpringBones"
	skel.add_child(sim)
	sim.owner = scene
	for c: Array in COLLIDERS:
		if skel.find_bone(c[0]) < 0:
			continue
		var col := SpringBoneCollisionSphere3D.new()
		col.name = "Collide_" + String(c[0])
		col.bone_name = c[0]
		col.radius = c[1] * k
		sim.add_child(col)
		col.owner = scene
	sim.setting_count = chains.size()
	for i in chains.size():
		var c: Dictionary = chains[i]
		sim.set_root_bone_name(i, c.root)
		sim.set_end_bone_name(i, c.end)
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_direction(i, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
		sim.set_end_bone_length(i, 0.12 * k)
		sim.set_stiffness(i, c.stiffness)
		sim.set_drag(i, c.drag)
		sim.set_gravity(i, c.gravity * k)
		sim.set_gravity_direction(i, Vector3.DOWN)
		sim.set_radius(i, c.radius * k)
		sim.set_center_from(i, SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN)
		sim.set_enable_all_child_collisions(i, c.collide)
	return scene
