"""Milestone 3 enemies, built procedurally in Blender (no fal call): mesh, flat-colour palette texture,
armature, keyframed clips, GLB.

  blender -b --factory-startup -P tools/blender/build_enemies.py -- [mist_wolf wandering_lantern ...]

Why procedural: the fal account ran out of balance during the A/B test (2026-11-06), so the Meshy /
Tripo generations planned for the enemies could not run (see art/source/enemies/AB_TEST.md). These
models follow the full game contract and can be swapped for generated ones later without code changes.

Contract (docs/CONTENT_PIPELINE.md, DESIGN.md): real-world scale, base at y = 0, facing glTF -Z
(Blender +Y), flat colours only (one 1K WebP palette texture, one cell per colour), clips named
idle, run, attack, cast, hit, death (+ phase for the boss), exported as NLA tracks at 24 fps.
Writes assets/models/enemies/<id>/<id>.glb, art/source/enemies/<id>.blend, prints @@REPORT@@ json.

Authoring conventions used by the clip tables below:
  pose = {bone: (rx, ry, rz)} or {bone: (rx, ry, rz, (lx, ly, lz))} or with a 5th item = uniform scale.
  Rotations in degrees about ARMATURE axes (X = right, Y = forward, Z = up), applied relative to the
  parent in its rest orientation; locations in metres, also in armature axes.
  For a bone hanging down (legs), +rx swings the lower end forwards; for a bone pointing forwards
  (spine, neck, head), +rx lifts the front end.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "enemies")
SRC = os.path.join(ROOT, "art", "source", "enemies")
FPS = 24
GRID = 8  # palette cells per side (128 px each in the 1K texture)


# ----------------------------------------------------------------------------------------- helpers
class Kit:
    """Collects mesh parts, colours, bones and clips for one enemy."""

    def __init__(self, name: str, palette: dict):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = FPS
        self.name = name
        self.palette = palette
        self.colour_index = {k: i for i, k in enumerate(palette)}
        self.parts = []  # (object, rigid bone or None, bones for segment weights)
        self.bones = {}  # name: (head, tail, parent)
        self.rig = None
        self.clips = {}

    # --- colours
    def uv_of(self, colour: str) -> tuple:
        i = self.colour_index[colour]
        cx, cy = i % GRID, i // GRID
        return ((cx + 0.5) / GRID, 1.0 - (cy + 0.5) / GRID)

    def paint(self, obj, fn) -> None:
        """fn(face_centre: Vector, normal: Vector) -> colour name, per face."""
        me = obj.data
        if not me.uv_layers:
            me.uv_layers.new(name="UVMap")
        uv = me.uv_layers.active.data
        for p in me.polygons:
            u = self.uv_of(fn(obj.matrix_world @ p.center, p.normal))
            for li in p.loop_indices:
                uv[li].uv = u

    def palette_image(self) -> bpy.types.Image:
        size = 1024
        cell = size // GRID
        px = np.zeros((size, size, 4), dtype=np.float32)
        px[..., 3] = 1.0
        for name, i in self.colour_index.items():
            h = self.palette[name].lstrip("#")
            rgb = [int(h[k:k + 2], 16) / 255.0 for k in (0, 2, 4)]
            cx, cy = i % GRID, i // GRID
            y0 = size - (cy + 1) * cell  # Blender pixel rows start at the bottom
            px[y0:y0 + cell, cx * cell:(cx + 1) * cell, :3] = rgb
        img = bpy.data.images.new(f"{self.name}_palette", size, size)
        img.pixels[:] = px.ravel()
        path = os.path.join(SRC, f"{self.name}_palette.png")
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        img.filepath = path
        img.reload()
        return img

    # --- meshes
    def add(self, obj, bone: str = None, segs: list = None):
        self.parts.append((obj, bone, segs))
        return obj

    def link(self, name: str, me) -> bpy.types.Object:
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj

    def skin(self, name: str, pts: list, edges: list, radii: list, subsurf: int = 1,
             flat: dict = None) -> bpy.types.Object:
        """Skin-modifier tube network. flat: {vertex index: (rx, ry)} for elliptic sections."""
        me = bpy.data.meshes.new(name)
        me.from_pydata([Vector(p) for p in pts], edges, [])
        obj = self.link(name, me)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        mod = obj.modifiers.new("skin", "SKIN")
        mod.use_smooth_shade = True
        for i, r in enumerate(radii):
            rr = flat.get(i, (r, r)) if flat else (r, r)
            me.skin_vertices[0].data[i].radius = rr
        me.skin_vertices[0].data[0].use_root = True
        bpy.ops.object.modifier_apply(modifier="skin")
        if subsurf:
            sub = obj.modifiers.new("sub", "SUBSURF")
            sub.levels = subsurf
            bpy.ops.object.modifier_apply(modifier="sub")
        for p in obj.data.polygons:
            p.use_smooth = True
        obj.select_set(False)
        return obj

    def prim(self, name: str, kind: str, loc, scale=(1, 1, 1), rot=(0, 0, 0), seg: int = 12,
             bevel: float = 0.0, smooth: bool = True) -> bpy.types.Object:
        bm = bmesh.new()
        if kind == "box":
            bmesh.ops.create_cube(bm, size=1.0)
            if bevel:
                bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bevel, segments=1,
                                affect="EDGES", profile=0.5)
        elif kind == "sphere":
            bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(6, seg // 2), radius=0.5)
        elif kind == "cone":  # base radius 0.5 at z=0, tip at z=1
            bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=0.5, radius2=0.0, depth=1.0)
            bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 0.5))
        elif kind == "cyl":
            bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=0.5, radius2=0.5, depth=1.0)
            bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 0.5))
        elif kind == "torus":
            r1, r2 = 0.5, 0.1
            ring = []
            for i in range(seg):
                a = i / seg * math.tau
                row = []
                for j in range(6):
                    b = j / 6 * math.tau
                    row.append(bm.verts.new(((r1 + r2 * math.cos(b)) * math.cos(a),
                                             (r1 + r2 * math.cos(b)) * math.sin(a), r2 * math.sin(b))))
                ring.append(row)
            for i in range(seg):
                for j in range(6):
                    bm.faces.new([ring[i][j], ring[(i + 1) % seg][j], ring[(i + 1) % seg][(j + 1) % 6],
                                  ring[i][(j + 1) % 6]])
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        obj = self.link(name, me)
        me.transform(Matrix.LocRotScale(Vector(loc), Euler([math.radians(a) for a in rot]), Vector(scale)))
        for p in obj.data.polygons:
            p.use_smooth = smooth
        return obj

    def spike(self, name: str, base, tip, r: float, seg: int = 6) -> bpy.types.Object:
        """Cone from base (radius r) to tip."""
        base, tip = Vector(base), Vector(tip)
        d = tip - base
        obj = self.prim(name, "cone", (0, 0, 0), (2 * r, 2 * r, d.length), seg=seg, smooth=False)
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        obj.matrix_world = Matrix.Translation(base) @ q.to_matrix().to_4x4()
        self.apply(obj)
        return obj

    @staticmethod
    def apply(obj) -> None:
        mw = obj.matrix_world.copy()
        obj.data.transform(mw)
        obj.matrix_world = Matrix.Identity(4)

    # --- skeleton
    def bone(self, name: str, head, tail, parent: str = None) -> None:
        self.bones[name] = (Vector(head), Vector(tail), parent)

    def build_rig(self) -> None:
        arm = bpy.data.armatures.new(f"{self.name}_rig")
        rig = bpy.data.objects.new(f"{self.name}_rig", arm)
        bpy.context.scene.collection.objects.link(rig)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.mode_set(mode="EDIT")
        for name, (h, t, parent) in self.bones.items():
            eb = arm.edit_bones.new(name)
            eb.head, eb.tail = h, t
            eb.roll = 0.0
            if parent:
                eb.parent = arm.edit_bones[parent]
        bpy.ops.object.mode_set(mode="OBJECT")
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
        self.rig = rig

    def skin_weights(self) -> bpy.types.Object:
        """Join parts into one mesh: rigid parts to their bone, the others by distance to bone segments."""
        segs = {n: (h, t) for n, (h, t, _) in self.bones.items()}
        for obj, rigid, names in self.parts:
            for n in self.bones:
                obj.vertex_groups.new(name=n)
            for v in obj.data.vertices:
                if rigid:
                    obj.vertex_groups[rigid].add([v.index], 1.0, "REPLACE")
                    continue
                d = []
                for n in names:
                    h, t = segs[n]
                    ab = t - h
                    k = max(0.0, min(1.0, (v.co - h).dot(ab) / max(ab.length_squared, 1e-9)))
                    d.append(((v.co - (h + ab * k)).length, n))
                d.sort()
                near = d[:3]
                w = [1.0 / (x + 0.02) ** 4 for x, _ in near]
                s = sum(w)
                for (x, n), wi in zip(near, w):
                    if wi / s > 0.02:
                        obj.vertex_groups[n].add([v.index], wi / s, "REPLACE")
        bpy.ops.object.select_all(action="DESELECT")
        objs = [p[0] for p in self.parts]
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        body = bpy.context.view_layer.objects.active
        body.name = self.name
        # merge coincident verts inside each part only (parts keep their own shading)
        mod = body.modifiers.new("arm", "ARMATURE")
        mod.object = self.rig
        body.parent = self.rig
        return body

    # --- clips
    def clip(self, name: str, keys: dict, loop: bool = False) -> None:
        """keys: {frame: {bone: pose}}; unspecified bones are at rest. loop: last key = first key."""
        rig = self.rig
        if loop:
            last = max(keys)
            first = min(keys)
            keys = dict(keys)
            keys[last] = keys[first]
        act = bpy.data.actions.new(name)
        rig.animation_data_create()
        rig.animation_data.action = act
        rest = {pb.name: pb.bone.matrix_local.to_quaternion() for pb in rig.pose.bones}
        for f in sorted(keys):
            pose = keys[f]
            for pb in rig.pose.bones:
                spec = pose.get(pb.name)
                rq = rest[pb.name]
                q = Quaternion()
                loc = Vector()
                sc = 1.0
                if spec:
                    rot = Euler([math.radians(a) for a in spec[:3]], "XYZ").to_quaternion()
                    q = rq.inverted() @ rot @ rq
                    if len(spec) > 3 and spec[3] is not None:
                        loc = rq.inverted() @ Vector(spec[3])
                    if len(spec) > 4:
                        sc = spec[4]
                pb.rotation_quaternion = q
                pb.location = loc
                pb.scale = (sc, sc, sc)
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
                pb.keyframe_insert("scale", frame=f)
        self.clips[name] = act
        rig.animation_data.action = None

    # --- output
    def export(self, body, extra_report: dict = None) -> dict:
        img = self.palette_image()
        mat = bpy.data.materials.new(f"{self.name}_flat")
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Roughness"].default_value = 1.0
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.interpolation = "Closest"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        body.data.materials.clear()
        body.data.materials.append(mat)
        # base at z = 0
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
        os.makedirs(os.path.join(OUT, self.name), exist_ok=True)
        dst = os.path.join(OUT, self.name, f"{self.name}.glb")
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, f"{self.name}.blend"))
        bpy.ops.export_scene.gltf(
            filepath=dst, export_format="GLB", use_selection=False,
            export_animation_mode="NLA_TRACKS", export_anim_slide_to_zero=True, export_force_sampling=True,
            export_optimize_animation_size=True, export_skins=True, export_influence_nb=4,
            export_morph=False, export_apply=False, export_yup=True, export_image_format="WEBP",
            export_image_quality=90, export_texcoords=True, export_normals=True, export_tangents=False,
            export_materials="EXPORT", export_cameras=False, export_lights=False)
        body.data.calc_loop_triangles()
        pts = [body.matrix_world @ v.co for v in body.data.vertices]
        rep = {
            "id": self.name, "tris": len(body.data.loop_triangles), "bones": len(self.bones),
            "glb_kb": round(os.path.getsize(dst) / 1024),
            "size_m": [round(max(p[i] for p in pts) - min(p[i] for p in pts), 2) for i in range(3)],
            "clips": {n: round((a.frame_range[1] - a.frame_range[0]) / FPS, 2) for n, a in self.clips.items()},
        }
        rep.update(extra_report or {})
        print("@@REPORT@@" + json.dumps(rep))
        return rep


def mirror(p):
    return (-p[0], p[1], p[2])


# ------------------------------------------------------------------------------------------ wolf
def mist_wolf() -> dict:
    """Mist wolf (enemy.mist_wolf, rusher): lean blue-grey wolf, pale misty mane / legs / tail tip,
    ice-blue eyes. 0.9 m at the shoulder, ~1.9 m nose to tail. Same model for the alpha (scaled
    1.3x and tinted darker in game). Colours from our concept art/source/enemies/mist_wolf_concept.png."""
    k = Kit("mist_wolf", {
        "fur": "#7b8ba4", "fur_dark": "#56647c", "pale": "#c6d3e1", "mist": "#e4edf6",
        "nose": "#2f3440", "eye": "#bdf3ff", "claw": "#3a3f4a", "inner_ear": "#b9c7d8",
    })
    # skeleton points (Blender: +Y forward, +Z up), body built as one skin network
    P = {
        "hips": (0, -0.42, 0.8), "spine": (0, -0.05, 0.83), "chest": (0, 0.3, 0.86),
        "neck": (0, 0.47, 1.0), "head": (0, 0.6, 1.1), "snout": (0, 0.8, 1.06), "nose": (0, 0.92, 1.03),
        "tail0": (0, -0.62, 0.84), "tail1": (0, -0.86, 0.68), "tail2": (0, -1.06, 0.5),
    }
    legs = {  # shoulder/hip, elbow/knee, wrist/hock, paw
        "fl": [(0.13, 0.3, 0.74), (0.15, 0.34, 0.45), (0.15, 0.31, 0.14), (0.15, 0.38, 0.04)],
        "hl": [(0.14, -0.42, 0.74), (0.16, -0.28, 0.47), (0.16, -0.5, 0.2), (0.16, -0.44, 0.04)],
    }
    pts, radii, idx = [], [], {}

    def v(name, p, r):
        idx[name] = len(pts)
        pts.append(p)
        radii.append(r)

    v("hips", P["hips"], 0.18)
    v("spine", P["spine"], 0.19)
    v("chest", P["chest"], 0.23)
    v("neck", P["neck"], 0.17)
    v("head", P["head"], 0.16)
    v("snout", P["snout"], 0.085)
    v("nose", P["nose"], 0.045)
    v("tail0", P["tail0"], 0.08)
    v("tail1", P["tail1"], 0.12)
    v("tail2", P["tail2"], 0.06)
    edges = [(idx["hips"], idx["spine"]), (idx["spine"], idx["chest"]), (idx["chest"], idx["neck"]),
             (idx["neck"], idx["head"]), (idx["head"], idx["snout"]), (idx["snout"], idx["nose"]),
             (idx["hips"], idx["tail0"]), (idx["tail0"], idx["tail1"]), (idx["tail1"], idx["tail2"])]
    for leg, chain in legs.items():
        for side, sx in (("L", 1), ("R", -1)):
            prev = idx["chest"] if leg == "fl" else idx["hips"]
            for j, p in enumerate(chain):
                name = f"{leg}{j}{side}"
                v(name, (p[0] * sx, p[1], p[2]), [0.095, 0.065, 0.05, 0.065][j])
                edges.append((prev, idx[name]))
                prev = idx[name]
    # subdivision shrinks skin sections by about a third: radii are scaled up to compensate
    radii = [r * 1.35 for r in radii]
    body = k.skin("body", pts, edges, radii, subsurf=2,
                  flat={idx["chest"]: (0.25, 0.33), idx["head"]: (0.19, 0.2), idx["hips"]: (0.21, 0.25),
                        idx["spine"]: (0.21, 0.26)})
    # bones
    k.bone("root", (0, 0, 0), (0, 0.3, 0))
    k.bone("hips", P["hips"], P["spine"], "root")
    k.bone("spine", P["spine"], P["chest"], "hips")
    k.bone("neck", P["chest"], P["head"], "spine")
    k.bone("head", P["head"], P["nose"], "neck")
    k.bone("tail1", P["tail0"], P["tail1"], "hips")
    k.bone("tail2", P["tail1"], P["tail2"], "tail1")
    for leg, chain in legs.items():
        for side, sx in (("L", 1), ("R", -1)):
            c = [(p[0] * sx, p[1], p[2]) for p in chain]
            parent = "spine" if leg == "fl" else "hips"
            k.bone(f"{leg}_upper_{side}", c[0], c[1], parent)
            k.bone(f"{leg}_lower_{side}", c[1], c[2], f"{leg}_upper_{side}")
            k.bone(f"{leg}_paw_{side}", c[2], c[3], f"{leg}_lower_{side}")
    body_bones = [b for b in k.bones if b != "root"]
    k.add(body, None, body_bones)

    def fur(c, n):
        x, y, z = c
        if n.z < -0.55 and z > 0.5 or z < 0.42:
            return "pale" if z > 0.16 else "mist"
        if y > 0.74:
            return "pale" if n.z < 0.3 else "fur"
        if n.z > 0.75 and -0.45 < y < 0.38:
            return "fur_dark"
        if y < -0.88:
            return "mist"
        return "fur"
    k.paint(body, fur)
    # ears, eyes, nose, claws (rigid)
    for sx in (1, -1):
        ear = k.spike(f"ear{sx}", (0.075 * sx, 0.56, 1.18), (0.1 * sx, 0.52, 1.4), 0.055, seg=5)
        k.paint(ear, lambda c, n: "inner_ear" if n.y > 0.5 else "fur_dark")
        k.add(ear, "head")
        eye = k.prim(f"eye{sx}", "sphere", (0.105 * sx, 0.72, 1.17), (0.05, 0.045, 0.03), seg=8)
        k.paint(eye, lambda c, n: "eye")
        k.add(eye, "head")
        for leg, chain in legs.items():
            pass
    nose = k.prim("nose", "sphere", P["nose"], (0.06, 0.05, 0.045), seg=8)
    k.paint(nose, lambda c, n: "nose")
    k.add(nose, "head")
    # mane: pointed pale tufts around the neck and shoulders, sweeping back (telegraph-friendly silhouette)
    rnd = random.Random(7)
    for i in range(18):
        a = -math.pi * 0.8 + i / 17 * math.pi * 1.6  # around the neck, not under the throat
        ring = Vector(P["neck"]) + Vector((0, -0.06 - 0.04 * (i % 2), -0.02))
        base = ring + Vector((math.sin(a) * 0.19, 0, math.cos(a) * 0.19))
        ln = rnd.uniform(0.8, 1.2)
        tip = base + Vector((math.sin(a) * 0.17, -0.4 * ln, math.cos(a) * 0.14 + 0.05))
        t = k.spike(f"mane{i}", base, tip, 0.08, seg=5)
        k.paint(t, lambda c, n, a=a: "mist" if c.z > 0.98 or abs(math.sin(a)) > 0.6 else "pale")
        k.add(t, "spine" if i % 2 else "neck")
    for i in range(5):  # dark fur ridge along the back
        y = 0.12 - i * 0.12
        base = Vector((0, y, 0.98 - i * 0.012))
        t = k.spike(f"ridge{i}", base, base + Vector((0, -0.2, 0.08)), 0.07, seg=4)
        k.paint(t, lambda c, n: "fur_dark")
        k.add(t, "spine" if y > -0.1 else "hips")
    for sx in (1, -1):  # cheek tufts and chest ruff
        for j in range(2):
            base = Vector((0.13 * sx, 0.6 - j * 0.05, 1.06 - j * 0.06))
            t = k.spike(f"cheek{sx}{j}", base, base + Vector((0.12 * sx, -0.1, -0.05)), 0.05, seg=4)
            k.paint(t, lambda c, n: "pale")
            k.add(t, "head")
    for j in range(5):
        x = (j - 2) * 0.06
        base = Vector((x, 0.45, 0.78))
        t = k.spike(f"ruff{j}", base, base + Vector((x * 0.6, 0.06, -0.24)), 0.06, seg=4)
        k.paint(t, lambda c, n: "pale")
        k.add(t, "spine")
    for i in range(5):  # tail tip wisps
        a = i / 5 * math.tau
        base = Vector(P["tail1"]) + Vector((math.cos(a) * 0.05, -0.05, math.sin(a) * 0.05))
        tip = Vector(P["tail2"]) + Vector((math.cos(a) * 0.09, -0.18, math.sin(a) * 0.07 - 0.05))
        t = k.spike(f"tailtuft{i}", base, tip, 0.06, seg=5)
        k.paint(t, lambda c, n: "mist")
        k.add(t, "tail2")
    k.build_rig()
    body = k.skin_weights()

    def legs_pose(fl, hl, fl2=0, hl2=0):
        # fl/hl: swing of front / hind legs in degrees (+ = paw forward), opposite for each side
        return {
            "fl_upper_L": (fl, 0, 0), "fl_upper_R": (fl2 if fl2 else -fl, 0, 0),
            "hl_upper_L": (hl, 0, 0), "hl_upper_R": (hl2 if hl2 else -hl, 0, 0),
            "fl_lower_L": (-max(0, -fl) * 0.8, 0, 0), "fl_lower_R": (-max(0, fl) * 0.8, 0, 0),
            "hl_lower_L": (max(0, hl) * 0.6, 0, 0), "hl_lower_R": (max(0, -hl) * 0.6, 0, 0),
        }

    def merge(*ds):
        out = {}
        for d in ds:
            out.update(d)
        return out

    k.clip("idle", {
        1: {"spine": (1, 0, 0), "neck": (0, 0, 3), "tail1": (-10, 0, 8), "tail2": (-5, 0, 6)},
        24: {"spine": (-1.5, 0, 0), "neck": (2, 0, -4), "head": (-3, 0, 0), "tail1": (-12, 0, -8),
             "tail2": (-6, 0, -6), "hips": (0, 0, 0, (0, 0, -0.01))},
        48: {},
    }, loop=True)
    # gallop, 16 frames (0.67 s); root bob, front and hind pairs out of phase
    run = {}
    for f, ph in ((1, 0.0), (5, 0.25), (9, 0.5), (13, 0.75)):
        s = math.sin(ph * math.tau)
        c = math.cos(ph * math.tau)
        run[f] = merge(legs_pose(38 * s, -40 * s, 30 * s, -32 * s), {
            "root": (0, 0, 0, (0, 0, 0.06 * abs(c))),
            "hips": (6 * c, 0, 0), "spine": (-5 * c, 0, 0), "neck": (-8 + 4 * c, 0, 0),
            "head": (-4 * c, 0, 0), "tail1": (8 + 10 * s, 0, 0), "tail2": (6 * s, 0, 0)})
    run[17] = run[1]
    k.clip("run", run)
    crouch = merge(legs_pose(-12, 18), {"root": (0, 0, 0, (0, -0.08, -0.1)), "hips": (-6, 0, 0),
                                        "neck": (-14, 0, 0), "head": (6, 0, 0), "tail1": (-20, 0, 0)})
    leap = merge(legs_pose(45, -50, 45, -50), {"root": (8, 0, 0, (0, 0.35, 0.18)), "neck": (6, 0, 0),
                                               "head": (14, 0, 0), "tail1": (20, 0, 0)})
    bite = merge(legs_pose(20, -20), {"root": (-4, 0, 0, (0, 0.4, 0.0)), "neck": (-10, 0, 0),
                                      "head": (-18, 0, 0), "tail1": (10, 0, 0)})
    k.clip("attack", {1: {}, 8: crouch, 13: leap, 17: bite, 22: bite, 30: {}})
    howl_hold = {"root": (0, 0, 0, (0, -0.05, -0.04)), "hips": (-8, 0, 0), "spine": (10, 0, 0),
                 "neck": (25, 0, 0), "head": (28, 0, 0), "tail1": (-15, 0, 0),
                 "fl_upper_L": (8, 0, 0), "fl_upper_R": (8, 0, 0)}
    k.clip("cast", {1: {}, 10: howl_hold, 30: merge(howl_hold, {"head": (32, 0, 4)}), 40: howl_hold,
                    48: {}})
    k.clip("hit", {1: {}, 4: {"root": (0, 0, 0, (0, -0.12, 0)), "spine": (-6, 0, 6), "neck": (-12, 0, -10),
                              "head": (-10, 0, 8), "tail1": (-20, 0, 0)}, 14: {}})
    k.clip("death", {
        1: {},
        8: merge(legs_pose(10, -10), {"root": (0, 0, 0, (0, -0.1, -0.05)), "neck": (-10, 0, 0),
                                      "head": (-12, 0, 0)}),
        20: merge(legs_pose(30, -30, 25, -20), {"root": (0, 82, 0, (0.0, -0.15, 0.1)),
                                                "neck": (-10, 0, 10), "head": (-20, 0, 0),
                                                "tail1": (-10, 0, 20)}),
        30: merge(legs_pose(35, -35, 28, -25), {"root": (0, 88, 0, (0.0, -0.15, 0.06)),
                                                "neck": (-12, 0, 14), "head": (-25, 0, 0),
                                                "tail1": (-10, 0, 25)}),
    })
    return k.export(body)



# --------------------------------------------------------------------------------------- lantern
def wandering_lantern() -> dict:
    """Wandering lantern (enemy.wandering_lantern, caster): a hexagonal iron lantern with a living
    flame inside (two dark eyes on the warm glass), hovering on a wisp of fire. 1.6 m tall overall,
    body 0.75-1.45 m; the wisp tip is the base (y = 0). Floating motion is in the clips (bone "body")."""
    k = Kit("wandering_lantern", {
        "iron": "#3b3441", "iron_hi": "#5d5266", "glass": "#ffcf7a", "glass_hi": "#ffe6a8",
        "flame": "#fff3d0", "eye": "#5a2a1c", "wisp": "#ffb26a", "wisp_tip": "#ff8a4a", "rune": "#e7ecff",
    })
    zb, zt, r = 0.78, 1.32, 0.24  # glass body bottom / top, radius
    # glass prism (6 sides) + iron frame posts, plates, roof, ring, finial
    glass = k.prim("glass", "cyl", (0, 0, zb), (2 * r, 2 * r, zt - zb), seg=6, smooth=False)
    glass.rotation_euler = (0, 0, 0)

    def glass_col(c, n):
        if abs(n.z) > 0.5:
            return "iron"
        # two eyes on the front panel (+Y), a little above the middle
        if n.y > 0.8 and c.z > 0.98 and abs(c.x) < 0.1:
            return "glass_hi"
        return "glass"
    k.paint(glass, glass_col)
    k.add(glass, "body")
    for sx in (-1, 1):
        eye = k.prim(f"eye{sx}", "sphere", (0.065 * sx, r * 0.87 + 0.012, 1.1), (0.06, 0.02, 0.085), seg=8)
        k.paint(eye, lambda c, n: "eye")
        k.add(eye, "body")
    for i in range(6):
        a = i / 6 * math.tau
        post = k.prim(f"post{i}", "box", (math.cos(a) * r * 1.02, math.sin(a) * r * 1.02, (zb + zt) / 2),
                      (0.045, 0.045, zt - zb + 0.04), rot=(0, 0, math.degrees(a)), smooth=False)
        k.paint(post, lambda c, n: "iron")
        k.add(post, "body")
    base = k.prim("base", "cyl", (0, 0, zb - 0.07), (2 * r * 1.15, 2 * r * 1.15, 0.08), seg=6, smooth=False)
    k.paint(base, lambda c, n: "iron_hi" if n.z > 0.5 else "iron")
    k.add(base, "body")
    foot = k.prim("foot", "cone", (0, 0, zb - 0.07), (2 * r * 0.9, 2 * r * 0.9, -0.16), seg=6, smooth=False)
    k.paint(foot, lambda c, n: "iron")
    k.add(foot, "body")
    lip = k.prim("lip", "cyl", (0, 0, zt), (2 * r * 1.2, 2 * r * 1.2, 0.05), seg=6, smooth=False)
    k.paint(lip, lambda c, n: "iron_hi" if n.z > 0.5 else "iron")
    k.add(lip, "body")
    roof = k.prim("roof", "cone", (0, 0, zt + 0.05), (2 * r * 1.25, 2 * r * 1.25, 0.24), seg=6, smooth=False)
    k.paint(roof, lambda c, n: "iron")
    k.add(roof, "body")
    ring = k.prim("ring", "torus", (0, 0, zt + 0.36), (0.16, 0.16, 0.16), rot=(90, 0, 0), seg=12)
    k.paint(ring, lambda c, n: "iron_hi")
    k.add(ring, "body")
    # rune band on the base (pale, telegraph colour family of the spells)
    for i in range(6):
        a = (i + 0.5) / 6 * math.tau
        rn = k.prim(f"rune{i}", "box", (math.cos(a) * r * 1.16, math.sin(a) * r * 1.16, zb - 0.03),
                    (0.012, 0.09, 0.02), rot=(0, 0, math.degrees(a)), smooth=False)
        k.paint(rn, lambda c, n: "rune")
        k.add(rn, "body")
    # flame core seen through the glass top, and the wisp tail under the lantern
    core = k.prim("core", "sphere", (0, 0, zt + 0.02), (0.14, 0.14, 0.2), seg=10)
    k.paint(core, lambda c, n: "flame")
    k.add(core, "body")
    wisp_pts = [(0, 0, zb - 0.2), (0.02, 0.05, 0.5), (-0.05, -0.06, 0.26), (0.03, -0.12, 0.02)]
    wisp = k.skin("wisp", wisp_pts, [(0, 1), (1, 2), (2, 3)], [0.16, 0.12, 0.07, 0.015], subsurf=2)
    k.paint(wisp, lambda c, n: "wisp_tip" if c.z < 0.3 else "wisp")
    k.add(wisp, None, ["wisp", "body"])
    for i in range(3):
        a = i / 3 * math.tau
        b = Vector((math.cos(a) * 0.1, math.sin(a) * 0.1, zb - 0.2))
        t = k.spike(f"flick{i}", b, b + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12 - 0.05, -0.32)), 0.06, seg=5)
        k.paint(t, lambda c, n: "wisp")
        k.add(t, "wisp")
    k.bone("root", (0, 0, 0), (0, 0.3, 0))
    k.bone("body", (0, 0, zb - 0.1), (0, 0, zt + 0.4), "root")
    k.bone("wisp", (0, 0, zb - 0.15), (0, -0.1, 0.02), "body")
    k.build_rig()
    body = k.skin_weights()
    up = 0.08
    k.clip("idle", {
        1: {"body": (0, 0, 0, (0, 0, 0.0)), "wisp": (8, 0, 6)},
        18: {"body": (3, 2, 0, (0, 0, up)), "wisp": (-6, 0, -8)},
        36: {"body": (-2, -2, 0, (0, 0, 0.02)), "wisp": (10, 0, 4)},
        48: {},
    }, loop=True)
    k.clip("run", {
        1: {"body": (-14, 0, 0, (0, 0, 0.05)), "wisp": (25, 0, 8)},
        6: {"body": (-16, 3, 0, (0, 0, 0.12)), "wisp": (32, 0, -8)},
        12: {"body": (-14, 0, 0, (0, 0, 0.05)), "wisp": (25, 0, 8)},
    }, loop=True)
    k.clip("attack", {  # flick a fire bolt: rear back, flare, snap forward
        1: {},
        8: {"body": (12, 0, 0, (0, -0.12, 0.06), 1.0), "wisp": (-15, 0, 0)},
        12: {"body": (-18, 0, 0, (0, 0.18, 0.02), 1.18), "wisp": (30, 0, 0)},
        16: {"body": (-10, 0, 0, (0, 0.1, 0.02), 1.05)},
        26: {},
    })
    k.clip("cast", {  # Embrasement channel: rise, spin, pulsing flare (2 s)
        1: {},
        8: {"body": (0, 0, 60, (0, 0, 0.22), 1.08), "wisp": (10, 0, 0)},
        20: {"body": (0, 0, 180, (0, 0, 0.3), 1.2), "wisp": (-10, 0, 0)},
        32: {"body": (0, 0, 300, (0, 0, 0.26), 1.08), "wisp": (10, 0, 0)},
        44: {"body": (0, 0, 359, (0, 0, 0.3), 1.22), "wisp": (-10, 0, 0)},
        48: {"body": (0, 0, 360, (0, 0, 0.22), 1.1)},
    })
    k.clip("hit", {1: {}, 3: {"body": (10, 0, -18, (0.08, -0.1, 0.0), 0.92), "wisp": (-20, 0, 15)}, 12: {}})
    k.clip("death", {
        1: {},
        6: {"body": (6, 0, 15, (0, 0, 0.12), 1.1)},
        16: {"body": (30, 0, 50, (0.05, 0, -0.45), 0.9), "wisp": (0, 0, 0, None, 0.3)},
        26: {"body": (80, 0, 70, (0.1, 0, -0.62), 0.85), "wisp": (0, 0, 0, None, 0.05)},
        30: {"body": (88, 0, 72, (0.1, 0, -0.62), 0.85), "wisp": (0, 0, 0, None, 0.05)},
    })
    return k.export(body)



# -------------------------------------------------------------------------------------- sentinel
def stone_sentinel() -> dict:
    """Stone sentinel (enemy.stone_sentinel, bulwark): a squat carved-stone construct, 2.2 m, huge fists
    and shoulders, pale-blue rune lines and visor eye (the arcane barrier colour), moss on the shoulders.
    Rigid stone blocks, one bone each: the construct moves like stacked masonry."""
    k = Kit("stone_sentinel", {
        "stone": "#9b958e", "stone_dk": "#726c69", "stone_lt": "#b9b2a8", "rune": "#a9e4ff",
        "moss": "#7f9a58", "moss_dk": "#5f7a42", "crack": "#4d4848",
    })
    rnd = random.Random(11)

    def block(name, bone, loc, size, rot=(0, 0, 0), col=None):
        jitter = (rot[0] + rnd.uniform(-3, 3), rot[1] + rnd.uniform(-3, 3), rot[2] + rnd.uniform(-4, 4))
        b = k.prim(name, "box", loc, size, rot=jitter, bevel=0.08, smooth=False)

        def paint(c, n, z0=loc[2] + size[2] * 0.25):
            if col:
                return col(c, n)
            if n.z > 0.7 and c.z > z0:
                return "stone_lt"
            if n.z < -0.6:
                return "stone_dk"
            return "stone"
        k.paint(b, paint)
        k.add(b, bone)
        return b

    # legs (short, thick), hips, torso, head
    for side, sx in (("L", 1), ("R", -1)):
        block(f"shin{side}", f"shin_{side}", (0.3 * sx, 0.02, 0.0 + 0.0), (0.36, 0.42, 0.5))
        block(f"foot{side}", f"shin_{side}", (0.3 * sx, 0.08, -0.25), (0.42, 0.56, 0.18))
        block(f"thigh{side}", f"thigh_{side}", (0.3 * sx, 0.0, 0.0), (0.34, 0.36, 0.42))
    # boxes are created centred: shift by the bone positions below via explicit z
    k.parts.clear()
    for side, sx in (("L", 1), ("R", -1)):
        block(f"foot{side}", f"shin_{side}", (0.3 * sx, 0.06, 0.09), (0.44, 0.58, 0.18))
        block(f"shin{side}", f"shin_{side}", (0.3 * sx, 0.0, 0.42), (0.36, 0.4, 0.5))
        block(f"thigh{side}", f"thigh_{side}", (0.3 * sx, 0.0, 0.86), (0.34, 0.36, 0.42))
    block("hips", "hips", (0, 0, 1.12), (0.82, 0.5, 0.3))
    block("torso", "torso", (0, 0, 1.55), (1.02, 0.66, 0.66))
    block("chest", "torso", (0, 0.06, 1.62), (0.8, 0.62, 0.42),
          col=lambda c, n: "stone_lt" if n.z > 0.7 else "stone")
    # rune lines on the chest (barrier colour) and a vertical crack
    block("rune_h", "torso", (0, 0.38, 1.66), (0.5, 0.04, 0.05), col=lambda c, n: "rune")
    block("rune_v", "torso", (0, 0.38, 1.5), (0.05, 0.04, 0.3), col=lambda c, n: "rune")
    block("rune_l", "torso", (-0.18, 0.38, 1.44), (0.04, 0.04, 0.16), rot=(0, 30, 0), col=lambda c, n: "rune")
    block("rune_r", "torso", (0.18, 0.38, 1.44), (0.04, 0.04, 0.16), rot=(0, -30, 0), col=lambda c, n: "rune")
    block("head", "head", (0, 0.06, 2.03), (0.42, 0.42, 0.34))
    block("brow", "head", (0, 0.24, 2.12), (0.46, 0.12, 0.1), col=lambda c, n: "stone_dk")
    block("visor", "head", (0, 0.27, 2.02), (0.3, 0.04, 0.06), col=lambda c, n: "rune")
    for side, sx in (("L", 1), ("R", -1)):
        block(f"shoulder{side}", f"upper_arm_{side}", (0.66 * sx, 0.0, 1.78), (0.46, 0.5, 0.4),
              col=lambda c, n: ("moss" if n.z > 0.6 else "stone"))
        block(f"moss{side}", f"upper_arm_{side}", (0.66 * sx, -0.04, 2.0), (0.34, 0.36, 0.08),
              col=lambda c, n: "moss_dk" if n.z < 0.5 else "moss")
        block(f"upper{side}", f"upper_arm_{side}", (0.7 * sx, 0.0, 1.42), (0.28, 0.3, 0.42))
        block(f"fore{side}", f"forearm_{side}", (0.72 * sx, 0.04, 1.02), (0.32, 0.34, 0.4))
        block(f"fist{side}", f"forearm_{side}", (0.72 * sx, 0.06, 0.68), (0.46, 0.48, 0.38))
        block(f"knuckle{side}", f"forearm_{side}", (0.72 * sx, 0.3, 0.68), (0.36, 0.08, 0.2),
              col=lambda c, n: "stone_dk")
        block(f"armrune{side}", f"forearm_{side}", (0.89 * sx, 0.04, 1.02), (0.02, 0.14, 0.24),
              col=lambda c, n: "rune")
    k.bone("root", (0, 0, 0), (0, 0.3, 0))
    k.bone("hips", (0, 0, 1.05), (0, 0, 1.3), "root")
    k.bone("torso", (0, 0, 1.3), (0, 0, 1.88), "hips")
    k.bone("head", (0, 0, 1.88), (0, 0, 2.2), "torso")
    for side, sx in (("L", 1), ("R", -1)):
        k.bone(f"thigh_{side}", (0.3 * sx, 0, 1.08), (0.3 * sx, 0, 0.68), "hips")
        k.bone(f"shin_{side}", (0.3 * sx, 0, 0.68), (0.3 * sx, 0, 0.05), f"thigh_{side}")
        k.bone(f"upper_arm_{side}", (0.66 * sx, 0, 1.8), (0.7 * sx, 0, 1.24), "torso")
        k.bone(f"forearm_{side}", (0.7 * sx, 0, 1.24), (0.72 * sx, 0, 0.6), f"upper_arm_{side}")
    k.build_rig()
    body = k.skin_weights()

    def arms(l_up, l_fo, r_up=None, r_fo=None, spread=0):
        r_up = l_up if r_up is None else r_up
        r_fo = l_fo if r_fo is None else r_fo
        return {"upper_arm_L": (l_up, -spread, 0), "forearm_L": (l_fo, 0, 0),
                "upper_arm_R": (r_up, spread, 0), "forearm_R": (r_fo, 0, 0)}

    def merge(*ds):
        out = {}
        for d in ds:
            out.update(d)
        return out

    k.clip("idle", {
        1: merge(arms(4, 6), {"torso": (2, 0, 0)}),
        30: merge(arms(6, 10), {"torso": (-1, 0, 2), "head": (0, 0, -4), "hips": (0, 0, 0, (0, 0, -0.02))}),
        60: {},
    }, loop=True)
    walk = {}
    for f, ph in ((1, 0.0), (7, 0.25), (13, 0.5), (19, 0.75)):
        sn, cs = math.sin(ph * math.tau), math.cos(ph * math.tau)
        walk[f] = merge(arms(-14 * sn, 10, 14 * sn, 10), {
            "thigh_L": (24 * sn, 0, 0), "thigh_R": (-24 * sn, 0, 0),
            "shin_L": (-max(0, -sn) * 30, 0, 0), "shin_R": (-max(0, sn) * 30, 0, 0),
            "hips": (0, 5 * sn, 0, (0, 0, -0.06 * abs(cs))), "torso": (-6, -4 * sn, 3 * sn)})
    walk[25] = walk[1]
    k.clip("run", walk)
    raise_ = merge(arms(150, 20, 150, 20), {"torso": (14, 0, 0), "head": (8, 0, 0),
                                             "hips": (0, 0, 0, (0, -0.05, 0.02))})
    slam = merge(arms(40, 30, 40, 30), {"torso": (-28, 0, 0), "head": (-6, 0, 0),
                                         "hips": (0, 0, 0, (0, 0.1, -0.16)),
                                         "thigh_L": (30, 0, 0), "thigh_R": (30, 0, 0),
                                         "shin_L": (-40, 0, 0), "shin_R": (-40, 0, 0)})
    # Fracas: 1.2 s wind-up readable from the camera, slam, slow recovery
    k.clip("attack", {1: {}, 16: raise_, 24: raise_, 29: slam, 40: slam, 56: {}})
    guard = merge(arms(70, 70, 70, 70, spread=-20), {"torso": (-6, 0, 0), "head": (-10, 0, 0)})
    k.clip("cast", {1: {}, 12: guard, 36: merge(guard, {"torso": (-8, 0, 3)}), 48: {}})
    k.clip("hit", {1: {}, 4: merge(arms(-10, 20), {"torso": (12, 0, -6), "head": (10, 0, 6),
                                                   "hips": (0, 0, 0, (0, -0.08, 0))}), 16: {}})
    kneel = merge(arms(10, 10), {"hips": (0, 0, 0, (0, 0.05, -0.38)), "thigh_L": (80, 0, 0),
                                 "thigh_R": (75, 0, 0), "shin_L": (-85, 0, 0), "shin_R": (-80, 0, 0),
                                 "torso": (-20, 0, 0), "head": (-20, 0, 0)})
    fall = merge(arms(25, 15, 15, 10, spread=8), {
        "hips": (0, 0, 0, (0, 0.2, -0.62)), "thigh_L": (88, 0, 0), "thigh_R": (85, 0, 0),
        "shin_L": (-88, 0, 0), "shin_R": (-86, 0, 0), "torso": (-62, 0, 4), "head": (-25, 0, 10)})
    k.clip("death", {1: {}, 12: kneel, 24: fall, 34: fall})
    return k.export(body)



# -------------------------------------------------------------------------------------- morvaine
def morvaine() -> dict:
    """Morvaine, Tisseuse de cendres (enemy.morvaine, boss) - ORIGINAL design, not a canon character.
    Design brief (text only): a tall, slender demon woman, 1.9 m, ash-grey skin with a faint lavender
    cast, pale gold eyes, two dark horns sweeping back from the temples with ember-red tips, long
    straight charcoal hair falling to the hips with two side locks; a high-collared floor-length gown
    of dark ash, ember seams and an ember hem that looks like smouldering cloth, wide sleeves; three
    glowing ember threads spiral around her right forearm (she weaves ash into binding threads).
    No legs visible: she glides. Readable from the 50° camera by the horns, the pale face and hands
    against the dark gown, and the ember hem ring."""
    k = Kit("morvaine", {
        "skin": "#cbc4cc", "skin_dk": "#a9a1ad", "gown": "#3c3842", "gown_dk": "#2b2830",
        "ember": "#e0662e", "ember_hi": "#ffb067", "hair": "#2c2930", "hair_hi": "#45404a",
        "horn": "#2f2830", "eye": "#f2cf6a", "lip": "#8c5a66",
    })
    # ---- body (skin network): pelvis, waist, chest, neck, arms
    P = {"pelvis": (0, 0, 1.0), "waist": (0, 0, 1.13), "chest": (0, 0.01, 1.33), "neck": (0, 0.0, 1.53),
         "head": (0, 0.01, 1.62)}
    arm = [(0.19, 0.0, 1.45), (0.27, -0.03, 1.2), (0.31, 0.03, 0.97), (0.32, 0.05, 0.9)]
    pts, radii, edges, idx = [], [], [], {}

    def v(name, p, r, parent=None):
        idx[name] = len(pts)
        pts.append(p)
        radii.append(r * 1.3)
        if parent:
            edges.append((idx[parent], idx[name]))

    v("pelvis", P["pelvis"], 0.12)
    v("waist", P["waist"], 0.085, "pelvis")
    v("chest", P["chest"], 0.12, "waist")
    v("neck", P["neck"], 0.042, "chest")
    v("headb", P["head"], 0.05, "neck")
    for side, sx in (("L", 1), ("R", -1)):
        prev = "chest"
        for j, p in enumerate(arm):
            n = f"arm{j}{side}"
            v(n, (p[0] * sx, p[1], p[2]), [0.05, 0.038, 0.03, 0.028][j], prev)
            prev = n
    body = k.skin("body", pts, edges, radii, subsurf=2,
                  flat={idx["chest"]: (0.19, 0.13), idx["waist"]: (0.13, 0.1), idx["pelvis"]: (0.17, 0.13)})
    k.paint(body, lambda c, n: "skin" if (c.z > 1.47 and abs(c.x) < 0.07) or c.z < 0.99 and abs(c.x) > 0.25
            else "gown")
    k.add(body, None, ["hips", "spine", "chest", "neck", "upper_arm_L", "forearm_L", "upper_arm_R", "forearm_R"])
    # ---- gown skirt: lathe with a scalloped, slightly trailing hem
    seg, rows = 24, [(1.12, 0.135), (1.0, 0.17), (0.75, 0.25), (0.42, 0.37), (0.12, 0.5), (0.0, 0.54)]
    bm = bmesh.new()
    grid = []
    for zi, (z, r) in enumerate(rows):
        ring = []
        for i in range(seg):
            a = i / seg * math.tau
            back = max(0.0, -math.sin(a))  # -Y = back: longer, wider train
            rr = r * (1 + 0.18 * back * (zi / (len(rows) - 1)))
            zz = z
            if zi == len(rows) - 1:
                zz = 0.0 + 0.035 * (1 + math.sin(a * 8)) * 0.5
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, zz)))
        grid.append(ring)
    for zi in range(len(rows) - 1):
        for i in range(seg):
            bm.faces.new([grid[zi][i], grid[zi][(i + 1) % seg], grid[zi + 1][(i + 1) % seg], grid[zi + 1][i]])
    bm.faces.new(grid[-1][::-1])  # closed hem (seen from the camera when she rises)
    me = bpy.data.meshes.new("skirt")
    bm.to_mesh(me)
    bm.free()
    skirt = k.link("skirt", me)
    bpy.context.view_layer.objects.active = skirt
    sub = skirt.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    bpy.ops.object.modifier_apply(modifier="sub")
    for pl in skirt.data.polygons:
        pl.use_smooth = True

    def skirt_col(c, n):
        a = math.atan2(c.y, c.x)
        if c.z < 0.13:
            return "ember" if c.z > 0.06 else "ember_hi"
        seam = min(abs(math.sin((a - math.pi / 4) * 2)), 1.0)
        if seam < 0.07 and c.z < 0.9:
            return "ember"
        if c.z < 0.3:
            return "gown_dk"
        return "gown"
    k.paint(skirt, skirt_col)
    k.add(skirt, None, ["skirt_F", "skirt_B", "skirt_L", "skirt_R", "hips"])
    belt = k.prim("belt", "torus", (0, 0, 1.11), (0.31, 0.25, 0.35), seg=16)
    k.paint(belt, lambda c, n: "ember")
    k.add(belt, "hips")
    collar = k.prim("collar", "cyl", (0, -0.005, 1.45), (0.16, 0.14, 0.14), seg=12)
    k.paint(collar, lambda c, n: "ember" if c.z > 1.57 else "gown_dk")
    k.add(collar, "neck")
    # ---- sleeves, hands, ember threads
    for side, sx in (("L", 1), ("R", -1)):
        el, wr = Vector((arm[1][0] * sx, arm[1][1], arm[1][2])), Vector((arm[2][0] * sx, arm[2][1], arm[2][2]))
        sl = k.spike(f"sleeve{side}", wr + (wr - el) * 0.05, el + (el - wr) * 0.15, 0.1, seg=10)
        k.paint(sl, lambda c, n, wz=wr.z: "ember" if c.z < wz + 0.03 else "gown")
        k.add(sl, f"forearm_{side}")
        hand = k.prim(f"hand{side}", "sphere", (arm[3][0] * sx, arm[3][1], arm[3][2]), (0.06, 0.08, 0.1), seg=10)
        k.paint(hand, lambda c, n: "skin")
        k.add(hand, f"hand_{side}")
    rnd = random.Random(4)
    wr, el = Vector((-arm[2][0], arm[2][1], arm[2][2])), Vector((-arm[1][0], arm[1][1], arm[1][2]))
    for t in range(3):
        tp, ph = [], t / 3 * math.tau
        for i in range(9):
            f = i / 8
            c = el.lerp(wr, f) + Vector((0, 0, -0.08 * f))
            a = ph + f * math.tau * 1.4
            rr = 0.09 + 0.03 * math.sin(f * 5 + t)
            tp.append(c + Vector((math.cos(a) * rr, math.sin(a) * rr, 0)))
        th = k.skin(f"thread{t}", tp, [(i, i + 1) for i in range(8)], [0.008] * 9, subsurf=1)
        k.paint(th, lambda c, n: "ember_hi")
        k.add(th, "forearm_R")
    # ---- head, face, hair, horns
    head = k.prim("head", "sphere", (0, 0.012, 1.685), (0.19, 0.215, 0.25), seg=16)
    k.paint(head, lambda c, n: "skin")
    k.add(head, "head")
    for sx in (1, -1):
        eye = k.prim(f"eye{sx}", "sphere", (0.042 * sx, 0.112, 1.69), (0.045, 0.012, 0.024), seg=8)
        k.paint(eye, lambda c, n: "eye")
        k.add(eye, "head")
    lip = k.prim("lip", "sphere", (0, 0.105, 1.615), (0.03, 0.01, 0.008), seg=6)
    k.paint(lip, lambda c, n: "lip")
    k.add(lip, "head")
    cap = k.prim("haircap", "sphere", (0, -0.03, 1.715), (0.215, 0.215, 0.235), seg=16)
    k.paint(cap, lambda c, n: "hair_hi" if n.z > 0.75 else "hair")
    k.add(cap, "head")
    # three long tapered strands fanning down the back to the hips
    for j, sx in enumerate((-1, 0, 1)):
        hp = [(0.05 * sx, -0.07, 1.74), (0.08 * sx, -0.12, 1.58), (0.1 * sx, -0.135, 1.36),
              (0.11 * sx, -0.13, 1.14), (0.1 * sx, -0.12, 0.98 + 0.05 * abs(sx))]
        hair = k.skin(f"hair{j}", hp, [(i, i + 1) for i in range(4)], [0.07, 0.07, 0.065, 0.05, 0.01], subsurf=2,
                      flat={1: (0.075, 0.045), 2: (0.07, 0.04), 3: (0.055, 0.03)})
        k.paint(hair, lambda c, n: "hair_hi" if n.z > 0.6 else "hair")
        k.add(hair, None, ["head", "hair"])
    for sx in (1, -1):
        lock = k.skin(f"lock{sx}", [(0.1 * sx, 0.04, 1.7), (0.115 * sx, 0.06, 1.55), (0.12 * sx, 0.07, 1.36)],
                      [(0, 1), (1, 2)], [0.035, 0.035, 0.012], subsurf=1)
        k.paint(lock, lambda c, n: "hair")
        k.add(lock, "head")
        hp = [(0.07 * sx, 0.0, 1.78), (0.12 * sx, -0.05, 1.86), (0.16 * sx, -0.14, 1.92), (0.15 * sx, -0.26, 1.95)]
        horn = k.skin(f"horn{sx}", hp, [(0, 1), (1, 2), (2, 3)], [0.03, 0.026, 0.017, 0.004], subsurf=1)
        k.paint(horn, lambda c, n: "ember" if c.y < -0.2 else "horn")
        k.add(horn, "head")
    # ---- skeleton
    k.bone("root", (0, 0, 0), (0, 0.3, 0))
    k.bone("hips", P["pelvis"], P["waist"], "root")
    k.bone("spine", P["waist"], P["chest"], "hips")
    k.bone("chest", P["chest"], (0, 0, 1.47), "spine")
    k.bone("neck", (0, 0, 1.47), P["head"], "chest")
    k.bone("head", P["head"], (0, 0.01, 1.84), "neck")
    k.bone("hair", (0, -0.1, 1.6), (0, -0.12, 1.0), "head")
    for name, tip in (("skirt_F", (0, 0.5, 0.05)), ("skirt_B", (0, -0.6, 0.05)), ("skirt_L", (0.5, 0, 0.05)),
                      ("skirt_R", (-0.5, 0, 0.05))):
        k.bone(name, (tip[0] * 0.25, tip[1] * 0.25, 0.95), tip, "hips")
    for side, sx in (("L", 1), ("R", -1)):
        a = [(p[0] * sx, p[1], p[2]) for p in arm]
        k.bone(f"upper_arm_{side}", a[0], a[1], "chest")
        k.bone(f"forearm_{side}", a[1], a[2], f"upper_arm_{side}")
        k.bone(f"hand_{side}", a[2], (a[3][0], a[3][1], a[3][2] - 0.06), f"forearm_{side}")
    k.build_rig()
    body = k.skin_weights()

    def merge(*ds):
        out = {}
        for d in ds:
            out.update(d)
        return out

    def arms(lx, ly, rx, ry, lf=0, rf=0):
        # rx: raise forward, ry: spread (+ = outwards for both sides), forearm bend lf / rf
        return {"upper_arm_L": (lx, -ly, 0), "upper_arm_R": (rx, ry, 0),
                "forearm_L": (lf, 0, 0), "forearm_R": (rf, 0, 0)}

    weave_a = merge(arms(30, 12, 34, 10, 40, 50), {"hand_L": (0, 0, 20), "hand_R": (0, 0, -25)})
    weave_b = merge(arms(36, 8, 28, 14, 55, 35), {"hand_L": (0, 0, -15), "hand_R": (0, 0, 20)})
    k.clip("idle", {
        1: merge(weave_a, {"hips": (0, 0, 0, (0, 0, 0.0)), "head": (-3, 0, 4), "skirt_B": (-3, 0, 0)}),
        30: merge(weave_b, {"hips": (0, 0, 0, (0, 0, 0.02)), "chest": (2, 0, 0), "head": (-5, 0, -4),
                            "skirt_B": (3, 0, 0), "skirt_F": (-2, 0, 0), "hair": (3, 0, 0)}),
        60: {},
    }, loop=True)
    glide = merge(arms(-35, 14, -35, 14, 10, 10), {"hips": (0, 0, 0, (0, 0, 0.04)), "spine": (-10, 0, 0),
                                                   "chest": (-6, 0, 0), "head": (8, 0, 0),
                                                   "skirt_F": (-18, 0, 0), "skirt_B": (-14, 0, 0),
                                                   "skirt_L": (0, 6, 0), "skirt_R": (0, -6, 0), "hair": (-18, 0, 0)})
    glide2 = merge(glide, {"hips": (0, 0, 0, (0, 0, 0.07)), "skirt_F": (-24, 0, 0), "skirt_B": (-20, 0, 0),
                           "skirt_L": (0, 0, 0), "skirt_R": (0, 0, 0), "hair": (-24, 0, 0)})
    k.clip("run", {1: glide, 9: glide2, 18: glide}, loop=True)
    wind = merge(arms(20, 10, -40, 30, 20, 70), {"chest": (0, 0, 25), "head": (0, 0, -15)})
    thrust = merge(arms(15, 10, 85, 0, 20, 0), {"chest": (-4, 0, -12), "spine": (-6, 0, 0), "head": (0, 0, 5),
                                                "hand_R": (-20, 0, 0), "skirt_B": (6, 0, 0)})
    k.clip("attack", {1: {}, 9: wind, 14: thrust, 22: thrust, 34: {}})
    up_a = merge(arms(110, 25, 110, 25, 30, 30), {"head": (12, 0, 0), "chest": (6, 0, 0),
                                                  "hips": (0, 0, 0, (0, 0, 0.08)), "hand_L": (0, 0, 30),
                                                  "hand_R": (0, 0, -30), "hair": (8, 0, 0)})
    up_b = merge(up_a, arms(95, 35, 120, 15, 50, 20), {"hand_L": (0, 0, -30), "hand_R": (0, 0, 30)})
    k.clip("cast", {1: {}, 10: up_a, 22: up_b, 34: up_a, 42: up_b, 54: {}})
    k.clip("hit", {1: {}, 4: merge(arms(-20, 30, -20, 30, 30, 30), {"spine": (16, 0, 0), "chest": (10, 0, 8),
                                                                    "head": (14, 0, -10),
                                                                    "hips": (0, 0, 0, (0, -0.1, 0))}), 16: {}})
    k.clip("death", {
        1: {},
        10: merge(arms(60, -10, 60, -10, 90, 90), {"spine": (-18, 0, 0), "head": (-25, 0, 0),
                                                   "hips": (0, 0, 0, (0, 0, -0.1))}),
        30: merge(arms(40, -5, 40, -5, 100, 100), {"spine": (-35, 0, 0), "chest": (-15, 0, 0),
                                                   "head": (-30, 0, 0), "hips": (0, 0, 0, (0, 0.05, -0.55)),
                                                   "skirt_F": (40, 0, 0), "skirt_B": (-40, 0, 0),
                                                   "skirt_L": (0, -35, 0), "skirt_R": (0, 35, 0)}),
        44: merge(arms(30, -5, 30, -5, 100, 100), {"root": (0, 0, 0, None, 0.7),
                                                   "spine": (-40, 0, 0), "chest": (-15, 0, 0),
                                                   "head": (-35, 0, 0), "hips": (0, 0, 0, (0, 0.08, -0.7)),
                                                   "skirt_F": (60, 0, 0), "skirt_B": (-60, 0, 0),
                                                   "skirt_L": (0, -55, 0), "skirt_R": (0, 55, 0)}),
    })
    spread = merge(arms(10, 80, 10, 80, 10, 10), {"head": (25, 0, 0), "chest": (12, 0, 0), "spine": (5, 0, 0),
                                                  "hips": (0, 0, 0, (0, 0, 0.15)), "hair": (15, 0, 0),
                                                  "skirt_F": (8, 0, 0), "skirt_B": (-8, 0, 0)})
    k.clip("phase", {1: {}, 12: spread, 28: merge(spread, {"head": (30, 0, 6)}), 40: {}})
    return k.export(body)


BUILDERS = {"mist_wolf": mist_wolf, "wandering_lantern": wandering_lantern,
            "stone_sentinel": stone_sentinel, "morvaine": morvaine}

if __name__ == "__main__":
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for n in names or list(BUILDERS):
        BUILDERS[n]()
