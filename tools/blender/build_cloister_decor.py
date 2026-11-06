"""Silent Dial Cloister set pieces (fal lot art/source/LOT_2026-11-06_decor.md) and the painted floor dial.

  blender -b --factory-startup -P tools/blender/build_cloister_decor.py -- art/source/env/silent_dial_cloister/decor \
      assets/environment [names...]

Generated pieces (Tripo h3.1 on our own concept sheet, decor/raw/<name>/<name>_tripo_0.glb): join, drop specks,
scale to real size, decimate to the budget, pivot at the ground centre, one material with the base colour
resized (1K or 512 px, JPEG in the GLB), front = +Z (glTF). Exported to assets/environment/ruins/<name>.glb
for the kit (game/world/prototype/location_builder.gd KIT).

dial: the 24 m floor dial stopped at three o'clock, rebuilt from the painted dial texture (decor/dial_tex.png:
engraved roman hour marks, minute ticks, ornament band; XII to the north) on a low stone disc, with raised
bronze hands (minute hand to XII / north, hour hand to III / east) and a bronze centre cap. The hands sample a
bronze swatch painted into a corner of the same texture, so the dial stays one mesh and one material.
Prints @@BUILT lines (tris, KB, dimensions in glTF axes x, y up, z).
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

# name: (size axis "h" height / "l" longest horizontal side, metres, max tris, texture px, yaw degrees: Tripo
# faces its fronts to Blender +X, -90 turns them to -Y = glTF +Z)
PIECES = {
    "clock_tower": ("h", 15.0, 6000, 1024, -90),
    "broken_arch": ("h", 6.6, 4000, 1024, -90),
    "fallen_column": ("l", 4.6, 2500, 512, -90),
    "watcher_statue": ("h", 3.3, 4000, 512, -90),
    "dial_altar": ("h", 1.6, 2500, 512, -90),
    "cloister_bell": ("h", 3.4, 3000, 512, -90),
}
DIAL_R = 12.2  # metres (docs/content/dungeon.md 2.4: floor dial of 24 m)
DIAL_UV_R = 0.475  # radius of the carved circle in the painted texture (measured on dial_tex.png)
BRONZE_UV = (0.01, 0.01, 0.11, 0.11)  # u0, v0, du, dv of the painted bronze swatch (Blender UV)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tris(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def export(ob, dst):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=True, export_apply=True,
        export_image_format="JPEG", export_jpeg_quality=86, export_animations=False,
        export_materials="EXPORT", export_normals=True, export_texcoords=True, export_tangents=False,
        export_yup=True,
    )
    d = ob.dimensions
    print("@@BUILT", os.path.basename(dst), tris(ob), "tris", os.path.getsize(dst) // 1024, "KB",
          "dims %.2f x %.2f x %.2f" % (d.x, d.z, d.y))


def material(name, img):
    mat = bpy.data.materials.new(f"env_{name}")
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def build_piece(src_dir, out_dir, name):
    axis, size, max_tris, px, yaw = PIECES[name]
    src = os.path.join(src_dir, "raw", name, f"{name}_tripo_0.glb")
    if not os.path.exists(src):
        print("missing", src)
        return
    reset()
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    img = next(i for i in bpy.data.images if i.size[0] > 0)
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    with bpy.context.temp_override(active_object=meshes[0], selected_editable_objects=meshes,
                                   selected_objects=meshes):
        if len(meshes) > 1:
            bpy.ops.object.join()
    ob = meshes[0]
    ob.name = name
    ob.parent = None
    ob.rotation_mode = "XYZ"
    ob.rotation_euler.z += math.radians(yaw)
    with bpy.context.temp_override(active_object=ob, selected_editable_objects=[ob], selected_objects=[ob]):
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # drop specks (islands under 0.2 % of the faces)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.faces.ensure_lookup_table()
    seen, drop = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            isl.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        if len(isl) < max(8, len(bm.faces) * 0.002):
            drop += isl
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    # real size, pivot at the footprint centre on the ground
    co = [v.co.copy() for v in ob.data.vertices]
    lo = Vector([min(c[i] for c in co) for i in range(3)])
    hi = Vector([max(c[i] for c in co) for i in range(3)])
    dims = hi - lo
    k = size / (dims.z if axis == "h" else max(dims.x, dims.y))
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in ob.data.vertices:
        v.co = (v.co - centre) * k
    ob.data.update()
    raw = tris(ob)
    if raw > max_tris:
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.ratio = max_tris / raw
        mod.use_collapse_triangulate = True
        with bpy.context.temp_override(object=ob, active_object=ob):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.set_sharp_from_angle(angle=math.radians(50))
    while len(ob.data.uv_layers) > 1:
        ob.data.uv_layers.remove(ob.data.uv_layers[-1])
    for ca in list(ob.data.color_attributes):
        ob.data.color_attributes.remove(ca)
    img.scale(px, px)
    img.name = f"{name}_albedo"
    ob.data.materials.clear()
    ob.data.materials.append(material(name, img))
    export(ob, os.path.join(out_dir, "ruins", f"{name}.glb"))


def _dial_texture(src_dir):
    """dial_tex.png with a bronze swatch painted in its top-left corner (outside the carved circle)."""
    img = bpy.data.images.load(os.path.join(src_dir, "dial_tex.png"))
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    u0, v0, du, dv = BRONZE_UV
    x0, x1 = int(u0 * w), int((u0 + du) * w)
    y0, y1 = int(v0 * h), int((v0 + dv) * h)  # rows from the bottom, as UVs
    t = np.linspace(0.0, 1.0, y1 - y0)[:, None] * np.ones((1, x1 - x0))
    xx = np.linspace(0.0, 1.0, x1 - x0)[None, :]
    patina = np.clip(0.5 + 0.5 * np.sin(xx * 23.0 + t * 7.0) * np.sin(t * 17.0 - xx * 5.0), 0.0, 1.0) ** 3
    bronze = np.stack([0.30 + 0.25 * t, 0.17 + 0.19 * t, 0.06 + 0.08 * t], axis=-1)  # aged bronze, linear
    green = np.array([0.16, 0.30, 0.24])
    px[y0:y1, x0:x1, :3] = bronze * (1.0 - 0.45 * patina[..., None]) + green * 0.45 * patina[..., None]
    px[y0:y1, x0:x1, 3] = 1.0
    img.pixels.foreach_set(px.ravel())
    img.name = "dial_albedo"
    img.pack()
    return img


def _flat_poly(bm, uvl, pts, z0, z1, uv_of):
    """Prism over a convex-ish 2D outline (counter-clockwise), top at z1, sides down to z0."""
    top = [bm.verts.new((x, y, z1)) for x, y in pts]
    bot = [bm.verts.new((x, y, z0)) for x, y in pts]
    faces = [bm.faces.new(top)]
    n = len(pts)
    for k in range(n):
        faces.append(bm.faces.new([bot[k], bot[(k + 1) % n], top[(k + 1) % n], top[k]]))
    for f in faces:
        for lp in f.loops:
            lp[uvl].uv = uv_of(lp.vert.co)


def build_dial_mesh(src_dir, out_dir):
    reset()
    img = _dial_texture(src_dir)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")

    def dial_uv(co):
        return (0.5 + co.x / DIAL_R * DIAL_UV_R, 0.5 + co.y / DIAL_R * DIAL_UV_R)

    def bronze_uv(co):
        u0, v0, du, dv = BRONZE_UV
        return (u0 + du * (0.5 + 0.4 * math.sin(co.x * 3.1)), v0 + dv * (0.5 + 0.4 * math.cos(co.y * 2.3)))

    # stone disc: top at 4 cm, chamfered lip down to the paving (no bottom face: it lies on the floor)
    seg = 64
    c = bm.verts.new((0, 0, 0.04))
    ring = [bm.verts.new((math.cos(a) * DIAL_R, math.sin(a) * DIAL_R, 0.04))
            for a in (k * math.tau / seg for k in range(seg))]
    foot = [bm.verts.new((math.cos(a) * (DIAL_R + 0.12), math.sin(a) * (DIAL_R + 0.12), -0.02))
            for a in (k * math.tau / seg for k in range(seg))]
    for k in range(seg):
        f = bm.faces.new([c, ring[k], ring[(k + 1) % seg]])
        for lp in f.loops:
            lp[uvl].uv = dial_uv(lp.vert.co)
        f = bm.faces.new([ring[k], foot[k], foot[(k + 1) % seg], ring[(k + 1) % seg]])
        for lp in f.loops:
            q = lp.vert.co * (DIAL_R / max(lp.vert.co.length, 1e-6))
            lp[uvl].uv = dial_uv(q)
    # hands (Blender +Y = glTF -Z = north): minute hand to XII, hour hand to III (east, +X); spade tips
    minute = [(0.0, 9.6), (-0.55, 8.4), (-0.18, 8.2), (-0.26, 0.0), (-0.5, -1.6), (0.0, -2.2), (0.5, -1.6),
              (0.26, 0.0), (0.18, 8.2), (0.55, 8.4)]
    hour = [(6.6, 0.0), (5.5, 0.75), (5.4, 0.25), (0.0, 0.42), (-1.2, 0.7), (-1.6, 0.0), (-1.2, -0.7),
            (0.0, -0.42), (5.4, -0.25), (5.5, -0.75)]
    for pts, z1 in ((minute, 0.09), (hour, 0.11)):
        pts = list(reversed(pts)) if _area(pts) < 0 else pts
        # split into a fan of convex quads/tris around the hand's axis so no face is concave
        _hand(bm, uvl, pts, 0.03, z1, bronze_uv)
    # centre cap
    cap = [(math.cos(a) * 0.95, math.sin(a) * 0.95) for a in (k * math.tau / 12 for k in range(12))]
    _flat_poly(bm, uvl, cap, 0.03, 0.14, bronze_uv)  # low: Morvaine stands on it
    knob = [(math.cos(a) * 0.4, math.sin(a) * 0.4) for a in (k * math.tau / 8 for k in range(8))]
    _flat_poly(bm, uvl, knob, 0.14, 0.19, bronze_uv)
    bm.normal_update()
    me = bpy.data.meshes.new("dial")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("dial", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(material("dial", img))
    export(ob, os.path.join(out_dir, "ruins", "dial.glb"))


def _area(pts):
    return sum(pts[k][0] * pts[(k + 1) % len(pts)][1] - pts[(k + 1) % len(pts)][0] * pts[k][1]
               for k in range(len(pts))) / 2


def _hand(bm, uvl, pts, z0, z1, uv_of):
    """Closed slab over a concave outline: top and bottom triangulated by ear clipping."""
    top = [bm.verts.new((x, y, z1)) for x, y in pts]
    bot = [bm.verts.new((x, y, z0)) for x, y in pts]
    faces = []
    for tri in _ears(pts):
        faces.append(bm.faces.new([top[i] for i in tri]))
        faces.append(bm.faces.new([bot[i] for i in reversed(tri)]))
    n = len(pts)
    for k in range(n):
        faces.append(bm.faces.new([bot[k], bot[(k + 1) % n], top[(k + 1) % n], top[k]]))
    for f in faces:
        for lp in f.loops:
            lp[uvl].uv = uv_of(lp.vert.co)


def _ears(pts):
    idx = list(range(len(pts)))
    out = []

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        return cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0

    guard = 0
    while len(idx) > 3 and guard < 500:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if cross(a, b, c) <= 0:
                continue
            if any(inside(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            out.append((i0, i1, i2))
            idx.pop(k)
            break
    out.append(tuple(idx))
    return out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    src_dir, out_dir = os.path.abspath(argv[0]), os.path.abspath(argv[1])
    only = set(argv[2:])
    for n in PIECES:
        if not only or n in only:
            build_piece(src_dir, out_dir, n)
    if not only or "dial" in only:
        build_dial_mesh(src_dir, out_dir)
