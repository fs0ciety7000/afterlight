"""Generated enemies (fal: Tripo meshes) on the procedural skeletons and clips of build_enemies.py.

  blender -b --factory-startup -P tools/blender/build_enemies_gen.py -- mist_wolf|stone_sentinel \
      --mesh raw.glb --albedo flat.png [--out x.glb] [--target-tris 14000]

The procedural builders (tools/blender/build_enemies.py) are run unchanged, with three Kit methods patched:
  build_rig     -> the generated mesh is imported, turned to face +Y (glTF -Z), scaled to real size,
                   and every bone joint is fitted to it (per-creature rules below) before the rig is built;
  skin_weights  -> the procedural parts are dropped; the generated mesh is welded, decimated if needed
                   and skinned (bone heat, distance-to-bone fallback), 4 influences;
  export        -> flat albedo (tools/blender/flatten_albedo.py) instead of the palette, WebP, NLA clips.
So the keyed clips (idle, run, attack, cast, hit, death) transfer as they are: they are authored
relative to the rest pose of whatever bones exist. Prints @@REPORT@@ json.
"""
import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_enemies as be  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("enemy", choices=("mist_wolf", "stone_sentinel"))
ap.add_argument("--mesh", required=True)
ap.add_argument("--albedo", required=True)
ap.add_argument("--out")
ap.add_argument("--blend")
ap.add_argument("--target-tris", type=int, default=14000)
ap.add_argument("--front", default="+X", help="axis the raw mesh faces (Tripo: +X)")
a = ap.parse_args(argv)
report = {"enemy": a.enemy}
STATE = {}


# ------------------------------------------------------------------------------------------ helpers
def import_mesh() -> bpy.types.Object:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(a.mesh))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in meshes:
        o.data.transform(o.matrix_world)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    for o in new:
        if o not in meshes:
            bpy.data.objects.remove(o)
    if len(meshes) > 1:
        with bpy.context.temp_override(active_object=meshes[0], selected_editable_objects=meshes):
            bpy.ops.object.join()
    ob = meshes[0]
    # face +Y (Blender) = glTF -Z
    turn = {"+X": 90, "-X": -90, "+Y": 0, "-Y": 180}[a.front]
    ob.data.transform(Matrix.Rotation(math.radians(turn), 4, "Z"))
    # weld UV-seam duplicates (weights and decimation would crack the seams otherwise)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    n = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    report["welded_verts"] = n - len(bm.verts)
    bm.to_mesh(ob.data)
    bm.free()
    place(ob, 1.0)
    return ob


def verts(ob):
    return [v.co.copy() for v in ob.data.vertices]


def place(ob, scale: float) -> None:
    """Uniform scale, centred on x/y, base at z = 0."""
    pts = verts(ob)
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    c = (lo + hi) / 2
    ob.data.transform(Matrix.Scale(scale, 4) @ Matrix.Translation((-c.x, -c.y, -lo.z)))


def centroid(pts):
    return sum(pts, Vector()) / len(pts) if pts else None


def section_mid_z(pts, y, half=0.04, zmin=-1.0):
    zs = [p.z for p in pts if abs(p.y - y) < half and p.z > zmin]
    return (min(zs) + max(zs)) / 2 if zs else None


def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


