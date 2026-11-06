"""Rigged Aubelin NPC from a Meshy rigging/multi-animation result (lot 2): rig + clips, flat albedo, GLB.

  blender -b --factory-startup -P tools/blender/build_npc_rigged.py -- odile --rig odile_rig_0.glb \
      --clip idle=odile_rig_8.glb --clip talk=odile_rig_10.glb[:first:last] --albedo flat.png \
      [--loop idle,talk] [--freeze LeftShoulder,LeftArm,...] [--arm-gap 0.14] [--out assets/models/npcs/odile.glb]

The rig input is the static NPC GLB of lot 1 (tools/blender/build_npcs.py: ~12 k tris, feet at the origin,
facing glTF +Z), so Meshy returns the same mesh, skinned to its 24-bone humanoid, in that rest pose.
- the rig, its mesh and one action per clip are kept (Meshy's Icosphere helper and stray actions go);
- arm weights below the armpit fade out with the sideways distance to the spine (--arm-gap): Meshy's skin
  hangs the apron and shawl on the hands; --freeze keeps an arm modelled bent around a prop in its pose;
- clips can be trimmed (`name=path:first:last`); looped clips get their last 4 keys eased to the first pose;
- the flat albedo material of lot 1 is put back (same names, WebP), toon is applied at run time (Toon.apply);
- the model must still face glTF +Z (Blender -Y): checked from the Head -> headfront bone, turned if not;
- feet at z = 0 in the rest pose; export GLB with one animation per clip (NLA tracks), 4 influences.
Prints @@REPORT@@ json.
"""
import argparse
import json
import math
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("npc")
ap.add_argument("--rig", required=True)
ap.add_argument("--clip", action="append", default=[], help="name=path[:first:last]")
ap.add_argument("--albedo", required=True)
ap.add_argument("--loop", default="idle,talk")
ap.add_argument("--out")
ap.add_argument("--freeze", default="", help="bones kept in their rest pose in every clip (an arm modelled "
                "bent around a prop: Meshy's clips assume a hanging arm and would push the hand into the body)")
ap.add_argument("--arm-gap", type=float, default=0.14, help="m; 0 keeps Meshy's arm weights as they are")
a =ap.parse_args(argv)
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
report = {"npc": a.npc}
LOOP_BLEND = 4


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    return [o for o in bpy.data.objects if o not in before]


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
new = import_glb(a.rig)
rig = next(o for o in new if o.type == "ARMATURE")
body = next(o for o in new if o.type == "MESH" and o.parent == rig)
for o in new:
    if o not in (rig, body):
        bpy.data.objects.remove(o)
rig.name = rig.data.name = f"{a.npc}_Rig"
body.name = body.data.name = a.npc
rig.animation_data_create()
rig.animation_data.action = None
for tr in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(tr)
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)


def fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                yield from cb.fcurves


clips = {}
for spec in a.clip:
    name, rest = spec.split("=", 1)
    parts = rest.split(":")
    objs = import_glb(parts[0])
    src = next(o for o in objs if o.type == "ARMATURE")
    act = src.animation_data.action
    src.animation_data.action = None
    for o in objs:
        bpy.data.objects.remove(o)
    act.name = name
    act.use_fake_user = True
    if len(parts) == 3:  # trim and shift so the clip starts at frame 1
        f0, f1 = float(parts[1]), float(parts[2])
        for fc in fcurves(act):
            kps = fc.keyframe_points
            for i in range(len(kps) - 1, -1, -1):
                if kps[i].co.x < f0 - 1e-3 or kps[i].co.x > f1 + 1e-3:
                    kps.remove(kps[i])
            for kp in kps:
                kp.co.x -= f0 - 1
                kp.handle_left.x -= f0 - 1
                kp.handle_right.x -= f0 - 1
            fc.update()
    clips[name] = act
for act in list(bpy.data.actions):
    if act not in clips.values():
        bpy.data.actions.remove(act)
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

# frozen bones: drop their channels from every clip (they stay in the modelled rest pose)
frozen = [f'pose.bones["{b}"]' for b in filter(None, a.freeze.split(","))]
if frozen:
    for act in clips.values():
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in [fc for fc in cb.fcurves if fc.data_path.startswith(tuple(frozen))]:
                        cb.fcurves.remove(fc)
    report["frozen"] = a.freeze

# arm weights: Meshy's auto-skin spreads hand / forearm weights over the apron and the shawl front (arms
# hang close to the body), which tears the cloth when an arm moves. Below the armpit, arm-chain weights fade
# out between --arm-gap and --arm-gap + 6 cm of sideways distance from the spine (the arms hang at the sides);
# what is taken goes to the spine bone at that height. Shoulders, neck and head keep Meshy's weights.
# (a frozen arm is skipped: it follows the chest rigidly, so its hand and the cloth around it stay together)
ARM = [f"{s}{b}" for s in ("Left", "Right") for b in ("Arm", "ForeArm", "Hand")
       if f"{s}{b}" not in a.freeze.split(",")]
