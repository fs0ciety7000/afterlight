"""Assemble a Meshy rigged character + per-clip GLBs into one game GLB for Godot.

Usage:
  blender -b --factory-startup -P tools/blender/build_character.py -- \
      --rig rigged.glb --clip idle=idle.glb --clip walk=walk.glb ... \
      --out fern.glb [--blend fern.blend] [--target-tris 22000] [--height 1.6] [--tex 2048]

What it does:
  - imports the rigged character, drops stray helper meshes (Meshy ships a 2 m "Icosphere")
  - imports each clip GLB, keeps its action under the clip name, deletes the duplicate rig/mesh
  - one NLA track per clip -> glTF NLA_TRACKS export gives one animation per clip
  - decimates (collapse, UV/weights preserved) to --target-tris
  - flattens materials to base colour only (metal 0, rough 1, no normal/ORM maps): cel shading
  - rotates the rig 180 deg so the character faces glTF -Z (Godot forward), feet at 0, height check
"""
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("--rig", required=True)
ap.add_argument("--clip", action="append", default=[])
ap.add_argument("--out", required=True)
ap.add_argument("--blend")
ap.add_argument("--target-tris", type=int, default=22000)
ap.add_argument("--height", type=float, default=1.6)
ap.add_argument("--tex", type=int, default=2048)
a = ap.parse_args(argv)
report = {}


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    return [o for o in bpy.data.objects if o not in before]


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)

new = import_glb(a.rig)
rig = next(o for o in new if o.type == "ARMATURE")
meshes = [o for o in new if o.type == "MESH" and o.parent == rig]
for o in new:
    if o.type == "MESH" and o not in meshes:
        bpy.data.objects.remove(o)  # stray helpers
rig.name = "Fern_Rig"
rig.data.name = "Fern_Rig"
body = meshes[0]
body.name = "Fern_Body"
if rig.animation_data and rig.animation_data.action:
    old = rig.animation_data.action
    rig.animation_data.action = None
    bpy.data.actions.remove(old)

# clips (the importer also pushes its own clip to an NLA track: drop those)
rig.animation_data_create()
for tr in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(tr)
clips = []
for spec in a.clip:
    name, path = spec.split("=", 1)
    objs = import_glb(path)
    src = next(o for o in objs if o.type == "ARMATURE")
    act = src.animation_data.action
    src.animation_data.action = None
    act.name = name
    act.use_fake_user = True
    for o in objs:
        bpy.data.objects.remove(o)
    tr = rig.animation_data.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(act.frame_range[0]), act)
    if act.slots:
        st.action_slot = act.slots[0]
    tr.mute = True
    clips.append((name, [round(f, 2) for f in act.frame_range]))
report["clips"] = clips
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)


def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


# decimate
t0 = tri_count(body)
report["tris_in"] = t0
if t0 > a.target_tris * 1.05:
    mod = body.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = a.target_tris / t0
    mod.use_collapse_triangulate = True
    with bpy.context.temp_override(object=body, active_object=body, selected_objects=[body]):
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
report["tris_out"] = tri_count(body)

# materials: base colour only
for slot in body.material_slots:
    m = slot.material
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    base_link = bsdf.inputs["Base Color"].links[0] if bsdf.inputs["Base Color"].links else None
    tex = base_link.from_node if base_link else None
    for n in list(nt.nodes):
        if n not in (bsdf, tex) and n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    if tex and tex.image:
        img = tex.image
        if max(img.size) > a.tex:
            img.scale(a.tex, a.tex)
        report.setdefault("textures", []).append([img.name, list(img.size)])
    m.name = "Fern_Mat"

# drop everything else (the glTF importer adds an "Icosphere" bone-shape object per import)
for o in list(bpy.data.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)
# orientation: want the face toward Blender +Y (= glTF -Z, Godot forward). Measured with the
# "headfront" bone (sits in front of the face); rotate 180 deg only if it points -Y.
hf, hd = rig.data.bones.get("headfront"), rig.data.bones.get("Head")
if hf and hd and ((rig.matrix_world @ hf.head_local) - (rig.matrix_world @ hd.head_local)).y < 0:
    # bake the turn into the rest pose: an unapplied object rotation was lost on glTF export
    rig.rotation_mode = "XYZ"  # glTF import leaves QUATERNION: rotation_euler would be ignored
    rig.rotation_euler = (0.0, 0.0, math.pi)
    bpy.context.view_layer.update()
    with bpy.context.temp_override(object=rig, active_object=rig, selected_objects=[rig, body],
                                   selected_editable_objects=[rig, body]):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
bpy.context.view_layer.update()
pts = [body.matrix_world @ v.co for v in body.data.vertices]
zmin = min(p.z for p in pts)
zmax = max(p.z for p in pts)
rig.location.z -= zmin
report["height_m"] = round(zmax - zmin, 3)
bpy.context.view_layer.update()
pts = [body.matrix_world @ v.co for v in body.data.vertices]
report["feet_z"] = round(min(p.z for p in pts), 4)
report["dims"] = [round(x, 3) for x in body.dimensions]
# nose direction check: the "headfront" bone sits in front of the face
hf = rig.data.bones.get("headfront")
hd = rig.data.bones.get("Head")
if hf and hd:
    d = (rig.matrix_world @ hf.head_local) - (rig.matrix_world @ hd.head_local)
    report["face_dir_blender"] = [round(x, 3) for x in d.normalized()]  # want +Y (= glTF -Z)

if a.blend:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.blend))

os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=os.path.abspath(a.out), export_format="GLB", use_selection=False,
    export_animation_mode="NLA_TRACKS", export_anim_slide_to_zero=True, export_force_sampling=True,
    export_skins=True, export_morph=False, export_apply=False, export_yup=True,
    export_image_format="JPEG", export_jpeg_quality=90, export_texcoords=True, export_normals=True,
    export_tangents=False, export_materials="EXPORT", export_cameras=False, export_lights=False)
report["glb_bytes"] = os.path.getsize(a.out)
print("@@REPORT@@" + json.dumps(report))

