"""Import a GLB, print stats as JSON, and render a review contact sheet.

Usage:
  blender -b --factory-startup -P tools/blender/inspect_glb.py -- in.glb out_sheet.png [mode] [views...]
mode: material (default) | solid | wire | random. Views as in blender-asset-qa review_shots.py.
"""
import json
import os
import sys

import bpy

SKILLS = os.path.join(os.path.dirname(__file__), "..", "..", ".claude", "skills", "blender-asset-qa", "scripts")
sys.path.insert(0, os.path.abspath(SKILLS))

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], os.path.abspath(argv[1])
mode = argv[2] if len(argv) > 2 else "material"
views = argv[3:] or ["front", "right", "back", "three_quarter"]

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(src))

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
tris = 0
lo = [1e9] * 3
hi = [-1e9] * 3
for o in meshes:
    m = o.data
    m.calc_loop_triangles()
    tris += len(m.loop_triangles)
    for c in o.bound_box:
        w = o.matrix_world @ __import__("mathutils").Vector(c)
        for i in range(3):
            lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
stats = {
    "meshes": [o.name for o in meshes],
    "tris": tris,
    "dims_xyz": [round(hi[i] - lo[i], 3) for i in range(3)],
    "min_z": round(lo[2], 3),
    "materials": [m.name for m in bpy.data.materials],
    "images": [(i.name, list(i.size)) for i in bpy.data.images],
    "armatures": [(o.name, len(o.data.bones)) for o in bpy.data.objects if o.type == "ARMATURE"],
    "actions": [(a.name, [round(x, 1) for x in a.frame_range]) for a in bpy.data.actions],
}
print("@@STATS@@" + json.dumps(stats))

import review_shots  # noqa: E402
print(review_shots.run(objects=[o.name for o in meshes], out=out, views=views, mode=mode, res=640))
