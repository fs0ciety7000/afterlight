"""Static Aubelin NPC from a Tripo image-to-3d mesh (no rig): clean, orient, scale, flat albedo, GLB.

  blender -b --factory-startup -P tools/blender/build_npcs.py -- odile --mesh raw.glb --albedo flat.png \
      --height 1.58 [--out assets/models/npcs/odile.glb] [--target-tris 12000] [--yaw auto|<deg>]

- the raw mesh faces +X (Tripo); it is turned to face --facing (glTF axis, default +Z = Blender -Y): the lot
  brief asks for +Z, which faces the default 3/4 camera (it sits on +Z) with no rotation. Fern and the
  enemies face -Z (Godot forward): to turn an NPC like them, add PI to its yaw (or build with --facing -Z);
- the concept is a front 3/4 view, so Tripo leaves the body yawed a little: with --yaw auto the shoulder line
  (principal axis of the vertices at 72-80 % of the height) is turned onto X (correction within +-45 deg);
- welded, degenerate faces dissolved, loose verts dropped, decimated to --target-tris if above it;
- scaled to --height (metres), origin centred under the feet (verts below 6 % of the height), base at z = 0;
- one material, flat albedo (tools/blender/flatten_albedo.py) exported as WebP: toon.gdshader is applied
  at run time (Toon.apply), so the GLB carries only the base colour.
Prints @@REPORT@@ json (tris, size, yaw, glb size).
"""
import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_point_tri

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("npc")
ap.add_argument("--mesh", required=True)
ap.add_argument("--albedo", required=True)
ap.add_argument("--height", type=float, required=True)
ap.add_argument("--out")
ap.add_argument("--target-tris", type=int, default=12000)
ap.add_argument("--yaw", default="auto")
ap.add_argument("--facing", default="+Z", choices=("+Z", "-Z"))
a = ap.parse_args(argv)
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
report = {"npc": a.npc}

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(a.mesh))
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    o.data.transform(o.matrix_world)
    o.parent = None
    o.matrix_world = Matrix.Identity(4)
for o in list(bpy.data.objects):
    if o not in meshes:
        bpy.data.objects.remove(o)
if len(meshes) > 1:
    with bpy.context.temp_override(active_object=meshes[0], selected_editable_objects=meshes):
        bpy.ops.object.join()
ob = meshes[0]
ob.name = a.npc
ob.data.name = a.npc
ob.data.transform(Matrix.Rotation(math.radians(-90 if a.facing == "+Z" else 90), 4, "Z"))  # +X -> -Y or +Y

# clean-up
bm = bmesh.new()
bm.from_mesh(ob.data)
n = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context="VERTS")
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
report["welded_verts"] = n - len(bm.verts)
bm.to_mesh(ob.data)
bm.free()


def pts():
    return [v.co.copy() for v in ob.data.vertices]


def bounds(p):
    return (Vector([min(q[i] for q in p) for i in range(3)]), Vector([max(q[i] for q in p) for i in range(3)]))


# yaw: shoulder line onto X
lo, hi = bounds(pts())
H = hi.z - lo.z
if a.yaw == "auto":
    band = [q for q in pts() if lo.z + 0.72 * H < q.z < lo.z + 0.80 * H]
    mx = sum(q.x for q in band) / len(band)
    my = sum(q.y for q in band) / len(band)
    sxx = sum((q.x - mx) ** 2 for q in band)
    syy = sum((q.y - my) ** 2 for q in band)
    sxy = sum((q.x - mx) * (q.y - my) for q in band)
    theta = 0.5 * math.atan2(2 * sxy, sxx - syy)  # major axis angle from X
    theta = (theta + math.pi / 4) % (math.pi / 2) - math.pi / 4
    yaw = -theta
    report["shoulder_ratio"] = round(math.sqrt(max(sxx, syy) / max(min(sxx, syy), 1e-9)), 2)
else:
    yaw = math.radians(float(a.yaw))
