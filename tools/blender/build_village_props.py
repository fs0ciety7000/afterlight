"""Small hand-built village dressing pieces for Aubelin (no fal): doorstep and flower bed.

  python3 tools/blender/build_village_props.py atlas      # system python (PIL): painted 1K atlas
  blender -b --factory-startup -P tools/blender/build_village_props.py -- assets/environment

Atlas quadrants (Blender UV, origin bottom-left): stone (0, .5), wood (.5, .5), terracotta / soil (0, 0),
flower tuft with blossoms (.5, 0, alpha). One material per piece, WebP; front = +Z (glTF), base at y = 0.
  doorstep   : stone slab 1.3 x 0.75 m with two terracotta pots of flowers (~350 tris)
  flower_bed : 2.4 x 0.8 m plank border, soil, 7 crossed flower cards (~300 tris)
"""
import math
import os
import random
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ATLAS = os.path.join(ROOT, "art", "source", "env", "tex", "village_props_atlas.png")


def make_atlas() -> None:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    sys.path.insert(0, os.path.dirname(__file__))
    from paint_leaf_tufts import paint

    rnd = random.Random(5)
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    # stone: cool lavender grey, painted slabs with dark cracks
    st = Image.new("RGB", (512, 512), (176, 170, 182))
    d = ImageDraw.Draw(st)
    for k in range(70):
        x, y = rnd.randint(0, 512), rnd.randint(0, 512)
        r = rnd.randint(30, 70)
        c = rnd.choice([(186, 180, 192), (166, 160, 174), (195, 190, 196)])
        d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=c)
    for k in range(14):
        x, y = rnd.randint(0, 512), rnd.randint(0, 512)
        d.line([(x, y), (x + rnd.randint(-60, 60), y + rnd.randint(-40, 40))], fill=(120, 112, 128), width=3)
    st = st.filter(ImageFilter.GaussianBlur(1.2))
    atlas.paste(st, (0, 0))
    # wood: warm planks along U
    wd = Image.new("RGB", (512, 512), (150, 98, 60))
    d = ImageDraw.Draw(wd)
    for y in range(0, 512, 64):
        d.rectangle((0, y, 512, y + 60), fill=rnd.choice([(158, 104, 64), (146, 94, 56), (166, 112, 70)]))
        d.line([(0, y + 61), (512, y + 61)], fill=(96, 60, 38), width=4)
        for k in range(6):
            x = rnd.randint(0, 512)
            d.line([(x, y + rnd.randint(10, 50)), (x + rnd.randint(60, 160), y + rnd.randint(10, 50))],
                   fill=(132, 84, 50), width=2)
    atlas.paste(wd, (512, 0))
    # terracotta (left half) / soil (right half)
    tc = Image.new("RGB", (512, 512), (196, 104, 70))
    d = ImageDraw.Draw(tc)
    d.rectangle((0, 0, 256, 70), fill=(214, 124, 84))  # rim band
    d.rectangle((0, 70, 256, 82), fill=(160, 82, 56))
    d.rectangle((256, 0, 512, 512), fill=(92, 66, 48))
    for k in range(260):
        x, y = rnd.randint(260, 508), rnd.randint(4, 508)
        r = rnd.randint(2, 6)
        d.ellipse((x - r, y - r, x + r, y + r), fill=rnd.choice([(78, 56, 40), (110, 80, 58)]))
    atlas.paste(tc, (0, 512))
    fl = paint("orchard", seed=9, fruit=True, fruit_colors=["#f2b8c6", "#ffffff", "#f4d35e", "#c9a0dc"],
               fruit_count=(16, 20), fruit_size=(0.045, 0.06))
    atlas.paste(fl, (512, 512))
    atlas.save(ATLAS)
    print(ATLAS)


if len(sys.argv) > 1 and sys.argv[1] == "atlas":
    make_atlas()
    sys.exit(0)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

STONE, WOOD, POT, SOIL, FLOWER = (0.0, 0.5, 0.5, 0.5), (0.5, 0.5, 0.5, 0.5), (0.0, 0.0, 0.25, 0.5), \
    (0.25, 0.0, 0.25, 0.5), (0.5, 0.0, 0.5, 0.5)  # u0, v0, du, dv