# ------------------------------------------------------------------------------ per-creature fitting
def fit_wolf(k, ob) -> None:
    pts = verts(ob)
    hi_z = max(p.z for p in pts)
    # back line at mid body (between the leg pairs), a little under the withers (~0.95-1.0 m)
    ys = sorted(p.y for p in pts if p.z < 0.25 * hi_z)
    mid_y = (ys[0] + ys[-1]) / 2
    back = max(p.z for p in pts if abs(p.y - mid_y) < 0.03 * (ys[-1] - ys[0]) and abs(p.x) < 0.05 * hi_z)
    s = 0.97 / back
    place(ob, s)
    pts = verts(ob)
    report["scale"] = round(s, 3)
    low = [p for p in pts if p.z < 0.32]
    mid_y = (min(p.y for p in low) + max(p.y for p in low)) / 2
    B = k.bones
    # legs: x/y of each joint from the leg column at that height
    leg_y = {}
    for leg, front in (("fl", True), ("hl", False)):
        for side, sx in (("L", 1), ("R", -1)):
            col = [p for p in pts if (p.y > mid_y) == front and p.x * sx > 0.02 and p.z < 0.55]
            names = [f"{leg}_upper_{side}", f"{leg}_lower_{side}", f"{leg}_paw_{side}"]
            joints = [B[names[0]][0], B[names[1]][0], B[names[2]][0], B[names[2]][1]]
            new = []
            for j, p in enumerate(joints):
                z = p.z if j < 3 else 0.04
                sl = [q for q in col if abs(q.z - min(z, 0.5)) < 0.04]
                c = centroid(sl) or centroid(col)
                new.append(Vector((c.x, c.y, z)))
            new[3] = Vector((new[2].x, new[2].y + (joints[3].y - joints[2].y), 0.04))
            new[0].x = new[1].x * 0.85
            leg_y[(leg, side)] = new[1].y
            B[names[0]] = (new[0], new[1], B[names[0]][2])
            B[names[1]] = (new[1], new[2], B[names[1]][2])
            B[names[2]] = (new[2], new[3], B[names[2]][2])
    fy = (leg_y[("fl", "L")] + leg_y[("fl", "R")]) / 2
    hy = (leg_y[("hl", "L")] + leg_y[("hl", "R")]) / 2
    body_pts = [p for p in pts if p.z > 0.45]
    hips = Vector((0, hy, section_mid_z(body_pts, hy, zmin=0.45)))
    chest = Vector((0, fy, section_mid_z(body_pts, fy, zmin=0.45)))
    spine = Vector((0, (hy + fy) / 2, section_mid_z(body_pts, (hy + fy) / 2, zmin=0.45)))
    nose_p = max(pts, key=lambda p: p.y)
    nose = Vector((0, nose_p.y - 0.03, nose_p.z))
    hy0 = nose.y - 0.3
    head = Vector((0, hy0, section_mid_z([p for p in pts if p.z > 0.7], hy0, zmin=0.7) or nose.z + 0.08))
    tail_p = min(pts, key=lambda p: p.y)
    t0 = Vector((0, hips.y - 0.2, section_mid_z(body_pts, hips.y - 0.2, zmin=0.45) or hips.z))
    t2 = Vector((0, tail_p.y + 0.03, tail_p.z))
    tm = (t0 + t2) / 2
    tm.z = section_mid_z([p for p in pts if p.y < t0.y], tm.y, half=0.05) or tm.z
    B["hips"] = (hips, spine, "root")
    B["spine"] = (spine, chest, "hips")
    B["neck"] = (chest, head, "spine")
    B["head"] = (head, nose, "neck")
    B["tail1"] = (t0, tm, "hips")
    B["tail2"] = (tm, t2, "tail1")
    for n in ("fl_upper_L", "fl_upper_R"):
        h, t, _ = B[n]
        B[n] = (h, t, "spine")


