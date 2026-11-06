"""Card-canopy vegetation: generated trunk + painted leaf-tuft cards instead of a solid canopy mass.

  python3 tools/blender/build_foliage.py atlas [names...]      # system python (PIL): leaf atlases
  blender -b --factory-startup -P tools/blender/build_foliage.py -- assets/environment [names...]

Per plant: import the raw image-to-3D mesh (Meshy or Tripo, see SPECS), scale to its real height,
split it by base colour into trunk (low saturation, or low on the tree) and canopy. The canopy becomes
  * a shrunk, decimated dark core (so gaps between cards read as depth, never as holes), and
  * N double-sided leaf cards scattered over the canopy surface (Poisson spacing), tilted towards the
    sky and the 50° camera, with custom normals pointing out of the canopy (soft, volumetric toon bands).
One material, one 1K WebP atlas: top-left quadrant = flattened trunk albedo, the other three = painted
leaf tufts (tools/blender/paint_leaf_tufts.py). Alpha is used by env_toon's alpha scissor (the Godot
builder sets it for kits with "cards": true). Pivot at the ground centre, +Z front, real-world metres.
Updates assets/environment/kit_manifest.json and art/source/env/tex/<name>_atlas.png.
"""

import json
import math
import os
import random
import sys

import numpy as np

try:
    import bmesh
    import bpy
    from mathutils import Vector
except ImportError:  # system python: atlas step only
    bpy = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.dirname(__file__))

ENV = os.path.join(ROOT, "art", "source", "env")
AB = os.path.join(ROOT, "art", "source", "enemies", "raw", "ab_birch_a")
MESHY_A = os.path.join(ENV, "raw", "birch_a", "birch_a_meshy_0.glb")
TRIPO_B = os.path.join(ENV, "raw_tripo", "birch_b", "birch_b_tripo_0.glb")
TRIPO_BUSH = os.path.join(ENV, "raw_tripo", "bush", "bush_tripo_0.glb")

# name: src, albedo, height, tufts (3 palettes, optional ":fruit"), cards, card size (m),
#       core tris, trunk tris, trunk recolour, min canopy height (fraction of the height)
SPECS = {
    "birch_a": dict(src=MESHY_A, tex="birch_a.png", h=7.0, tufts=["golden", "amber", "golden"],
                    cards=110, size=1.2, core=300, trunk=500, canopy_min=0.3),
    "birch_a_lo": dict(src=MESHY_A, tex="birch_a.png", h=7.0, tufts=["golden", "amber", "golden"],
                       cards=42, size=1.8, core=140, trunk=160, canopy_min=0.3),
    "birch_b": dict(src=TRIPO_B, tex="birch_b.png", h=9.0, tufts=["sage", "golden", "russet"],
                    cards=115, size=1.25, core=300, trunk=500, canopy_min=0.3),
    "birch_b_lo": dict(src=TRIPO_B, tex="birch_b.png", h=9.0, tufts=["sage", "golden", "russet"],
                       cards=45, size=1.9, core=140, trunk=170, canopy_min=0.3),
    "bush": dict(src=TRIPO_BUSH, tex="bush.png", h=1.3, tufts=["sage", "amber", "golden"],
                 cards=30, size=0.5, core=300, trunk=0, canopy_min=0.0, all_canopy=True, up=1.8),
    # orchard tree: the birch_a shape, shorter, brown bark, green leaves with fruit
    "fruit_tree": dict(src=MESHY_A, tex="birch_a.png", h=4.6,
                       tufts=["orchard", "orchard:fruit", "orchard_dark:fruit"],
                       cards=80, size=1.05, core=400, trunk=500, canopy_min=0.3, bark=True),
}
TUFT_MID = {  # mid colours used to pick the tuft that matches the painted albedo under each card
    "golden": (0.87, 0.65, 0.36), "amber": (0.83, 0.59, 0.29), "sage": (0.68, 0.67, 0.42),
    "russet": (0.73, 0.5, 0.31), "orchard": (0.43, 0.6, 0.3), "orchard_dark": (0.36, 0.53, 0.27),
}
# atlas quadrants (Blender UV, origin bottom-left): 0 = albedo (top-left), 1..3 = tufts
QUAD = [(0.0, 0.5), (0.5, 0.5), (0.0, 0.0), (0.5, 0.0)]
SWATCH = 0.035  # dark swatch in the bottom-left corner of each tuft cell, used by the core



