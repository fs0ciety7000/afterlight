"""Box-kit helpers shared by the hand-built environment pieces (build_mire_props.py,
build_cloister_props.py): planar-UV boxes, prisms and wedges on the village props atlas, GLB export.

Atlas: art/source/env/tex/village_props_atlas.png (Blender UV, origin bottom-left): stone (0, .5),
wood (.5, .5), terracotta (0, 0, left half), dark soil / iron (.25, 0). Front = +Z in glTF (-Y here).
"""
import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ATLAS = os.path.join(ROOT, "art", "source", "env", "tex", "village_props_atlas.png")
STONE, WOOD = (0.0, 0.5, 0.5, 0.5), (0.5, 0.5, 0.5, 0.5)  # u0, v0, du, dv
TILE, IRON = (0.02, 0.04, 0.2, 0.34), (0.29, 0.06, 0.17, 0.38)  # inset: no mip bleed
UV_QUAD = ((0.05, 0.05), (0.95, 0.05), (0.95, 0.95), (0.05, 0.95))


def _quad(bm, uvl, pts, region, uv=UV_QUAD):
    f = bm.faces.new([bm.verts.new(p) for p in pts])
    for lp, (uu, vv) in zip(f.loops, uv):
        lp[uvl].uv = (region[0] + uu * region[2], region[1] + vv * region[3])
    return f


def box(bm, uvl, c, size, region, top_scale=1.0, tilt=0.0, top_sx=None, yaw=0.0, roll=0.0):
    """Frustum box from z = c.z up (top face scaled; `top_sx` scales its x only, 0 -> wedge);
    each face fills the atlas region (planar). `tilt` rolls the box around Y, `roll` around X and
    `yaw` turns it around Z, all about its base centre."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2]
    tsx = top_scale if top_sx is None else top_sx
    bot = [Vector((sx * hx, sy * hy, 0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    top = [Vector((sx * hx * tsx, sy * hy * top_scale, hz)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]

    def place(p):
        q = Vector((p.x * math.cos(tilt) + p.z * math.sin(tilt), p.y, -p.x * math.sin(tilt) + p.z * math.cos(tilt)))
        q = Vector((q.x, q.y * math.cos(roll) - q.z * math.sin(roll), q.y * math.sin(roll) + q.z * math.cos(roll)))
        q = Vector((q.x * math.cos(yaw) - q.y * math.sin(yaw), q.x * math.sin(yaw) + q.y * math.cos(yaw), q.z))
        return Vector(c) + q

    bot = [place(p) for p in bot]
    top = [place(p) for p in top]
    faces = [top, [bot[3], bot[2], bot[1], bot[0]], [bot[0], bot[1], top[1], top[0]],
             [bot[1], bot[2], top[2], top[1]], [bot[2], bot[3], top[3], top[2]], [bot[3], bot[0], top[0], top[3]]]
    for k, quad in enumerate(faces):
        if k == 0 and tsx == 0.0:
            continue  # wedge: the top collapses to a ridge line
        if tsx == 0.0:
            quad = [p for i, p in enumerate(quad) if i == 0 or (quad[i] - quad[i - 1]).length > 1e-5]
            if len(quad) == 4 and (quad[0] - quad[3]).length < 1e-5:
                quad = quad[:3]
            if len(quad) == 3:
                f = bm.faces.new([bm.verts.new(p) for p in quad])
                for lp, (uu, vv) in zip(f.loops, ((0.05, 0.05), (0.95, 0.05), (0.5, 0.95))):
                    lp[uvl].uv = (region[0] + uu * region[2], region[1] + vv * region[3])
                continue
        _quad(bm, uvl, quad, region)


def prism(bm, uvl, c, radius, height, sides, region, top_scale=1.0, phase=0.0, cap=True):
    """Upright n-gon prism from z = c.z; side faces fill the region, top/bottom caps as fans."""
    ring_b = [Vector((math.cos(phase + k * math.tau / sides) * radius, math.sin(phase + k * math.tau / sides) * radius, 0))
              for k in range(sides)]
    ring_t = [Vector((p.x * top_scale, p.y * top_scale, height)) for p in ring_b]
    c = Vector(c)
    for k in range(sides):
        a, b = ring_b[k], ring_b[(k + 1) % sides]
        at, bt = ring_t[k], ring_t[(k + 1) % sides]
        _quad(bm, uvl, [c + a, c + b, c + bt, c + at], region)
    if cap:
        for ring, up in ((ring_t, True), (ring_b, False)):
            centre = c + Vector((0, 0, height if up else 0))
            rr = radius * (top_scale if up else 1.0)  # keep the cap inside its atlas region
            for k in range(sides):
                a, b = c + ring[k], c + ring[(k + 1) % sides]
                tri = [centre, a, b] if up else [centre, b, a]
                f = bm.faces.new([bm.verts.new(p) for p in tri])
                for lp, p in zip(f.loops, tri):
                    lp[uvl].uv = (region[0] + (0.5 + 0.45 * (p.x - centre.x) / rr) * region[2],
                                  region[1] + (0.5 + 0.45 * (p.y - centre.y) / rr) * region[3])


def finish(name: str, bm, out_dir: str, sub: str = "props", merge: bool = True) -> None:
    import bmesh

    if merge:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
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
    os.makedirs(os.path.join(out_dir, sub), exist_ok=True)
    dst = os.path.join(out_dir, sub, f"{name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=True, export_apply=True,
        export_image_format="WEBP", export_image_quality=88, export_animations=False,
        export_materials="EXPORT", export_normals=True, export_texcoords=True, export_tangents=False,
        export_yup=True,
    )
    me.calc_loop_triangles()
    d = obj.dimensions
    print("@@BUILT", name, len(me.loop_triangles), "tris", os.path.getsize(dst) // 1024, "KB",
          "dims %.2f x %.2f x %.2f" % (d.x, d.y, d.z))