def fit_sentinel(k, ob) -> None:
    pts = verts(ob)
    hi_z = max(p.z for p in pts)
    place(ob, 2.2 / hi_z)
    report["scale"] = round(2.2 / hi_z, 3)
    pts = verts(ob)
    B = k.bones
    half_w = max(abs(p.x) for p in pts)
    for side, sx in (("L", 1), ("R", -1)):
        # legs: column under the hips, between the fists
        leg = [p for p in pts if p.z < 0.55 and 0.05 < p.x * sx < 0.55 * half_w]
        c_low = centroid([p for p in leg if p.z < 0.3]) or Vector((0.3 * sx, 0, 0))
        c_knee = centroid([p for p in leg if 0.4 < p.z < 0.55]) or c_low
        hip = Vector((c_knee.x, c_knee.y, B[f"thigh_{side}"][0].z))
        knee = Vector((c_knee.x, c_knee.y, 0.68))
        ankle = Vector((c_low.x, c_low.y, 0.05))
        B[f"thigh_{side}"] = (hip, knee, "hips")
        B[f"shin_{side}"] = (knee, ankle, f"thigh_{side}")
        # arms: outermost columns; fist = lowest arm part, elbow at ~1.25 m
        arm = [p for p in pts if p.x * sx > 0.6 * half_w and p.z > 0.35]
        fist = centroid([p for p in arm if p.z < min(q.z for q in arm) + 0.3]) or B[f"forearm_{side}"][1]
        elbow = centroid([p for p in arm if 1.15 < p.z < 1.35]) or B[f"forearm_{side}"][0]
        top = max((p for p in arm), key=lambda p: p.z)
        shoulder = Vector((elbow.x * 0.92, elbow.y, min(top.z - 0.15, 1.85)))
        B[f"upper_arm_{side}"] = (shoulder, Vector(elbow), "torso")
        B[f"forearm_{side}"] = (Vector(elbow), Vector(fist), f"upper_arm_{side}")
    head_pts = [p for p in pts if p.z > 1.95 and abs(p.x) < 0.3]
    hc = centroid(head_pts) or Vector((0, 0, 2.0))
    torso_y = centroid([p for p in pts if 1.2 < p.z < 1.7 and abs(p.x) < 0.3]).y
    B["hips"] = (Vector((0, torso_y, 1.05)), Vector((0, torso_y, 1.3)), "root")
    B["torso"] = (Vector((0, torso_y, 1.3)), Vector((hc.x * 0.5, (torso_y + hc.y) / 2, 1.85)), "hips")
    B["head"] = (Vector((hc.x * 0.5, (torso_y + hc.y) / 2, 1.85)), Vector((hc.x, hc.y, 2.2)), "torso")


FITTERS = {"mist_wolf": fit_wolf, "stone_sentinel": fit_sentinel}


# ------------------------------------------------------------------------------------- Kit patches
orig_build_rig = be.Kit.build_rig


def build_rig(self):
    ob = import_mesh()
    STATE["mesh"] = ob
    FITTERS[self.name](self, ob)
    report["bones_fitted"] = {n: [round(x, 3) for x in h] + [round(x, 3) for x in t]
                              for n, (h, t, _) in self.bones.items()}
    orig_build_rig(self)


def segment_weights(ob, kit) -> None:
    segs = {n: (h, t) for n, (h, t, _) in kit.bones.items() if n != "root"}
    for v in ob.data.vertices:
        d = []
        for n, (h, t) in segs.items():
            ab = t - h
            kk = max(0.0, min(1.0, (v.co - h).dot(ab) / max(ab.length_squared, 1e-9)))
            d.append(((v.co - (h + ab * kk)).length, n))
        d.sort()
        near = d[:3]
        w = [1.0 / (x + 0.02) ** 4 for x, _ in near]
        s = sum(w)
        for (x, n), wi in zip(near, w):
            if wi / s > 0.02:
                ob.vertex_groups[n].add([v.index], wi / s, "REPLACE")