def box(bm, uvl, c, size, region, top_scale=1.0):
    """Frustum box (top face scaled), UVs: each face fills the region (planar)."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2]
    bot = [Vector((c[0] + sx * hx, c[1] + sy * hy, c[2])) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    top = [Vector((c[0] + sx * hx * top_scale, c[1] + sy * hy * top_scale, c[2] + hz))
           for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    faces = [top, [bot[0], bot[1], top[1], top[0]], [bot[1], bot[2], top[2], top[1]],
             [bot[2], bot[3], top[3], top[2]], [bot[3], bot[0], top[0], top[3]]]
    for quad in faces:
        f = bm.faces.new([bm.verts.new(p) for p in quad])
        for lp, (uu, vv) in zip(f.loops, ((0.05, 0.05), (0.95, 0.05), (0.95, 0.95), (0.05, 0.95))):
            lp[uvl].uv = (region[0] + uu * region[2], region[1] + vv * region[3])


def cylinder(bm, uvl, c, r0, r1, h, n=8):
    ring0 = [Vector((c[0] + r0 * math.cos(a), c[1] + r0 * math.sin(a), c[2])) for a in
             (k / n * math.tau for k in range(n))]
    ring1 = [Vector((c[0] + r1 * math.cos(a), c[1] + r1 * math.sin(a), c[2] + h)) for a in
             (k / n * math.tau for k in range(n))]
    for k in range(n):
        q = [ring0[k], ring0[(k + 1) % n], ring1[(k + 1) % n], ring1[k]]
        f = bm.faces.new([bm.verts.new(p) for p in q])
        for lp, (uu, vv) in zip(f.loops, ((k / n, 0.0), ((k + 1) / n, 0.0), ((k + 1) / n, 1.0), (k / n, 1.0))):
            lp[uvl].uv = (POT[0] + uu * POT[2], POT[1] + (0.15 + vv * 0.84) * POT[3])
    # soil disc just under the rim
    f = bm.faces.new([bm.verts.new(p - Vector((0, 0, 0.04))) for p in ring1])
    for lp in f.loops:
        lp[uvl].uv = (SOIL[0] + 0.5 * SOIL[2], SOIL[1] + 0.5 * SOIL[3])


def flower_cards(bm, uvl, c, size, cards, normals, rnd):
    """Two crossed double-sided cards; normals up (lit like the ground)."""
    a0 = rnd.uniform(0, math.pi)
    for a in (a0, a0 + math.pi / 2):
        t = Vector((math.cos(a), math.sin(a), 0)) * size * 0.5
        quad = [c - t, c + t, c + t + Vector((0, 0, size * 0.8)), c - t + Vector((0, 0, size * 0.8))]
        uvs = ((0.06, 0.06), (0.94, 0.06), (0.94, 0.94), (0.06, 0.94))
        for order in ((0, 1, 2, 3), (3, 2, 1, 0)):
            f = bm.faces.new([bm.verts.new(quad[j]) for j in order])
            for lp, j in zip(f.loops, order):
                lp[uvl].uv = (FLOWER[0] + uvs[j][0] * FLOWER[2], FLOWER[1] + uvs[j][1] * FLOWER[3])
            cards.append(f.index if f.index >= 0 else len(bm.faces) - 1)


def finish(name: str, bm, out_dir: str) -> None:
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    n_faces = len(bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    # flower cards (alpha in the atlas) get up-facing normals
    uv = me.uv_layers.active.data
    corner = []
    for p in me.polygons:
        is_flower = all(uv[li].uv[0] >= 0.5 and uv[li].uv[1] < 0.5 for li in p.loop_indices)
        for li in p.loop_indices:
            corner.append(Vector((0, 0, 1)) if is_flower else p.normal.copy())
    me.normals_split_custom_set(corner)
    mat = bpy.data.materials.new(f"env_{name}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 1.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(ATLAS)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
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
    print("@@BUILT", name, len(me.loop_triangles), "tris", os.path.getsize(dst) // 1024, "KB", n_faces)


def build(out_dir: str) -> None:
    rnd = random.Random(3)
    # Blender: -Y = glTF +Z (front). Doorstep: slab in front of the door, pots at both ends.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    cards = []
    box(bm, uvl, (0, 0, 0), (1.3, 0.75, 0.16), STONE, top_scale=0.94)
    for sx in (-1, 1):
        c = Vector((sx * 0.86, 0.05, 0))
        cylinder(bm, uvl, c, 0.15, 0.21, 0.36)
        flower_cards(bm, uvl, c + Vector((0, 0, 0.28)), 0.6, cards, None, rnd)
    finish("doorstep", bm, out_dir)
    # flower bed: plank border + soil + flower clumps
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    L, W, T, Hb = 2.4, 0.8, 0.08, 0.2
    box(bm, uvl, (0, -W / 2 + T / 2, 0), (L, T, Hb), WOOD)
    box(bm, uvl, (0, W / 2 - T / 2, 0), (L, T, Hb), WOOD)
    box(bm, uvl, (-L / 2 + T / 2, 0, 0), (T, W - 2 * T, Hb), WOOD)
    box(bm, uvl, (L / 2 - T / 2, 0, 0), (T, W - 2 * T, Hb), WOOD)
    box(bm, uvl, (0, 0, 0), (L - 2 * T, W - 2 * T, Hb * 0.7), SOIL)
    for k in range(7):
        x = -L / 2 + 0.3 + k * (L - 0.6) / 6 + rnd.uniform(-0.06, 0.06)
        y = rnd.uniform(-0.12, 0.12)
        flower_cards(bm, uvl, Vector((x, y, Hb * 0.6)), rnd.uniform(0.5, 0.65), cards, None, rnd)
    finish("flower_bed", bm, out_dir)


build(os.path.abspath(sys.argv[sys.argv.index("--") + 1]))