def load_rgb(path: str) -> np.ndarray:
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[:, :, :3]
    bpy.data.images.remove(img)
    return a  # row 0 = bottom (Blender convention), linear? no: generated PNGs are sRGB bytes / 255


def sample(tex: np.ndarray, uv) -> np.ndarray:
    h, w, _ = tex.shape
    x = min(w - 1, max(0, int((uv[0] % 1.0) * w)))
    y = min(h - 1, max(0, int((uv[1] % 1.0) * h)))
    return tex[y, x]


def saturation(c) -> float:
    mx, mn = max(c), min(c)
    return 0.0 if mx < 1e-4 else (mx - mn) / mx


def make_atlas(spec: dict, name: str) -> str:
    from PIL import Image

    from paint_leaf_tufts import PALETTES, _hex, paint

    alb = Image.open(os.path.join(ENV, "tex", spec["tex"])).convert("RGB").resize((512, 512), Image.LANCZOS)
    if spec.get("bark"):
        a = np.asarray(alb).astype(np.float32) / 255.0
        sat = (a.max(2) - a.min(2)) / np.maximum(a.max(2), 1e-4)
        v = a.max(2)
        lo, hi = np.array([0.29, 0.2, 0.15]), np.array([0.56, 0.41, 0.29])
        bark = lo + (hi - lo) * np.clip((v - 0.2) / 0.7, 0, 1)[..., None]
        a = np.where((sat < 0.3)[..., None], bark, a)
        alb = Image.fromarray((a * 255).astype(np.uint8))
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    atlas.paste(alb.convert("RGBA"), (0, 0))
    for k, t in enumerate(spec["tufts"]):
        pal, _, extra = t.partition(":")
        tuft = paint(pal, seed=17 + k * 7 + len(name), fruit=extra == "fruit")
        # dark swatch for the core (bottom-left corner of the cell, outside the card UVs)
        sw = int(512 * SWATCH)
        dark = _hex(PALETTES[pal][0])
        core = tuple(int(c * 0.82) for c in dark) + (255,)
        tuft.paste(Image.new("RGBA", (sw, sw), core), (0, 512 - sw))
        qx, qy = QUAD[k + 1]
        atlas.paste(tuft, (int(qx * 1024), int((1.0 - qy - 0.5) * 1024)))
    path = os.path.join(ENV, "tex", f"{name}_atlas.png")
    atlas.save(path)
    return path


def tri_count(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def decimate(obj, target: int) -> None:
    tris = tri_count(obj)
    if target and tris > target:
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = target / tris
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)