def skin_weights(self):
    for obj, _, _ in self.parts:
        bpy.data.objects.remove(obj)
    self.parts.clear()
    ob = STATE["mesh"]
    ob.name = self.name
    report["tris_in"] = tri_count(ob)
    if report["tris_in"] > a.target_tris * 1.05:
        mod = ob.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = a.target_tris / report["tris_in"]
        mod.use_collapse_triangulate = True
        with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    report["tris"] = tri_count(ob)
    for n in self.bones:
        if n not in ob.vertex_groups:
            ob.vertex_groups.new(name=n)
    if os.environ.get("ENEMY_WEIGHTS") == "distance":
        segment_weights(ob, self)
        report["weights"] = "distance"
    else:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        self.rig.select_set(True)
        bpy.context.view_layer.objects.active = self.rig
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        root = ob.vertex_groups.get("root")
        if root:
            ob.vertex_groups.remove(root)
            ob.vertex_groups.new(name="root")
        empty = sum(1 for v in ob.data.vertices if not any(g.weight > 1e-4 for g in v.groups))
        report["heat_unweighted"] = empty
        if empty > 0.01 * len(ob.data.vertices):
            for vg in ob.vertex_groups:
                vg.remove(list(range(len(ob.data.vertices))))
            segment_weights(ob, self)
            report["weights"] = "distance (heat failed)"
        else:
            if empty:  # a few strays: nearest bone
                stray = [v for v in ob.data.vertices if not any(g.weight > 1e-4 for g in v.groups)]
                for v in stray:
                    best = min(((v.co - (h + (t - h) * max(0.0, min(1.0, (v.co - h).dot(t - h)
                                / max((t - h).length_squared, 1e-9))))).length, n)
                               for n, (h, t, _) in self.bones.items() if n != "root")
                    ob.vertex_groups[best[1]].add([v.index], 1.0, "REPLACE")
            report["weights"] = "heat"
    # 4 influences, normalised
    for v in ob.data.vertices:
        gs = sorted(((g.group, g.weight) for g in v.groups), key=lambda kv: -kv[1])
        keep = gs[:4]
        s = sum(w for _, w in keep) or 1.0
        for g, _ in gs:
            ob.vertex_groups[g].remove([v.index])
        for g, w in keep:
            ob.vertex_groups[g].add([v.index], w / s, "REPLACE")
    ob.modifiers.clear()
    mod = ob.modifiers.new("arm", "ARMATURE")
    mod.object = self.rig
    ob.parent = self.rig
    ob.matrix_parent_inverse = self.rig.matrix_world.inverted()
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def export(self, body, extra_report=None):
    img = bpy.data.images.load(os.path.abspath(a.albedo))
    img.name = f"{self.name}_albedo"
    mat = bpy.data.materials.new(f"{self.name}_flat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    body.data.materials.clear()
    body.data.materials.append(mat)
    for o in list(bpy.data.objects):
        if o not in (body, self.rig):
            bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    zmin = min((body.matrix_world @ v.co).z for v in body.data.vertices)
    self.rig.location.z -= zmin
    bpy.context.view_layer.update()
    for name, act in self.clips.items():
        tr = self.rig.animation_data.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, int(act.frame_range[0]), act)
        if act.slots:
            st.action_slot = act.slots[0]
        tr.mute = True
    dst = os.path.abspath(a.out or os.path.join(be.OUT, self.name, f"{self.name}.glb"))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.blend or os.path.join(be.SRC, f"{self.name}_gen.blend")))
    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=False,
        export_animation_mode="NLA_TRACKS", export_anim_slide_to_zero=True, export_force_sampling=True,
        export_optimize_animation_size=True, export_skins=True, export_influence_nb=4,
        export_morph=False, export_apply=False, export_yup=True, export_image_format="WEBP",
        export_image_quality=88, export_texcoords=True, export_normals=True, export_tangents=False,
        export_materials="EXPORT", export_cameras=False, export_lights=False)
    pts = [body.matrix_world @ v.co for v in body.data.vertices]
    report.update({
        "tris": tri_count(body), "bones": len(self.bones), "glb_kb": round(os.path.getsize(dst) / 1024),
        "size_m": [round(max(p[i] for p in pts) - min(p[i] for p in pts), 2) for i in range(3)],
        "base_z": round(min(p.z for p in pts), 4),
        "clips": {n: round((ac.frame_range[1] - ac.frame_range[0]) / be.FPS, 2) for n, ac in self.clips.items()},
        "out": dst,
    })
    print("@@REPORT@@" + json.dumps(report))
    return report


be.Kit.build_rig = build_rig
be.Kit.skin_weights = skin_weights
be.Kit.export = export
be.BUILDERS[a.enemy]()
