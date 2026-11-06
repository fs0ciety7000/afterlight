"""Render a strip of poses (one view, several frames) for each clip of a GLB, Workbench (headless-safe).

Usage:
  blender -b --factory-startup -P tools/blender/render_pose_strip.py -- in.glb out.png \
      [--clips a,b] [--frames 6] [--view side|front|back|three_quarter] [--front -Y] [--res 360]
One row per clip, --frames evenly spaced frames per row; frame numbers are written on each cell.
"""
import argparse
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("out")
ap.add_argument("--clips", default="")
ap.add_argument("--frames", type=int, default=6)
ap.add_argument("--view", default="side")
ap.add_argument("--front", default="+Y")
ap.add_argument("--res", type=int, default=360)
a = ap.parse_args(argv)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(a.src))
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o)
sc = bpy.context.scene
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.animation_data_create()
for tr in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(tr)
acts = list(bpy.data.actions)
if a.clips:
    want = a.clips.split(",")
    acts = [next(x for x in bpy.data.actions if x.name == w or w in x.name) for w in want]

sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sh.background_type = "VIEWPORT"
sh.background_color = (0.62, 0.62, 0.64)
sc.render.resolution_x = int(a.res * 0.8)
sc.render.resolution_y = a.res
sc.view_settings.view_transform = "Standard"
cam_data = bpy.data.cameras.new("qa")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 2.3
cam = bpy.data.objects.new("qa", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
sign = 1 if a.front[0] == "+" else -1
f = Vector((0, 0, 0)); f["XYZ".index(a.front[1].upper())] = sign
side = Vector((f.y, -f.x, 0))
d = {"front": f, "side": side, "back": -f, "three_quarter": (f + side).normalized() + Vector((0, 0, 1.2))}[a.view]
d = Vector(d).normalized()
c = Vector((0, 0, 0.85))
cam.location = c + d * 10
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()

tmp = os.path.join(os.path.dirname(os.path.abspath(a.out)), "_strip_tmp")
os.makedirs(tmp, exist_ok=True)
rows = []
for act in acts:
    rig.animation_data.action = act
    if act.slots:
        rig.animation_data.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    n = max(1, a.frames)
    frames = [round(f0 + (f1 - f0) * i / max(1, n - 1)) for i in range(n)]
    cells = []
    for fr in frames:
        sc.frame_set(int(fr))
        p = os.path.join(tmp, f"{len(rows)}_{fr}.png")
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        cells.append((p, fr))
    rows.append((act.name, cells))

# compose with Blender's image API-free approach: write a manifest, compose with PIL if available
import json  # noqa: E402
man = os.path.join(tmp, "manifest.json")
json.dump(rows, open(man, "w"))
print("@@MANIFEST@@" + man)
