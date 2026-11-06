"""Run the blender-asset-qa check (.claude/skills/blender-asset-qa/scripts/qa_check.py) on an exported GLB.

  blender -b --factory-startup -P tools/blender/qa_glb.py -- in.glb [--profile game]
Prints @@QA@@ json. Duplicate verts and open edges along UV seams are expected after a glTF round trip
(the format splits vertices per UV), so they are reported but not counted as defects by the caller.
"""
import json
import os
import sys

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, ".claude", "skills", "blender-asset-qa", "scripts"))
import qa_check  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
profile = argv[argv.index("--profile") + 1] if "--profile" in argv else "game"
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(argv[0]))
r = qa_check.run(objects=[o.name for o in bpy.data.objects if o.type == "MESH"], profile=profile)
print("@@QA@@" + json.dumps(r))
