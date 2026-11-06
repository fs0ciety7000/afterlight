"""Render a textured QA turnaround (front / side / back / 3-4 top) of a GLB, Workbench (headless-safe).

Usage:
  blender -b --factory-startup -P tools/blender/render_turnaround.py -- in.glb out_dir [--front +Y] [--frame N --clip name]
Writes out_dir/qa_<view>.png; compose with tools/blender/compose_sheet.py (system python, PIL).
--front: Blender axis the character faces (+Y when exported for Godot -Z forward).
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("out_dir")
ap.add_argument("--front", default="+Y")
ap.add_argument("--clip")
ap.add_argument("--frame", type=float, default=0)
ap.add_argument("--res", type=int, default=900)
a = ap.parse_args(argv)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(a.src))
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name.startswith("Icosphere"):  # importer bone-shape helper
        bpy.data.objects.remove(o)
sc = bpy.context.scene
rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if rig and rig.animation_data:
    if a.clip:
        act = bpy.data.actions.get(a.clip) or next(x for x in bpy.data.actions if a.clip in x.name)
        rig.animation_data.action = act
        if act.slots:
            rig.animation_data.action_slot = act.slots[0]
    else:
        rig.animation_data.action = None
        for pb in rig.pose.bones:
            pb.matrix_basis.identity()
sc.frame_set(int(a.frame))
bpy.context.view_layer.update()

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for o in meshes:
    e = o.evaluated_get(dg)
    m = e.to_mesh()
    pts += [e.matrix_world @ v.co for v in m.vertices]
    e.to_mesh_clear()
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
c = (lo + hi) / 2
size = max(hi - lo) * 1.1

sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_cavity = False
sh.show_object_outline = True
sh.background_type = "VIEWPORT"
sh.background_color = (0.62, 0.62, 0.64)
sc.render.resolution_x = int(a.res * 0.75)
sc.render.resolution_y = a.res
sc.render.film_transparent = False
sc.view_settings.view_transform = "Standard"

cam_data = bpy.data.cameras.new("qa")
cam = bpy.data.objects.new("qa", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam

sign = 1 if a.front[0] == "+" else -1
ax = a.front[1].upper()
f = Vector((0, 0, 0)); f["XYZ".index(ax)] = sign
side = Vector((f.y, -f.x, 0))
views = {"front": f, "side": side, "back": -f, "three_quarter_top": (f + side).normalized() * 0.8 + Vector((0, 0, 1.0))}
os.makedirs(a.out_dir, exist_ok=True)
for name, d in views.items():
    d = Vector(d).normalized()
    cam.location = c + d * 10
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size
    sc.render.filepath = os.path.join(os.path.abspath(a.out_dir), f"qa_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("saved", sc.render.filepath)