TORSO = ("Spine01", "Spine02", "Hips")


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


if a.arm_gap > 0:
    bpy.context.view_layer.update()
    bw = {b.name: rig.matrix_world @ b.head_local for b in rig.data.bones}
    axis_x = (bw["Hips"].x + bw["Spine"].x) / 2
    armpit = min(bw["LeftArm"].z, bw["RightArm"].z) - 0.10
    vg = {g.name: g for g in body.vertex_groups}
    for t in TORSO:
        vg.setdefault(t, body.vertex_groups.new(name=t))
    idx = {g.index: g.name for g in body.vertex_groups}
    moved = 0
    for v in body.data.vertices:
        p = body.matrix_world @ v.co
        if p.z > armpit:
            continue
        k = smoothstep(a.arm_gap, a.arm_gap + 0.06, abs(p.x - axis_x))
        if k >= 1.0:
            continue
        take = 0.0
        for g in list(v.groups):
            if idx[g.group] in ARM and g.weight > 0:
                take += g.weight * (1 - k)
                vg[idx[g.group]].add([v.index], g.weight * k, "REPLACE")
        if take > 1e-4:
            dst_bone = "Spine01" if p.z >= bw["Spine01"].z else ("Spine02" if p.z >= bw["Spine02"].z else "Hips")
            vg[dst_bone].add([v.index], take, "ADD")
            moved += 1
    report["arm_weights_moved_verts"] = moved

# seamless loops: ease the last keys toward the first pose; the pop left is reported (deg / cm)
for name in filter(None, a.loop.split(",")):
    act = clips.get(name)
    if not act:
        continue
    for fc in fcurves(act):
        kps = fc.keyframe_points
        if len(kps) < LOOP_BLEND + 2:
            continue
        first = kps[0].co.y
        n = len(kps)
        for k in range(LOOP_BLEND):
            i = n - LOOP_BLEND + k
            t = (k + 1) / LOOP_BLEND
            kps[i].co.y = kps[i].co.y * (1 - t) + first * t
        fc.update()
    report.setdefault("looped", []).append(name)

# flat albedo material (same names as lot 1: Godot extracts <npc>_<npc>_albedo.webp)
img = bpy.data.images.load(os.path.abspath(a.albedo))
img.name = f"{a.npc}_albedo"
mat = bpy.data.materials.new(f"{a.npc}_flat")
nt = mat.node_tree
bsdf = next(nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED")
bsdf.inputs["Roughness"].default_value = 1.0
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Specular IOR Level"].default_value = 0.0
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
body.data.materials.clear()
body.data.materials.append(mat)
while len(body.data.uv_layers) > 1:
    body.data.uv_layers.remove(body.data.uv_layers[-1])
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

# facing: glTF +Z = Blender -Y
bones = rig.data.bones
bpy.context.view_layer.update()
face = (rig.matrix_world @ bones["headfront"].head_local) - (rig.matrix_world @ bones["Head"].head_local)
if face.y > 0:
    rig.rotation_mode = "XYZ"
    rig.rotation_euler.z += math.pi
    bpy.context.view_layer.update()
    sel = [rig, body]
    with bpy.context.temp_override(object=rig, active_object=rig, selected_objects=sel,
                                   selected_editable_objects=sel):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    report["turned"] = True
bpy.context.view_layer.update()
pts = [body.matrix_world @ v.co for v in body.data.vertices]
rig.location.z -= min(p.z for p in pts)
bpy.context.view_layer.update()
pts = [body.matrix_world @ v.co for v in body.data.vertices]
face = (rig.matrix_world @ bones["headfront"].head_local) - (rig.matrix_world @ bones["Head"].head_local)
report["face_dir_blender"] = [round(x, 3) for x in face.normalized()]
report["size_m"] = [round(max(p[i] for p in pts) - min(p[i] for p in pts), 2) for i in range(3)]
report["feet_z"] = round(min(p.z for p in pts), 4)
body.data.calc_loop_triangles()
report["tris"] = len(body.data.loop_triangles)
report["bones"] = len(bones)

for name, act in clips.items():
    tr = rig.animation_data.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(act.frame_range[0]), act)
    if act.slots:
        st.action_slot = act.slots[0]
    tr.mute = True
report["clips"] = {n: [round(x, 1) for x in act.frame_range] for n, act in clips.items()}

dst = os.path.abspath(a.out or os.path.join(ROOT, "assets", "models", "npcs", f"{a.npc}.glb"))
os.makedirs(os.path.dirname(dst), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=dst, export_format="GLB", use_selection=False,
    export_animation_mode="NLA_TRACKS", export_anim_slide_to_zero=True, export_force_sampling=True,
    export_optimize_animation_size=True, export_skins=True, export_influence_nb=4, export_morph=False,
    export_apply=False, export_yup=True, export_image_format="WEBP", export_image_quality=88,
    export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
    export_cameras=False, export_lights=False, export_def_bones=False)
report["glb_kb"] = round(os.path.getsize(dst) / 1024)
print("@@REPORT@@" + json.dumps(report))
