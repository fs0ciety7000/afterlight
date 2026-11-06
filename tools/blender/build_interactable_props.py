"""Interactable props for chests, mist herbs and discoveries, hand-built (no fal, owner's small-props rule).

  blender -b --factory-startup -P tools/blender/build_interactable_props.py -- assets/models/props

Writes, base at y = 0, front = +Z (glTF), toon-friendly (flat colours + the village props atlas; Toon.apply
keeps each surface's albedo texture and colour):
  chest.glb             0.9 x 0.62 x 0.6 m; two nodes, ChestBody and ChestLid. The lid's origin is on its hinge
                        (back top edge), so the game opens it by turning ChestLid around X (about -110 deg).
  mist_herb.glb         ~0.7 m tuft of pale blue blades with glowing tips (docs/content/bestiary_discoveries.md
                        2.3: "touffe bleu pâle qui luit faiblement"); the halo is added in the game.
  discovery_marker.glb  1.5 m carved stone post with a floating pale crystal (level dressing: a discovery spot
                        with nothing else to show).
  discovery_crystal.glb the crystal alone, floating at 1 m: what the game draws over a discovery anchor.
Prints one @@BUILT line per file (tris, KB, dimensions).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit_mesh import ATLAS, STONE, WOOD, box, prism  # noqa: E402

DARK_WOOD = (0.5, 0.5, 0.5, 0.12)  # the darker plank band of the wood quadrant
FLAT = {  # name: (base colour sRGB hex, emission strength)
    "iron": ("#3b3a46", 0.0),
    "brass": ("#c79a3c", 0.0),
    "inside": ("#2e2219", 0.0),
    "stem": ("#4f7088", 0.0),
    "blade": ("#9fc3e6", 0.0),
    "tip": ("#e8f1ff", 0.0),
    "crystal": ("#e8e2f4", 0.0),
}


def srgb(hexstr):
    c = [int(hexstr[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def atlas_mat():
    mat = bpy.data.materials.get("props_atlas")
    if mat:
        return mat
    mat = bpy.data.materials.new("props_atlas")
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 1.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(ATLAS)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def flat_mat(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = srgb(FLAT[name][0])
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


class Part:
    """One bmesh per object; faces carry a material slot index (0 = atlas, then flat colours)."""

    def __init__(self, name, slots):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.slots = slots  # ["atlas", "iron", ...]

    def add(self, slot, fn, *a, **kw):
        before = set(self.bm.faces)
        fn(self.bm, self.uv, *a, **kw)
        for f in self.bm.faces:
            if f not in before:
                f.material_index = self.slots.index(slot)

    def obj(self, origin=(0, 0, 0)):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        for v in self.bm.verts:
            v.co -= Vector(origin)
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for s in self.slots:
            me.materials.append(atlas_mat() if s == "atlas" else flat_mat(s))
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        ob.location = origin
        bpy.context.scene.collection.objects.link(ob)
        return ob


def export(objs, dst):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=True, export_apply=True,
        export_image_format="WEBP", export_image_quality=88, export_animations=False,
        export_materials="EXPORT", export_normals=True, export_texcoords=True, export_tangents=False,
        export_yup=True,
    )
    tris = 0
    for o in objs:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
    lo = Vector([min((o.matrix_world @ v.co)[i] for o in objs for v in o.data.vertices) for i in range(3)])
    hi = Vector([max((o.matrix_world @ v.co)[i] for o in objs for v in o.data.vertices) for i in range(3)])
    d = hi - lo
    print("@@BUILT", os.path.basename(dst), tris, "tris", os.path.getsize(dst) // 1024, "KB",
          "dims %.2f x %.2f x %.2f" % (d.x, d.y, d.z))


def build_chest(out):
    # Blender axes: X along the chest, -Y = front (glTF +Z), Z up. Body 0.9 x 0.56 x 0.42 m.
    reset()
    w, d, h = 0.9, 0.56, 0.42
    body = Part("ChestBody", ["atlas", "iron", "brass", "inside"])
    body.add("atlas", box, (0, 0, 0), (w, d, h), WOOD)
    body.add("atlas", box, (0, 0, 0), (w + 0.04, d + 0.04, 0.06), DARK_WOOD)  # plinth band
    for sx in (-0.3, 0.3):  # iron bands wrapping the body
        body.add("iron", box, (sx, 0, 0.0), (0.06, d + 0.03, h + 0.005), WOOD)
    for sx in (-1, 1):  # corner posts
        for sy in (-1, 1):
            body.add("iron", box, (sx * (w / 2 - 0.02), sy * (d / 2 - 0.02), 0.0), (0.06, 0.06, h + 0.01), WOOD)
    body.add("brass", box, (0, -d / 2 - 0.012, h - 0.17), (0.14, 0.03, 0.16), WOOD)  # lock plate
    body.add("inside", box, (0, 0, h - 0.06), (w - 0.08, d - 0.08, 0.065), WOOD)  # dark inside, seen open
    b = body.obj()

    # lid: barrel top of 5 staves, hinge on the back top edge (y = +d/2, z = h)
    lid = Part("ChestLid", ["atlas", "iron", "brass"])
    r = d / 2 + 0.02
    staves = 5
    for k in range(staves):
        a0 = math.pi * k / staves
        a1 = math.pi * (k + 1) / staves
        am = (a0 + a1) / 2
        chord = 2 * r * math.sin(math.pi / staves / 2) + 0.004
        # each stave: a thin box lying along X, rolled to follow the barrel
        c = (0, math.cos(am) * r * 0.97, h + math.sin(am) * r * 0.62)
        lid.add("atlas", box, (c[0], c[1], c[2] - 0.022), (w + 0.03, chord, 0.045), WOOD,
                roll=am - math.pi / 2)
    for sx in (-0.3, 0.3):
        for k in range(staves):
            am = math.pi * (k + 0.5) / staves
            chord = 2 * r * math.sin(math.pi / staves / 2) + 0.01
            c = (sx, math.cos(am) * (r * 0.97 + 0.012), h + math.sin(am) * (r * 0.62 + 0.012))
            lid.add("iron", box, (c[0], c[1], c[2] - 0.022), (0.065, chord, 0.05), WOOD, roll=am - math.pi / 2)
    for sx in (-1, 1):  # flat end caps (half ellipses) as fans
        verts = [(sx * (w / 2 + 0.016), math.cos(math.pi * k / 8) * r, h + math.sin(math.pi * k / 8) * r * 0.62)
                 for k in range(9)]
        bm = lid.bm
        ring = [bm.verts.new(v) for v in verts]
        f = bm.faces.new(ring if sx > 0 else list(reversed(ring)))
        f.material_index = 0
        for lp in f.loops:
            lp[lid.uv].uv = (WOOD[0] + (0.5 + lp.vert.co.y / (2.2 * r)) * WOOD[2] * 0.9,
                             WOOD[1] + (lp.vert.co.z - h) / (r * 0.7) * WOOD[3] * 0.4)
    lid.add("brass", box, (0, -r - 0.012, h - 0.02), (0.1, 0.03, 0.12), WOOD)  # hasp
    lo = lid.obj(origin=(0, d / 2, h))
    lo.parent = b
    lo.location = (0, d / 2, h)
    export([b, lo], os.path.join(out, "chest.glb"))


def blade(part, slot, base, yaw, lean, length, width, segs=3):
    """Tapered three-sided blade curving outwards, closed (toon-friendly from every side)."""
    bm = part.bm
    rot = Matrix.Rotation(yaw, 3, "Z")
    rings = []
    for s in range(segs + 1):
        t = s / segs
        out = math.sin(t * lean) * length * 0.5
        z = length * (1 - (1 - t) ** 1.6) * 0.95
        wd = width * (1 - t) + 0.004
        c = Vector(base) + rot @ Vector((out, 0, z))
        rings.append([bm.verts.new(c + rot @ Vector((math.cos(a) * wd * 0.4, math.sin(a) * wd, 0)))
                      for a in (0, 2.1, 4.2)])
    idx = part.slots.index(slot)
    for s in range(segs):
        for k in range(3):
            f = bm.faces.new([rings[s][k], rings[s][(k + 1) % 3], rings[s + 1][(k + 1) % 3], rings[s + 1][k]])
            f.material_index = idx
    bm.faces.new(list(reversed(rings[0]))).material_index = idx
    tip_c = sum((v.co for v in rings[-1]), Vector()) / 3
    return tip_c, rings[-1]


def bud(part, c, r):
    bm = part.bm
    idx = part.slots.index("tip")
    pts = [Vector(c) + Vector(p) * r for p in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1.6), (0, 0, -0.8))]
    v = [bm.verts.new(p) for p in pts]
    for a, b2, top in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
        bm.faces.new([v[a], v[b2], v[top]]).material_index = idx


def build_herb(out):
    reset()
    rnd = random.Random(31)
    herb = Part("MistHerb", ["stem", "blade", "tip"])
    # low rosette of dark leaves, then seven pale blades with glowing buds
    for k in range(6):
        blade(herb, "stem", (0, 0, 0), k * math.tau / 6 + 0.3, 2.2, 0.34, 0.07, segs=2)
    for k in range(7):
        yaw = k * math.tau / 7 + rnd.uniform(-0.3, 0.3)
        ln = rnd.uniform(0.55, 0.75)
        tip, _ = blade(herb, "blade", (math.cos(yaw) * 0.04, math.sin(yaw) * 0.04, 0), yaw, rnd.uniform(0.7, 1.2),
                       ln, 0.045)
        bud(herb, tip + Vector((0, 0, 0.01)), 0.036)
    export([herb.obj()], os.path.join(out, "mist_herb.glb"))


def build_marker(out, post=True):
    reset()
    m = Part("DiscoveryMarker" if post else "DiscoveryCrystal", ["atlas", "crystal"] if post else ["crystal"])
    if post:
        m.add("atlas", box, (0, 0, 0), (0.5, 0.5, 0.12), STONE, top_scale=0.9)
        m.add("atlas", prism, (0, 0, 0.12), 0.17, 0.72, 6, STONE, top_scale=0.78, phase=math.pi / 6)
        m.add("atlas", box, (0, 0, 0.84), (0.3, 0.3, 0.07), STONE, top_scale=1.15)
    # floating crystal (detached on purpose): elongated octahedron, 0.44 m, centre at 1.22 m (1.0 alone)
    bm = m.bm
    idx = m.slots.index("crystal")
    c = Vector((0, 0, 1.22 if post else 1.0))
    eq = [c + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, 0)) for a in (0.3, 1.87, 3.44, 5.01)]
    top, bot = bm.verts.new(c + Vector((0, 0, 0.26))), bm.verts.new(c - Vector((0, 0, 0.18)))
    ev = [bm.verts.new(p) for p in eq]
    for k in range(4):
        bm.faces.new([ev[k], ev[(k + 1) % 4], top]).material_index = idx
        bm.faces.new([ev[(k + 1) % 4], ev[k], bot]).material_index = idx
    export([m.obj()], os.path.join(out, "discovery_marker.glb" if post else "discovery_crystal.glb"))


if __name__ == "__main__":
    dst_dir = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
    os.makedirs(dst_dir, exist_ok=True)
    build_chest(dst_dir)
    build_herb(dst_dir)
    build_marker(dst_dir)
    build_marker(dst_dir, post=False)