def build(name: str) -> None:
    spec = SPECS[name]
    rnd = random.Random(hash(name) & 0xFFFF)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=spec["src"])
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    src = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = src.data
    co = np.array([v.co[:] for v in me.vertices])
    lo, hi = co.min(0), co.max(0)
    k = spec["h"] / (hi[2] - lo[2])
    centre = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])
    for v in me.vertices:
        v.co = Vector((np.array(v.co[:]) - centre) * k)
    me.update()
    # classify faces by the flattened albedo under their UV centroid
    tex = load_rgb(os.path.join(ENV, "tex", spec["tex"]))
    uvl = me.uv_layers.active.data
    H = spec["h"]
    canopy = []
    for p in me.polygons:
        uv = sum((Vector(uvl[li].uv) for li in p.loop_indices), Vector((0, 0))) / p.loop_total
        c = sample(tex, uv)
        z = p.center.z
        canopy.append(spec.get("all_canopy", False) or (
            saturation(c) > 0.3 and z > spec["canopy_min"] * H and max(c) > 0.25))
    # separate canopy / trunk
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    canopy_faces = [f for f in bm.faces if canopy[f.index]]
    pts, nrms, areas, cols = [], [], [], []
    uv_layer = bm.loops.layers.uv.active
    for f in canopy_faces:
        pts.append(f.calc_center_median().copy())
        nrms.append(f.normal.copy())
        areas.append(f.calc_area())
        uv = sum((Vector(lp[uv_layer].uv) for lp in f.loops), Vector((0, 0))) / len(f.loops)
        cols.append(sample(tex, uv))
    cpts = np.array([p[:] for p in pts])
    ccentre = Vector(cpts.mean(0))
    # generators flatten some canopies (paper-thin from the side): inflate the thin horizontal axis
    ext = cpts.max(0) - cpts.min(0)
    infl = Vector((max(1.0, 0.8 * ext[1] / max(ext[0], 1e-3)), max(1.0, 0.8 * ext[0] / max(ext[1], 1e-3)), 1.0))

    def inflate(v):
        d = v - ccentre
        return ccentre + Vector((d.x * infl.x, d.y * infl.y, d.z))

    pts = [inflate(p) for p in pts]
    nrms = [Vector((n.x / infl.x, n.y / infl.y, n.z)).normalized() for n in nrms]
    trunk_bm = bm.copy()
    bmesh.ops.delete(trunk_bm, geom=[f for f in trunk_bm.faces if canopy[f.index]], context="FACES")
    core_bm = bm.copy()
    bmesh.ops.delete(core_bm, geom=[f for f in core_bm.faces if not canopy[f.index]], context="FACES")
    bm.free()
    objs = []
    for label, b, target in (("trunk", trunk_bm, spec["trunk"]), ("core", core_bm, spec["core"])):
        if len(b.faces) == 0:
            b.free()
            continue
        m = bpy.data.meshes.new(label)
        b.to_mesh(m)
        b.free()
        o = bpy.data.objects.new(label, m)
        bpy.context.scene.collection.objects.link(o)
        if label == "core":
            # voxel remesh + smooth: a soft blob (decimating the generated canopy left spiky shards)
            bpy.context.view_layer.objects.active = o
            rm = o.modifiers.new("remesh", "REMESH")
            rm.mode = "VOXEL"
            rm.voxel_size = max(spec["h"] / 24.0, 0.06)
            bpy.ops.object.modifier_apply(modifier=rm.name)
            sm = o.modifiers.new("smooth", "SMOOTH")
            sm.factor = 0.8
            sm.iterations = 6
            bpy.ops.object.modifier_apply(modifier=sm.name)
            if not o.data.uv_layers:
                o.data.uv_layers.new(name="UVMap")  # remesh drops UVs; set to the swatch below
        decimate(o, target)
        objs.append(o)
    trunk = next((o for o in objs if o.name.startswith("trunk")), None)
    core = next(o for o in objs if o.name.startswith("core"))
    # core: shrink towards the canopy centre (cards stand proud of it), UVs onto the dark swatch
    for v in core.data.vertices:
        d = inflate(v.co) - ccentre
        v.co = ccentre + d * 0.86
    for poly in core.data.polygons:
        # swatch of the tuft that matches the albedo here
        qx, qy = QUAD[1 + poly.index % 3]
        for li in poly.loop_indices:
            core.data.uv_layers.active.data[li].uv = (
                qx + SWATCH * 0.25 + rnd.random() * SWATCH * 0.4, qy + SWATCH * 0.25 + rnd.random() * SWATCH * 0.4)
    if trunk:
        for li, d in enumerate(trunk.data.uv_layers.active.data):
            u, v = d.uv
            d.uv = (0.004 + (u % 1.0) * 0.492, 0.504 + (v % 1.0) * 0.492)
    # cards: Poisson-like spacing on the canopy surface, area weighted
    w = np.array(areas)
    w = w / w.sum()
    min_d = spec["size"] * 0.3
    placed = []
    kd_pts = []
    tries = 0
    while len(placed) < spec["cards"] and tries < spec["cards"] * 60:
        tries += 1
        i = int(np.searchsorted(np.cumsum(w), rnd.random()))
        i = min(i, len(pts) - 1)
        p = pts[i]
        if any((p - q).length < min_d for q in kd_pts):
            continue
        kd_pts.append(p)
        placed.append(i)
    tuft_mids = [TUFT_MID[t.partition(":")[0]] for t in spec["tufts"]]
    cards = bmesh.new()
    card_normals = []
    uvc = cards.loops.layers.uv.new("UVMap")
    for i in placed:
        p, fn = pts[i], nrms[i]
        out = (p - ccentre)
        out.z *= 0.6
        out = out.normalized()
        shade_n = (out * 0.65 + fn * 0.35 + Vector((0, 0, 0.35))).normalized()
        # card plane faces outwards, tilted towards the sky and towards the camera side
        face_n = (out + Vector((0, 0, spec.get("up", 0.9))) + Vector((rnd.uniform(-.3, .3), rnd.uniform(-.3, .3), 0))).normalized()
        t = face_n.cross(Vector((0, 0, 1)))
        if t.length < 1e-3:
            t = Vector((1, 0, 0))
        t = t.normalized()
        b = t.cross(face_n).normalized()  # card "up" (top of the tuft painting)
        roll = rnd.uniform(-0.6, 0.6)
        t, b = t * math.cos(roll) + b * math.sin(roll), b * math.cos(roll) - t * math.sin(roll)
        s = spec["size"] * rnd.uniform(0.8, 1.2) * 0.5
        c = p + out * spec["size"] * 0.05
        corners = [c - t * s - b * s, c + t * s - b * s, c + t * s + b * s, c - t * s + b * s]
        # tuft whose colour is closest to the painted canopy under the card (with some randomness)
        col = cols[i]
        dist = [sum((col[j] - m[j]) ** 2 for j in range(3)) + rnd.uniform(0, 0.02) for m in tuft_mids]
        q = QUAD[1 + int(np.argmin(dist))]
        uvs = [(0.06, 0.06), (0.94, 0.06), (0.94, 0.94), (0.06, 0.94)]
        for order in ([0, 1, 2, 3], [3, 2, 1, 0]):
            verts = [cards.verts.new(x) for x in corners]  # own verts per side (bmesh refuses twins)
            f = cards.faces.new([verts[j] for j in order])
            for lp, j in zip(f.loops, order):
                lp[uvc].uv = (q[0] + uvs[j][0] * 0.5, q[1] + uvs[j][1] * 0.5)
            card_normals.append(shade_n)
    cm = bpy.data.meshes.new("cards")
    cards.to_mesh(cm)
    cards.free()
    card_obj = bpy.data.objects.new("cards", cm)
    bpy.context.scene.collection.objects.link(card_obj)
    # join everything; card faces are the last ones
    bpy.data.objects.remove(src)
    parts = [o for o in (trunk, core, card_obj) if o]
    for o in parts:
        o.data.uv_layers[0].name = "UVMap"
        while len(o.data.uv_layers) > 1:
            o.data.uv_layers.remove(o.data.uv_layers[-1])
        for ca in list(o.data.color_attributes):
            o.data.color_attributes.remove(ca)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    me = obj.data
    for p in me.polygons:
        p.use_smooth = True
    n_cards = len(card_normals)
    first_card = len(me.polygons) - n_cards
    corner = [None] * len(me.loops)
    vn = [v.normal.copy() for v in me.vertices]
    for p in me.polygons:
        for li in p.loop_indices:
            if p.index >= first_card:
                corner[li] = card_normals[p.index - first_card]
            else:
                # trunk keeps its own normals; the core shades like the canopy volume
                corner[li] = vn[me.loops[li].vertex_index]
    me.normals_split_custom_set(corner)
    # material with the atlas
    atlas_path = os.path.join(ENV, "tex", f"{name}_atlas.png")
    mat = bpy.data.materials.new(f"env_{name}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 1.0
    img_node = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(atlas_path)
    img.name = f"{name}_atlas"
    img_node.image = img
    nt.links.new(img_node.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(img_node.outputs["Alpha"], bsdf.inputs["Alpha"])  # glTF alphaMode MASK
    mat.surface_render_method = "DITHERED"
    me.materials.clear()
    me.materials.append(mat)
    dst = os.path.join(OUT, "vegetation", f"{name}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=True, export_apply=True,
        export_image_format="WEBP", export_image_quality=88, export_animations=False,
        export_materials="EXPORT", export_normals=True, export_texcoords=True, export_tangents=False,
        export_yup=True,
    )
    co = np.array([v.co[:] for v in me.vertices])
    lo, hi = co.min(0), co.max(0)
    tris = tri_count(obj)
    manifest[name] = {
        "file": os.path.relpath(dst, os.path.dirname(OUT)),
        "tris": tris, "cards": len(placed),
        "size_m": [round(hi[0] - lo[0], 2), round(hi[2] - lo[2], 2), round(hi[1] - lo[1], 2)],
        "kb": round(os.path.getsize(dst) / 1024),
        "source": os.path.relpath(spec["src"], ROOT),
    }
    print("@@BUILT", name, json.dumps(manifest[name]))


if bpy is None:
    for n in SPECS:
        if len(sys.argv) < 3 or n in sys.argv[2:]:
            print(make_atlas(SPECS[n], n))
    sys.exit(0)
argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
ONLY = set(argv[1:])
manifest_path = os.path.join(OUT, "kit_manifest.json")
manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
for n in SPECS:
    if not ONLY or n in ONLY:
        build(n)
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=1, sort_keys=True)
