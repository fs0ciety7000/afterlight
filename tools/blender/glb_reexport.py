"""Re-export a GLB with a JPEG texture (input for services that may not read EXT_texture_webp, e.g. Meshy rigging).

  blender -b --factory-startup -P tools/blender/glb_reexport.py -- in.glb out.glb
Prints @@REPORT@@ json (objects, out size).
"""
import json
import os
import sys

import bpy

src, dst = sys.argv[sys.argv.index("--") + 1:][:2]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(src))
os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.abspath(dst), export_format="GLB", export_image_format="JPEG",
                          export_animations=False, export_yup=True)
print("@@REPORT@@" + json.dumps({
    "objects": [[o.name, o.type, [round(d, 2) for d in o.dimensions]] for o in bpy.data.objects],
    "out": dst, "kb": round(os.path.getsize(dst) / 1024)}))
