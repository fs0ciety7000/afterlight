"""Small hand-built pieces for the Lantern Mire (no fal), painted with the village props atlas.

  blender -b --factory-startup -P tools/blender/build_mire_props.py -- assets/environment

Atlas: art/source/env/tex/village_props_atlas.png (tools/blender/build_village_props.py atlas), quadrants
stone (0, .5) and wood (.5, .5). One material per piece, WebP; front = +Z (glTF).
  boardwalk : 2 x 4 m pontoon section along Z, plank deck with its TOP at y = 0, piles down to y = -1.3,
              two short mooring posts (~250 tris). Placed at deck height by the location builder.
  beacon    : the drowned beacon of the mire, an 8 m post on a stone footing with a lantern cage at the
              top (lamp centre at y = 7.4) (~300 tris).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ATLAS = os.path.join(ROOT, "art", "source", "env", "tex", "village_props_atlas.png")
STONE, WOOD = (0.0, 0.5, 0.5, 0.5), (0.5, 0.5, 0.5, 0.5)  # u0, v0, du, dv


def box(bm, uvl, c, size, region, top_scale=1.0, tilt=0.0):
    """Frustum box from z = c.z up (top face scaled); each face fills the atlas region (planar).
    `tilt` rolls the box around Y (radians) about its base centre."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2]
    bot = [Vector((sx * hx, sy * hy, 0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    top = [Vector((sx * hx * top_scale, sy * hy * top_scale, hz)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    rot = [[math.cos(tilt), 0, math.sin(tilt)], [0, 1, 0], [-math.sin(tilt), 0, math.cos(tilt)]]

    def place(p):
        return Vector(c) + Vector([sum(rot[i][j] * p[j] for j in range(3)) for i in range(3)])

    bot = [place(p) for p in bot]
    top = [place(p) for p in top]
    faces = [top, [bot[3], bot[2], bot[1], bot[0]], [bot[0], bot[1], top[1], top[0]],
             [bot[1], bot[2], top[2], top[1]], [bot[2], bot[3], top[3], top[2]], [bot[3], bot[0], top[0], top[3]]]
    for quad in faces:
        f = bm.faces.new([bm.verts.new(p) for p in quad])
        for lp, (uu, vv) in zip(f.loops, ((0.05, 0.05), (0.95, 0.05), (0.95, 0.95), (0.05, 0.95))):
            lp[uvl].uv = (region[0] + uu * region[2], region[1] + vv * region[3])


def finish(name: str, bm, out_dir: str) -> None:
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.new(f"env_{name}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 1.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(ATLAS)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    dst = os.path.join(out_dir, "props", f"{name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=True, export_apply=True,
        export_image_format="WEBP", export_image_quality=88, export_animations=False,
        export_materials="EXPORT", export_normals=True, export_texcoords=True, export_tangents=False,
        export_yup=True,
    )
    me.calc_loop_triangles()
    print("@@BUILT", name, len(me.loop_triangles), "tris", os.path.getsize(dst) // 1024, "KB")


def build(out_dir: str) -> None:
    # Blender: -Y = glTF +Z (front), Z up. Boardwalk runs along Y (4 m), 2 m wide.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    for k in range(8):  # eight planks across the walk, slightly uneven
        y = -1.75 + k * 0.5
        box(bm, uvl, (0.03 * ((k * 7) % 3 - 1), y, -0.08), (2.0 + 0.06 * (k % 2), 0.46, 0.08), WOOD,
            tilt=0.012 * ((k * 5) % 3 - 1))
    for sx in (-0.85, 0.85):  # stringers
        box(bm, uvl, (sx, 0, -0.22), (0.14, 4.0, 0.14), WOOD)
    for sx in (-0.85, 0.85):  # piles
        for sy in (-1.6, 1.6):
            box(bm, uvl, (sx, sy, -1.3), (0.18, 0.18, 1.08), WOOD, top_scale=0.9)
    for sx, sy in ((-0.95, 1.7), (0.95, -1.7)):  # mooring posts above the deck
        box(bm, uvl, (sx, sy, -0.2), (0.16, 0.16, 0.85), WOOD, top_scale=0.8)
    finish("boardwalk", bm, out_dir)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    box(bm, uvl, (0, 0, -0.6), (1.5, 1.5, 1.1), STONE, top_scale=0.8)  # footing, half sunk
    box(bm, uvl, (0, 0, 0.4), (0.34, 0.34, 6.8), WOOD, top_scale=0.85)  # mast
    box(bm, uvl, (0, 0, 6.6), (1.3, 0.16, 0.16), WOOD)  # yard
    box(bm, uvl, (0, 0, 7.0), (0.62, 0.62, 0.08), WOOD)  # cage floor
    for sx in (-0.27, 0.27):
        for sy in (-0.27, 0.27):
            box(bm, uvl, (sx, sy, 7.08), (0.06, 0.06, 0.66), WOOD)  # cage bars
    box(bm, uvl, (0, 0, 7.74), (0.74, 0.74, 0.22), WOOD, top_scale=0.2)  # roof
    box(bm, uvl, (0, 0, 7.12), (0.3, 0.3, 0.5), STONE, top_scale=0.7)  # lamp body
    for a in (0.6, -0.9):  # two leaning stakes around the footing
        box(bm, uvl, (math.cos(a) * 0.9, math.sin(a) * 0.9, -0.5), (0.12, 0.12, 1.6), WOOD, tilt=0.25)
    finish("beacon", bm, out_dir)


build(os.path.abspath(sys.argv[sys.argv.index("--") + 1]))
