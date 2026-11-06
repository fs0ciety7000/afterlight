"""QA sheet of small props: each GLB side by side, rendered from several views (Workbench, textured).

  blender -b --factory-startup -P tools/blender/qa_props_sheet.py -- out.png a.glb b.glb ... \
      [--open-lid chest.glb] [--res 520] [--views front34,side,game]

--open-lid: also shows that GLB with its ChestLid node opened (-110 deg), as the game draws a taken chest.
Views: front34 (3/4 front, slightly above), side, back34, game (50 deg pitch from the south, the exploration
camera). Writes one PNG: one row per view, one column per prop, labels on top.
"""
import math
import os
import sys
import tempfile

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = os.path.abspath(argv[0])
res = 520
views = ["front34", "side", "back34", "game"]
srcs, open_lid = [], []
i = 1
while i < len(argv):
    if argv[i] == "--open-lid":
        open_lid.append(os.path.abspath(argv[i + 1]))
        i += 2
    elif argv[i] == "--res":
        res = int(argv[i + 1])
        i += 2
    elif argv[i] == "--views":
        views = argv[i + 1].split(",")
        i += 2
    else:
        srcs.append(os.path.abspath(argv[i]))
        i += 1

DIRS = {"front34": (0.6, -1, 0.45), "side": (1, 0, 0.12), "back34": (-0.6, 1, 0.45), "game": (0, -1, 1.19)}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_cavity = True
scene.display.shading.show_object_outline = True
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("w")
scene.display.shading.background_type = "VIEWPORT"
scene.render.resolution_x = scene.render.resolution_y = res

items = [(s, False) for s in srcs] + [(s, True) for s in open_lid]
groups = []
for k, (src, opened) in enumerate(items):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=src)
    new = [o for o in bpy.data.objects if o not in before]
    if opened:
        for o in new:
            if o.name.startswith("ChestLid"):
                o.rotation_mode = "XYZ"
                o.rotation_euler.x -= math.radians(110)  # same angle as Godot's rotation.x
    for o in new:
        if o.parent is None:
            o.location.x += k * 100.0  # far apart: one camera per prop and view
    label = os.path.basename(src).replace(".glb", "") + (" (open)" if opened else "")
    groups.append((label, [o for o in new if o.type == "MESH"]))

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
tmp = tempfile.mkdtemp()
tiles = []
for view in views:
    row = []
    for label, obs in groups:
        bpy.context.view_layer.update()
        pts = [o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
        lo = Vector([min(p[i] for p in pts) for i in range(3)])
        hi = Vector([max(p[i] for p in pts) for i in range(3)])
        c = (lo + hi) / 2
        r = (hi - lo).length / 2
        d = Vector(DIRS[view]).normalized()
        cam.location = c + d * (r * 4)
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        cam_data.ortho_scale = r * 2.3
        path = os.path.join(tmp, f"{view}_{len(row)}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        row.append((label, view, path))
    tiles.append(row)
print("@@TILES", repr(tiles))
manifest = os.path.join(tmp, "tiles.txt")
with open(manifest, "w") as f:
    for row in tiles:
        f.write("\t".join(f"{lb}|{v}|{p}" for lb, v, p in row) + "\n")
print("@@MANIFEST", manifest)