ob.data.transform(Matrix.Rotation(yaw, 4, "Z"))
report["yaw_deg"] = round(math.degrees(yaw), 1)

# decimate
ob.data.calc_loop_triangles()
report["tris_in"] = len(ob.data.loop_triangles)
if report["tris_in"] > a.target_tris * 1.05:
    mod = ob.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = a.target_tris / report["tris_in"]
    mod.use_collapse_triangulate = True
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier=mod.name)

# coplanar overlaps left by the collapse (z-fighting, same test as blender-asset-qa with eps = 1 mm):
# also folds onto a neighbour; the smaller tri of each same-facing pair goes
bm = bmesh.new()
bm.from_mesh(ob.data)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.faces.ensure_lookup_table()
bm.normal_update()
eps = 0.001 * H / a.height
bvh = BVHTree.FromBMesh(bm)
dead = set()
for f in bm.faces:
    if f.index in dead or f.normal.length < 0.5:
        continue
    vs = [v.co for v in f.verts]
    cen = sum(vs, Vector()) / 3
    for p in (cen, cen.lerp(vs[0], .6), cen.lerp(vs[1], .6), cen.lerp(vs[2], .6)):
        for _, _, j, _ in bvh.find_nearest_range(p, eps):
            if j is None or j == f.index or j in dead:
                continue
            g = bm.faces[j]
            if f.normal.dot(g.normal) < 0.999:
                continue
            ga, gb, gc = (v.co for v in g.verts)
            q = p - g.normal * g.normal.dot(p - ga)
            if not intersect_point_tri(q, ga, gb, gc):
                continue
            dead.add(min((f, g), key=lambda x: x.calc_area()).index)
bmesh.ops.delete(bm, geom=[bm.faces[i] for i in dead], context="FACES_ONLY")
report["overlaps_removed"] = len(dead)
bm.to_mesh(ob.data)
bm.free()

# scale and place: feet centre at the origin, base at z = 0
lo, hi = bounds(pts())
s = a.height / (hi.z - lo.z)
ob.data.transform(Matrix.Scale(s, 4))
lo, hi = bounds(pts())
feet = [q for q in pts() if q.z < lo.z + 0.06 * a.height]
flo, fhi = bounds(feet)
c = (flo + fhi) / 2
ob.data.transform(Matrix.Translation((-c.x, -c.y, -lo.z)))
for p in ob.data.polygons:
    p.use_smooth = True

# flat albedo material
img = bpy.data.images.load(os.path.abspath(a.albedo))
img.name = f"{a.npc}_albedo"
mat = bpy.data.materials.new(f"{a.npc}_flat")
mat.use_nodes = True
nt = mat.node_tree
bsdf = next(nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED")
bsdf.inputs["Roughness"].default_value = 1.0
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Specular IOR Level"].default_value = 0.0
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
ob.data.materials.clear()
ob.data.materials.append(mat)
while len(ob.data.uv_layers) > 1:
    ob.data.uv_layers.remove(ob.data.uv_layers[-1])

dst = os.path.abspath(a.out or os.path.join(ROOT, "assets", "models", "npcs", f"{a.npc}.glb"))
os.makedirs(os.path.dirname(dst), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=dst, export_format="GLB", use_selection=False, export_animations=False, export_skins=False,
    export_morph=False, export_apply=False, export_yup=True, export_image_format="WEBP", export_image_quality=88,
    export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
    export_cameras=False, export_lights=False)
ob.data.calc_loop_triangles()
p = pts()
lo, hi = bounds(p)
report.update({
    "tris": len(ob.data.loop_triangles), "scale": round(s, 3), "glb_kb": round(os.path.getsize(dst) / 1024),
    "size_m": [round(hi[i] - lo[i], 2) for i in range(3)], "base_z": round(lo.z, 4),
    "texture": list(img.size), "out": dst,
})
print("@@REPORT@@" + json.dumps(report))
