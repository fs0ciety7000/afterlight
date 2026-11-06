"""Aubelin notice board (npc.notice_board, role "board"), hand-built, no fal.

  blender -b --factory-startup -P tools/blender/build_notice_board.py -- assets/models/props/notice_board.glb

Two posts, a framed plank panel and a small gable roof in the wood quadrant of the village props atlas
(art/source/env/tex/village_props_atlas.png, see build_village_props.py), with parchment notices and red
seals as flat-colour materials (Toon.apply keeps the albedo colour). Notices on both faces, so the board
reads from any side; front = +Z (glTF) like the other village props, base at y = 0, ~2.2 m tall.
Prints @@REPORT@@ json.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ATLAS = os.path.join(ROOT, "art", "source", "env", "tex", "village_props_atlas.png")
WOOD = (0.5, 0.5, 0.5, 0.5)  # u0, v0, du, dv (Blender UV, origin bottom-left)
DARK_WOOD = (0.5, 0.5, 0.5, 0.12)  # the darker plank band at the bottom of the wood quadrant
dst = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
rnd = random.Random(12)

bpy.ops.wm.read_factory_settings(use_empty=True)
bm = bmesh.new()
uvl = bm.loops.layers.uv.new("UVMap")


def quad(pts, region, mat, uvs=((0, 0), (1, 0), (1, 1), (0, 1))):
    f = bm.faces.new([bm.verts.new(p) for p in pts])
    f.material_index = mat
    for lp, (uu, vv) in zip(f.loops, uvs):
        lp[uvl].uv = (region[0] + (0.04 + 0.92 * uu) * region[2], region[1] + (0.04 + 0.92 * vv) * region[3])
    return f


def box(c, size, region, mat=0, rot=Matrix.Identity(3)):
    """Closed box centred at c (x, y) with its base at c.z; every face maps the whole region."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2]
    corner = [Vector((sx * hx, sy * hy, z)) for z in (0, hz) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    p = [Vector(c) + rot @ v for v in corner]
    b0, b1, b2, b3, t0, t1, t2, t3 = p
    long_x = size[0] >= size[2]
    for f in ([b0, b1, t1, t0], [b1, b2, t2, t1], [b2, b3, t3, t2], [b3, b0, t0, t3], [t0, t1, t2, t3], [b3, b2, b1, b0]):
        uvs = ((0, 0), (1, 0), (1, 1), (0, 1)) if long_x else ((0, 0), (0, 1), (1, 1), (1, 0))
        quad(f, region, mat, uvs)


# posts, panel, frame
for sx in (-1, 1):
    box((sx * 0.78, 0, 0), (0.12, 0.12, 2.12), DARK_WOOD)
box((0, 0, 0.95), (1.5, 0.05, 0.96), WOOD)  # plank panel, its ends hidden in the battens and posts
box((0, 0, 1.88), (1.66, 0.09, 0.08), DARK_WOOD)  # top batten
box((0, 0, 0.9), (1.66, 0.09, 0.08), DARK_WOOD)  # bottom batten
# gable roof: two planks meeting over the panel
for sy in (-1, 1):
    r = Matrix.Rotation(sy * math.radians(-28), 3, "X")
    box((0, sy * 0.17, 2.02), (1.9, 0.4, 0.035), WOOD, rot=r)
box((0, 0, 2.09), (1.94, 0.07, 0.07), DARK_WOOD)  # ridge, sunk into the plank tops

# notices on both faces, sheets not overlapping: parchment 1.5 mm off the panel, red seals 1.5 mm off the
# sheets (above the 1 mm z-fight distance, within the 2 mm contact tolerance of blender-asset-qa)
sheets = [(-0.5, 1.5, 0.34, 0.42), (-0.08, 1.58, 0.3, 0.36), (0.42, 1.52, 0.32, 0.42), (-0.32, 1.12, 0.3, 0.3),
          (0.14, 1.1, 0.26, 0.3)]
for side in (-1, 1):
    y = side * (0.025 + 0.0015)
    for k, (x, z, w, h) in enumerate(sheets):
        x = x * side
        a = math.radians(rnd.uniform(-6, 6))
        rot = Matrix.Rotation(a, 3, "Y")
        corners = [Vector((-w / 2, 0, -h / 2)), Vector((w / 2, 0, -h / 2)), Vector((w / 2, 0, h / 2)),
                   Vector((-w / 2, 0, h / 2))]
        pts = [Vector((x, y, z)) + rot @ v for v in corners]
        if side > 0:  # faces must point away from the panel
            pts.reverse()
        quad(pts, (0, 0, 1, 1), 1 + (k % 2))
        if k in (0, 2, 4):
            s = 0.035
            cpos = Vector((x, y + side * 0.0015, z + h / 2 - 0.05))
            seal = [cpos + rot @ Vector(v) for v in ((-s, 0, -s), (s, 0, -s), (s, 0, s), (-s, 0, s))]
            if side > 0:
                seal.reverse()
            quad(seal, (0, 0, 1, 1), 3)

bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f.material_index == 0])
bm.normal_update()
me = bpy.data.meshes.new("notice_board")
bm.to_mesh(me)
bm.free()
ob = bpy.data.objects.new("notice_board", me)
bpy.context.scene.collection.objects.link(ob)


def flat(name, hex_col):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = [((int(hex_col[i:i + 2], 16) / 255) ** 2.2) for i in (1, 3, 5)] + [1]
    bsdf.inputs["Roughness"].default_value = 1.0
    return m


wood = bpy.data.materials.new("env_notice_board")
wood.use_nodes = True
nt = wood.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
bsdf.inputs["Roughness"].default_value = 1.0
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(ATLAS)
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
for m in (wood, flat("notice_paper", "#efe2c2"), flat("notice_paper_old", "#dccb9e"), flat("notice_seal", "#a8443a")):
    me.materials.append(m)
for p in me.polygons:
    p.use_smooth = False

os.makedirs(os.path.dirname(dst), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=dst, export_format="GLB", use_selection=False, export_apply=True, export_image_format="WEBP",
    export_image_quality=88, export_animations=False, export_materials="EXPORT", export_normals=True,
    export_texcoords=True, export_tangents=False, export_yup=True)
me.calc_loop_triangles()
pts = [v.co for v in me.vertices]
print("@@REPORT@@" + json.dumps({
    "tris": len(me.loop_triangles), "glb_kb": round(os.path.getsize(dst) / 1024),
    "size_m": [round(max(p[i] for p in pts) - min(p[i] for p in pts), 2) for i in range(3)],
    "base_z": round(min(p.z for p in pts), 4), "out": dst}))
