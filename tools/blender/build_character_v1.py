"""Fern v1 build: Meshy rig + clips -> game GLB with secondary bones (hair, skirt), staff, flat albedo.

Usage:
  blender -b --factory-startup -P tools/blender/build_character_v1.py -- \
      --rig rig_0.glb --clip idle=idle.glb --clip cast=cast.glb:1:40 ... \
      --albedo flat.png --out fern.glb [--blend fern.blend] [--target-tris 22000] [--height 1.6]

--clip name=path[:first:last]   optional frame range (source frames, inclusive) to trim a clip.
--loop name,name                clips whose last frames are blended into the first pose (seamless loop).

Pipeline (each step prints into the @@REPORT@@ JSON):
  1. import the Meshy rig, drop helpers, import each clip as an action (trimmed), no stray NLA.
  2. decimate (collapse) to --target-tris; shrink the hands a little toward the wrist.
  3. swap the base colour for the flattened albedo (tools/blender/flatten_albedo.py), 1K, WebP.
  4. classify vertices by albedo colour (hair / skin / white dress / black coat / boots).
  5. secondary bones: SKIRT_<a>_<1..3> rings under Hips (coat + dress below the waist),
     HAIR_<side>_<1..3> chains under Spine (chest); weights rebuilt for those regions (no thigh weights
     on the skirt: it can no longer tear between the legs).
  6. skirt follow: every clip gets the skirt chain roots keyed so the hem clears the legs
     (outward push = furthest leg along the chain direction, sideways = weighted leg swing).
     Hair and the skirt tips are left to SpringBoneSimulator3D in Godot.
  7. face normals bent toward a head sphere (clean anime face under 2-band shading).
  6a. staff prop: rigid mesh skinned to its own "Staff" bone (child of RightHand, at the grip),
     upright in the idle pose; keyed per clip to pivot back toward upright (--staff-upright).
  9. rotate to face glTF -Z, feet at 0, export GLB (NLA tracks, WebP, 4 influences).
"""
import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("--rig", required=True)
ap.add_argument("--clip", action="append", default=[])
ap.add_argument("--loop", default="idle,walk,run")
ap.add_argument("--albedo", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--blend")
ap.add_argument("--target-tris", type=int, default=22000)
ap.add_argument("--height", type=float, default=1.6)
ap.add_argument("--tex", type=int, default=1024)
ap.add_argument("--hand-scale", type=float, default=0.88)
ap.add_argument("--skirt-chains", type=int, default=8)
ap.add_argument("--no-staff", action="store_true")
ap.add_argument("--staff-upright", default="idle=1,walk=0.85,run=0.8,hit=0.6,cast=0.35,death=0,victory=0",
                help="per clip: how much the staff pivots back toward upright in the palm")
ap.add_argument("--name", default="Fern", help="prefix of the rig, mesh, material and texture names")
ap.add_argument("--class-mode", default="fern", choices=("fern", "robe"),
                help="albedo -> vertex class rules: fern (violet hair, white dress, black coat) or robe "
                "(near-black hair, dark grey robe with ember trim = 'white' dress class, lavender skin)")
ap.add_argument("--in-place", default="", help="clip=k,...: horizontal Hips travel scaled by k (0 = in place)")
ap.add_argument("--head-up", type=float, default=10.0, help="degrees added to every clip: chin up, "
                "so the face reads from the 50 deg top-down camera")
a = ap.parse_args(argv)
report = {}


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    return [o for o in bpy.data.objects if o not in before]


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- 1. import
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
new = import_glb(a.rig)
rig = next(o for o in new if o.type == "ARMATURE")
body = next(o for o in new if o.type == "MESH" and o.parent == rig)
for o in new:
    if o not in (rig, body):
        bpy.data.objects.remove(o)
rig.name = rig.data.name = f"{a.name}_Rig"
body.name = f"{a.name}_Body"
rig.animation_data_create()
if rig.animation_data.action:
    old = rig.animation_data.action
    rig.animation_data.action = None
    bpy.data.actions.remove(old)
for tr in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(tr)

clips = {}
for spec in a.clip:
    name, rest = spec.split("=", 1)
    parts = rest.split(":")
    path = parts[0]
    rng = (float(parts[1]), float(parts[2])) if len(parts) == 3 else None
    objs = import_glb(path)
    src = next(o for o in objs if o.type == "ARMATURE")
    act = src.animation_data.action
    src.animation_data.action = None
    act.name = name
    act.use_fake_user = True
    for o in objs:
        bpy.data.objects.remove(o)
    if rng:
        # trim: drop keys outside the range, shift so the clip starts at frame 1
        f0, f1 = rng
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        kps = fc.keyframe_points
                        for i in range(len(kps) - 1, -1, -1):
                            if kps[i].co.x < f0 - 1e-3 or kps[i].co.x > f1 + 1e-3:
                                kps.remove(kps[i])
                        for kp in kps:
                            kp.co.x -= f0 - 1
                            kp.handle_left.x -= f0 - 1
                            kp.handle_right.x -= f0 - 1
                        fc.update()
    clips[name] = act
for tr in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(tr)
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
report["clips_in"] = {n: [round(x, 1) for x in act.frame_range] for n, act in clips.items()}


def channelbag(act):
    return act.layers[0].strips[0].channelbags[0]


# optional: keep clips (near) in place, e.g. a hit reaction that steps back a metre
for kv in filter(None, a.in_place.split(",")):
    cname, k = kv.split("=")
    act = clips.get(cname)
    if not act:
        continue
    fcs = {fc.array_index: fc for fc in channelbag(act).fcurves if fc.data_path == 'pose.bones["Hips"].location'}
    if len(fcs) != 3 or len({len(fc.keyframe_points) for fc in fcs.values()}) != 1:
        continue
    M3 = rig.data.bones["Hips"].matrix_local.to_3x3()
    up = (rig.matrix_world.inverted().to_3x3() @ Vector((0, 0, 1))).normalized()  # world up, armature space
    n = len(fcs[0].keyframe_points)
    vs = [M3 @ Vector([fcs[j].keyframe_points[i].co.y for j in range(3)]) for i in range(n)]
    h0 = vs[0] - up * vs[0].dot(up)
    for i, v in enumerate(vs):
        h = v - up * v.dot(up)
        nv = up * v.dot(up) + h0 + (h - h0) * float(k)
        loc = M3.inverted() @ nv
        for j in range(3):
            fcs[j].keyframe_points[i].co.y = loc[j]
            fcs[j].keyframe_points[i].interpolation = "LINEAR"
    for fc in fcs.values():
        fc.update()
    report.setdefault("in_place", {})[cname] = float(k)


# ---------------------------------------------------------------- 2. decimate, hands
def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


# glTF import splits vertices on UV seams: weld them (UVs live on face corners, so they survive),
# otherwise per-vertex edits (classification, weights, smoothing) crack the seams open
bm = bmesh.new()
bm.from_mesh(body.data)
nv = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
report["welded_verts"] = nv - len(bm.verts)
bm.to_mesh(body.data)
bm.free()
report["tris_in"] = tri_count(body)
if report["tris_in"] > a.target_tris * 1.05:
    mod = body.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = a.target_tris / report["tris_in"]
    mod.use_collapse_triangulate = True
    with bpy.context.temp_override(object=body, active_object=body, selected_objects=[body]):
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
report["tris_out"] = tri_count(body)

RM = rig.matrix_world
BM = body.matrix_world
BMi = BM.inverted()
bones = rig.data.bones


def bhead(name):
    return RM @ bones[name].head_local


gi = {g.name: g.index for g in body.vertex_groups}
gname = {g.index: g.name for g in body.vertex_groups}
me = body.data
for side in ("Left", "Right"):
    hand = gi.get(side + "Hand")
    wrist = bhead(side + "Hand")
    for v in me.vertices:
        w = next((g.weight for g in v.groups if g.group == hand), 0.0)
        if w > 0.05:
            p = BM @ v.co
            k = 1.0 - (1.0 - a.hand_scale) * min(1.0, w * 1.5)
            v.co = BMi @ (wrist + (p - wrist) * k)

# ---------------------------------------------------------------- 3. albedo
mat = body.material_slots[0].material
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
tex = bsdf.inputs["Base Color"].links[0].from_node
for n in list(nt.nodes):
    if n not in (bsdf, tex) and n.type != "OUTPUT_MATERIAL":
        nt.nodes.remove(n)
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 1.0
bsdf.inputs["Specular IOR Level"].default_value = 0.0
old_img = tex.image
img = bpy.data.images.load(os.path.abspath(a.albedo))
img.name = f"{a.name}_Albedo"
if max(img.size) != a.tex:
    img.scale(a.tex, a.tex)
tex.image = img
bpy.data.images.remove(old_img)
mat.name = f"{a.name}_Mat"
W, H = img.size
pix = list(img.pixels[:])  # RGBA floats, row 0 = bottom


def sample(uv):
    x = min(W - 1, max(0, int(uv.x % 1.0 * W)))
    y = min(H - 1, max(0, int(uv.y % 1.0 * H)))
    i = (y * W + x) * 4
    return pix[i], pix[i + 1], pix[i + 2]


# ---------------------------------------------------------------- 4. classify vertices
uvl = me.uv_layers.active.data
vcol = [[0.0, 0.0, 0.0, 0] for _ in me.vertices]
for loop in me.loops:
    r, g, b = sample(uvl[loop.index].uv)
    c = vcol[loop.vertex_index]
    c[0] += r; c[1] += g; c[2] += b; c[3] += 1


def classify(c):
    n = max(1, c[3])
    r, g, b = c[0] / n, c[1] / n, c[2] / n
    mx, mn = max(r, g, b), min(r, g, b)
    if a.class_mode == "robe":
        # robe (dark grey) and its ember trim play the "white dress" role: never driven by the legs
        if mx < 0.18:
            return "hair"  # near-black: hair, also shoes and horns (filtered by height later)
        if mx > 0.55 and mn > 0.5 and b >= g:
            return "skin"  # pale lavender skin
        return "white"
    if b > g + 0.08 and r > g + 0.05 and mx > 0.18:
        return "hair"
    if r > b + 0.08 and mx > 0.6:
        return "skin"
    if mn > 0.6:
        return "white"
    return "black"


cls = [classify(c) for c in vcol]
wpos = [BM @ v.co for v in me.vertices]
arm_bones = {gi[n] for n in gi if any(k in n for k in ("Arm", "Hand", "Shoulder"))}
leg_bones = {gi[n] for n in gi if any(k in n for k in ("UpLeg", "Leg", "Foot", "Toe"))}


def armish(v):
    """arm-driven and close to the forearm/hand (sleeve, hand), not just an arm weight on the coat"""
    if sum(g.weight for g in v.groups if g.group in arm_bones) <= 0.5:
        return False
    p = BM @ v.co
    if p.z < hips.z and math.hypot(p.x - hips.x, p.y - hips.y) < 0.24:
        return False  # coat body below the waist, even where the hand hangs next to it
    for side in ("Left", "Right"):
        a_, f_, h_ = bhead(side + "Arm"), bhead(side + "ForeArm"), bhead(side + "Hand")
        tip = h_ + (h_ - f_).normalized() * 0.1
        for s0, s1 in ((a_, f_), (f_, h_), (h_, tip)):
            ab = s1 - s0
            t = min(1.0, max(0.0, (p - s0).dot(ab) / max(1e-8, ab.length_squared)))
            if (p - (s0 + ab * t)).length < 0.10:
                return True
    return False


hips = bhead("Hips")
neck_z = bhead("neck").z
head_c = bhead("Head")
hem_z = min(p.z for p, c in zip(wpos, cls) if c == "white")  # lowest dress vertex ~ hem
report["hem_z"] = round(hem_z, 3)
report["classes"] = {k: cls.count(k) for k in set(cls)}

# ---------------------------------------------------------------- 5. secondary bones
WAIST_Z = hips.z - 0.02           # skirt chains start here
SKIRT_TOP = hips.z + 0.04         # above: original weights
SKIRT_FULL = hips.z - 0.12        # below: skirt weights only
center = Vector((hips.x, hips.y, 0))
N = a.skirt_chains


def ang(p):
    return math.atan2(p.y - center.y, p.x - center.x)


# hair chains: back left / center / right, front locks left / right
# hanging hair: violet, below the head, above the hips (stray violet texels elsewhere are ignored)
hair_v = [v.index for v, p, c in zip(me.vertices, wpos, cls)
          if c == "hair" and hips.z - 0.2 < p.z < neck_z + 0.10]
hair_set = set(hair_v)
# skirt = every vertex of the lower body shell between the waist and the hem, whatever its colour
# (a colour test leaves stray leg-weighted vertices that tear into spikes); boots stay on the legs
def seg_dist(p, a_, b_):
    ab = b_ - a_
    t = min(1.0, max(0.0, (p - a_).dot(ab) / max(1e-8, ab.length_squared)))
    return (p - (a_ + ab * t)).length


def leg_dist(p):
    """3D distance to the closest lower-leg polyline (knee -> ankle -> toe base -> toe tip)"""
    best = 9.0
    for side in ("Left", "Right"):
        k, f, t = bhead(side + "Leg"), bhead(side + "Foot"), bhead(side + "ToeBase")
        tip = t + (t - f).normalized() * 0.07
        for a_, b_ in ((k, f), (f, t), (t, tip)):
            best = min(best, seg_dist(p, a_, b_))
    return best


LEG_R = 0.09
skirt_v = []
for v, p, c in zip(me.vertices, wpos, cls):
    if p.z < SKIRT_TOP and v.index not in hair_set and not armish(v):
        if c != "white" and p.z < 0.38 and leg_dist(p) < LEG_R:
            continue  # boot / shin (the white dress hem is never a leg)
        if p.z < hem_z - 0.04:
            continue  # soles and heels, below any hem
        skirt_v.append(v.index)

# chain geometry per angle: radius at waist, lowest hem point
chains = []
for i in range(N):
    th = -math.pi + (i + 0.5) * 2 * math.pi / N
    sel = [wpos[j] for j in skirt_v if abs((ang(wpos[j]) - th + math.pi) % (2 * math.pi) - math.pi) < math.pi / N]
    top = [p for p in sel if abs(p.z - WAIST_Z) < 0.05]
    r_top = (sum(math.hypot(p.x - center.x, p.y - center.y) for p in top) / len(top)) if top else 0.12
    low = min(sel, key=lambda p: p.z) if sel else Vector((center.x, center.y, hem_z))
    r_low = math.hypot(low.x - center.x, low.y - center.y)
    d = Vector((math.cos(th), math.sin(th), 0))
    root = Vector((center.x, center.y, WAIST_Z)) + d * (r_top * 0.85)
    tip = Vector((center.x, center.y, low.z)) + d * (r_low * 0.95)
    chains.append({"th": th, "d": d, "root": root, "tip": tip, "name": f"SKIRT_{i}"})


HAIR_TOP = neck_z + 0.10
HAIR_FULL = neck_z - 0.02
fwd = (bhead("headfront") - head_c)
fwd.z = 0
fwd.normalize()  # face direction (Blender -Y before the final turn)


def hair_group(p):
    rel = p - head_c
    f = rel.dot(fwd)
    s = (rel.x if bhead("LeftArm").x > head_c.x else -rel.x)  # >0: character left
    if f > 0.0:
        return "HAIR_FL" if s > 0 else "HAIR_FR"
    if s > 0.05:
        return "HAIR_BL"
    if s < -0.05:
        return "HAIR_BR"
    return "HAIR_BC"


hair_groups = {}
for j in hair_v:
    hair_groups.setdefault(hair_group(wpos[j]), []).append(j)
hair_chains = []
for gname_, idx in sorted(hair_groups.items()):
    pts = [wpos[j] for j in idx]
    top = [p for p in pts if p.z > HAIR_FULL - 0.04] or pts
    root = sum(top, Vector()) / len(top)
    root.z = HAIR_TOP - 0.04
    low = min(pts, key=lambda p: p.z)
    tipv = Vector((sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), low.z))
    if root.z - tipv.z < 0.12:
        continue
    hair_chains.append({"name": gname_, "root": root, "tip": tipv, "verts": idx})
report["hair_chains"] = {c["name"]: [len(c["verts"]), round(c["root"].z - c["tip"].z, 2)] for c in hair_chains}

SEG = 3
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = rig.data.edit_bones
RMi = RM.inverted()


def add_chain(prefix, root, tip, parent):
    names = []
    prev = eb[parent]
    for k in range(SEG):
        h = root.lerp(tip, k / SEG)
        t = root.lerp(tip, (k + 1) / SEG)
        b = eb.new(f"{prefix}_{k + 1}")
        b.head = RMi @ h
        b.tail = RMi @ t
        b.roll = 0.0
        b.parent = prev
        b.use_connect = k > 0
        b.use_deform = True
        prev = b
        names.append(b.name)
    return names


for c in chains:
    c["bones"] = add_chain(c["name"], c["root"], c["tip"], "Hips")
for c in hair_chains:
    c["bones"] = add_chain(c["name"], c["root"], c["tip"], "Spine")  # chest, not Head: hair lying on the back must follow the back
bpy.ops.object.mode_set(mode="OBJECT")
for c in chains + hair_chains:
    for n in c["bones"]:
        if n not in body.vertex_groups:
            body.vertex_groups.new(name=n)
gi = {g.name: g.index for g in body.vertex_groups}
gname = {g.index: g.name for g in body.vertex_groups}
hips_g = gi["Hips"]
head_g = gi["Head"]


def seg_weights(s):
    """s in [0,1] along a 3-bone chain -> {bone k: w}, tent blend between segment centres."""
    t = min(SEG - 1e-4, max(0.0, s * SEG)) - 0.5
    k0 = int(math.floor(t))
    f = t - k0
    out = {}
    if k0 < 0:
        return {0: 1.0}
    if k0 >= SEG - 1:
        return {SEG - 1: 1.0}
    out[k0] = 1 - f
    out[k0 + 1] = f
    return out


def set_weights(v, wd):
    tot = sum(wd.values())
    for g in list(v.groups):
        body.vertex_groups[g.group].remove([v.index])
    for g, w in wd.items():
        if w > 1e-4:
            body.vertex_groups[g].add([v.index], w / tot, "REPLACE")


for j in skirt_v:
    v = me.vertices[j]
    p = wpos[j]
    orig = {g.group: g.weight for g in v.groups}
    # legs never drive the skirt directly: move their share to the hips
    base = {}
    for g, w in orig.items():
        key = hips_g if g in leg_bones else g
        base[key] = base.get(key, 0) + w
    phi = ang(p)
    x = (phi + math.pi) / (2 * math.pi) * N - 0.5
    i0 = int(math.floor(x)) % N
    f = x - math.floor(x)
    f = f * f * (3 - 2 * f)
    sk = {}
    for ci, cw in ((i0, 1 - f), ((i0 + 1) % N, f)):
        c = chains[ci]
        s = (c["root"].z - p.z) / max(0.05, c["root"].z - c["tip"].z)
        for k, w in seg_weights(s).items():
            g = gi[c["bones"][k]]
            sk[g] = sk.get(g, 0) + w * cw
    b = smoothstep(SKIRT_TOP, SKIRT_FULL, p.z)
    wd = {}
    for g, w in base.items():
        wd[g] = wd.get(g, 0) + w * (1 - b)
    for g, w in sk.items():
        wd[g] = wd.get(g, 0) + w * b
    set_weights(v, wd)

for c in hair_chains:
    for j in c["verts"]:
        v = me.vertices[j]
        p = wpos[j]
        orig = {g.group: g.weight for g in v.groups}
        s = (c["root"].z - p.z) / max(0.05, c["root"].z - c["tip"].z)
        ch = {gi[c["bones"][k]]: w for k, w in seg_weights(max(0.0, s)).items()}
        b = smoothstep(HAIR_TOP, HAIR_FULL, p.z)
        wd = {}
        # above the blend the hair belongs to the head only (not to neck/spine/shoulders)
        wd[head_g] = (1 - b)
        for g, w in ch.items():
            wd[g] = wd.get(g, 0) + w * b
        set_weights(v, wd)

# smooth the new weights a little, then 4 influences max
# Laplacian smoothing of the rebuilt weights (graph neighbours), then 4 influences max
nbrs = [[] for _ in me.vertices]
for e in me.edges:
    i, j = e.vertices
    nbrs[i].append(j)
    nbrs[j].append(i)
touched = set(skirt_v) | set(hair_v)
ring = set(touched)
for j in touched:
    ring.update(nbrs[j])
wmap = {j: {g.group: g.weight for g in me.vertices[j].groups} for j in ring}
for _ in range(2):
    nxt = {}
    for j in touched:
        acc = {}
        for g, w in wmap[j].items():
            acc[g] = acc.get(g, 0) + 0.5 * w
        nb = nbrs[j]
        for k in nb:
            for g, w in wmap.get(k, {}).items():
                acc[g] = acc.get(g, 0) + 0.5 * w / len(nb)
        nxt[j] = acc
    wmap.update(nxt)
for j in touched:
    top = sorted(wmap[j].items(), key=lambda kv: -kv[1])[:4]
    set_weights(me.vertices[j], dict(top))
for v in me.vertices:
    if len(v.groups) > 4:
        top = sorted(((g.group, g.weight) for g in v.groups), key=lambda kv: -kv[1])[:4]
        set_weights(v, dict(top))
report["skirt_verts"] = len(skirt_v)

# cut the skirt free from the boots: faces bridging skirt-driven and leg-driven vertices would
# stretch into sheets when a foot swings out from under the hem (the hole is hidden by the hem)
skirt_groups = {gi[n] for c in chains for n in c["bones"]}
leg_groups = {gi[n] for n in gi if any(k in n for k in ("Leg", "Foot", "Toe"))}


def dominant(v):
    return max(v.groups, key=lambda g: g.weight).group if len(v.groups) else -1


dom = [dominant(v) for v in me.vertices]
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
kill = []
for f in bm.faces:
    ds = [dom[v.index] for v in f.verts]
    if any(d in skirt_groups for d in ds) and any(d in leg_groups for d in ds):
        kill.append(f)
bmesh.ops.delete(bm, geom=kill, context="FACES_ONLY")
bm.to_mesh(me)
bm.free()
report["bridge_faces_cut"] = len(kill)
report["hair_verts"] = len(hair_v)

# ---------------------------------------------------------------- 6a. staff (before the clip bake)
sc = bpy.context.scene
pbs = rig.pose.bones
staff = None
if not a.no_staff:
    bm = bmesh.new()
    def ring_mesh(z0, z1, r0, r1, seg=8):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r0, radius2=r1, depth=z1 - z0,
                              matrix=Matrix.Translation((0, 0, (z0 + z1) / 2)))
    L = 1.42
    parts = [  # (z0, z1, r0, r1, material index)
        (0.0, 0.03, 0.012, 0.017, 0),     # foot
        (0.03, L - 0.12, 0.017, 0.016, 0),  # shaft
        (0.50, 0.70, 0.021, 0.021, 1),    # purple wrap (grip)
        (L - 0.12, L - 0.05, 0.016, 0.030, 0),  # head flare
        (L - 0.05, L, 0.030, 0.012, 0),
    ]
    mats = []
    for nm, col in (("Fern_Staff_Wood", (0.36, 0.22, 0.12, 1)), ("Fern_Staff_Wrap", (0.36, 0.20, 0.52, 1))):
        m = bpy.data.materials.new(nm)
        m.use_nodes = True
        p = m.node_tree.nodes.get("Principled BSDF")
        p.inputs["Base Color"].default_value = col
        p.inputs["Roughness"].default_value = 1.0
        p.inputs["Metallic"].default_value = 0.0
        mats.append(m)
    for z0, z1, r0, r1, mi in parts:
        before = set(bm.faces)
        ring_mesh(z0, z1, r0, r1, 10)
        for f in bm.faces:
            if f not in before:
                f.material_index = mi
                f.smooth = False
    sme = bpy.data.meshes.new("Fern_Staff")
    bm.to_mesh(sme)
    bm.free()
    staff = bpy.data.objects.new("Staff", sme)
    for m in mats:
        sme.materials.append(m)
    sc.collection.objects.link(staff)
    # orient upright in the middle of the idle clip, grip (wrap centre) in the right palm
    idle = clips.get("idle")
    rig.animation_data.action = idle
    if idle and idle.slots:
        rig.animation_data.action_slot = idle.slots[0]
    sc.frame_set(int(sum(idle.frame_range) / 2) if idle else 1)
    bpy.context.view_layer.update()
    hand = pbs["RightHand"]
    fore = pbs["RightForeArm"]
    wrist = RM @ hand.head
    hand_dir = (wrist - RM @ fore.head).normalized()
    palm = wrist + hand_dir * 0.065
    # rigid skin on RightHand (robust in glTF, unlike bone-parented objects): vertices are placed for
    # the idle pose, then mapped back to the rest pose through the hand's pose -> rest transform
    tilt = Matrix.Rotation(math.radians(8), 4, fwd.cross(Vector((0, 0, 1))))
    world_idle = Matrix.Translation(palm) @ tilt @ Matrix.Translation((0, 0, -0.60))
    to_rest = RM @ bones["RightHand"].matrix_local @ hand.matrix.inverted() @ RM.inverted()
    sme.transform(RM.inverted() @ to_rest @ world_idle)
    staff.parent = rig
    staff.matrix_world = RM.copy()
    # own bone at the grip, child of RightHand: keyed per clip so the staff pivots in the palm and
    # stays near upright while walking (a rigid hand attachment swings it flat at every arm swing)
    grip_rest = to_rest @ palm
    up_rest = (to_rest.to_3x3() @ (tilt.to_3x3() @ Vector((0, 0, 1)))).normalized()
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    sb = rig.data.edit_bones.new("Staff")
    sb.head = RMi @ grip_rest
    sb.tail = RMi @ (grip_rest + up_rest * 0.3)
    sb.parent = rig.data.edit_bones["RightHand"]
    sb.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    vg = staff.vertex_groups.new(name="Staff")
    vg.add(list(range(len(sme.vertices))), 1.0, "REPLACE")
    mod = staff.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    rig.animation_data.action = None
    for pb in pbs:
        pb.matrix_basis.identity()
    report["staff_tris"] = len(sme.polygons)


# ---------------------------------------------------------------- 6. skirt follow per clip
pbs = rig.pose.bones
H_rest = bones["Hips"].matrix_local
H_rest_i = H_rest.inverted()
legs = {}
for side in ("Left", "Right"):
    legs[side] = (side + "Leg", side + "Foot")
for c in chains:
    c["root_loc"] = H_rest_i @ (RMi @ c["root"])
    c["tip_loc"] = H_rest_i @ (RMi @ c["tip"])
    c["d_loc"] = (H_rest_i.to_3x3() @ (RMi.to_3x3() @ c["d"])).normalized()
    c["M_loc"] = H_rest_i @ bones[c["bones"][0]].matrix_local
left_dir = (H_rest_i @ bones["LeftUpLeg"].head_local) - (H_rest_i @ bones["RightUpLeg"].head_local)
left_dir.normalize()


def leg_point(side, pose):
    kn, an = legs[side]
    if pose:
        k = pbs[kn].head
        f = pbs[an].head
        Hm = pbs["Hips"].matrix
    else:
        k = bones[kn].head_local
        f = bones[an].head_local
        Hm = H_rest
    return Hm.inverted() @ k.lerp(f, 0.6)


rest_leg = {s: leg_point(s, False) for s in legs}
max_push = 0.32 / RM.to_scale().x  # armature space may be in cm (Meshy rigs carry a 0.01 scale)
sc = bpy.context.scene
lat = (RMi.to_3x3() @ Vector((1, 0, 0))).normalized()  # character's left-right axis, armature space
# rotating about +X by a negative angle lifts a face that looks toward -Y (pre-turn Meshy layout)
head_q = Quaternion(lat, math.radians(-a.head_up) * (1 if fwd.y < 0 else -1))
# chin up, expressed in the Head bone's own rest frame and applied to its existing keys (the clip
# keys sit on fractional frames: inserting keys at integer frames would make the head jitter)
Rh = bones["Head"].matrix_local.to_quaternion()
C = Rh.inverted() @ head_q @ Rh
staff_w = dict((kv.split("=")[0], float(kv.split("=")[1])) for kv in a.staff_upright.split(","))
up_arm = (RMi.to_3x3() @ Vector((0, 0, 1))).normalized()
if a.head_up:
    for act in clips.values():
        fcs = {fc.array_index: fc for fc in channelbag(act).fcurves
               if fc.data_path == 'pose.bones["Head"].rotation_quaternion'}
        if len(fcs) == 4 and len({len(fc.keyframe_points) for fc in fcs.values()}) == 1:
            for k in range(len(fcs[0].keyframe_points)):
                q = Quaternion([fcs[j].keyframe_points[k].co.y for j in range(4)])
                q2 = C @ q
                for j in range(4):
                    fcs[j].keyframe_points[k].co.y = q2[j]
                    fcs[j].keyframe_points[k].interpolation = "LINEAR"
            for fc in fcs.values():
                fc.update()
for name, act in clips.items():
    rig.animation_data.action = act
    if act.slots:
        rig.animation_data.action_slot = act.slots[0]
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    for fr in range(f0, f1 + 1):
        sc.frame_set(fr)
        if staff:
            # staff: pivot in the palm toward upright, by the clip's weight
            w = staff_w.get(name, 0.0)
            pb = pbs["Staff"]
            pb.matrix_basis.identity()
            bpy.context.view_layer.update()
            M = pb.matrix.copy()
            cur = (M.to_3x3() @ Vector((0, 1, 0))).normalized()
            q = Quaternion().slerp(cur.rotation_difference(up_arm), w)
            hp = M.translation.copy()
            pb.matrix = Matrix.Translation(hp) @ q.to_matrix().to_4x4() @ Matrix.Translation(-hp) @ M
        delta = {s: leg_point(s, True) - rest_leg[s] for s in legs}
        Hm = pbs["Hips"].matrix
        for c in chains:
            d = c["d_loc"]
            # hem must clear the leg that moves outward along this chain's direction
            out = max(0.0, delta["Left"].dot(d), delta["Right"].dot(d)) * 1.05
            wl = 0.5 + 0.5 * left_dir.dot(d)
            avg = delta["Left"] * wl + delta["Right"] * (1 - wl)
            tang = avg - d * avg.dot(d)
            tang.z = 0
            v = d * out + tang * 0.7
            if v.length > max_push:  # keep the coat from ballooning on big strides
                v *= max_push / v.length
            R, T = c["root_loc"], c["tip_loc"]
            q = (T - R).rotation_difference((T + v) - R)
            Ml = Matrix.Translation(R) @ q.to_matrix().to_4x4() @ Matrix.Translation(-R) @ c["M_loc"]
            pb = pbs[c["bones"][0]]
            pb.matrix = Hm @ Ml
        bpy.context.view_layer.update()
        for c in chains:
            pbs[c["bones"][0]].keyframe_insert("rotation_quaternion", frame=fr, group=c["bones"][0])
        if staff:
            pbs["Staff"].keyframe_insert("rotation_quaternion", frame=fr, group="Staff")
    report.setdefault("skirt_baked", []).append(name)

# seamless loops: ease the last frames toward the first pose (quaternions and locations)
LOOP_BLEND = 4
for name in a.loop.split(","):
    act = clips.get(name)
    if not act:
        continue
    for fc in channelbag(act).fcurves:
        kps = fc.keyframe_points
        if len(kps) < LOOP_BLEND + 2:
            continue
        first = kps[0].co.y
        n = len(kps)
        for k in range(LOOP_BLEND):
            i = n - LOOP_BLEND + k
            t = (k + 1) / LOOP_BLEND
            kps[i].co.y = kps[i].co.y * (1 - t) + first * t
        fc.update()
rig.animation_data.action = None
for pb in pbs:
    pb.matrix_basis.identity()

# ---------------------------------------------------------------- 7. face normals
face_v = [v.index for v, p, c in zip(me.vertices, wpos, cls)
          if c == "skin" and p.z > neck_z + 0.08 and (p - head_c).dot(fwd) > -0.02]
sphere_c = head_c + Vector((0, 0, 0.08)) - fwd * 0.04
if face_v:
    fset = set(face_v)
    me.calc_normals_split() if hasattr(me, "calc_normals_split") else None
    normals = [Vector(ln.vector) for ln in me.corner_normals] if hasattr(me, "corner_normals") else None
    if normals is not None:
        for loop in me.loops:
            if loop.vertex_index in fset:
                p = wpos[loop.vertex_index]
                sph = BMi.to_3x3() @ (p - sphere_c).normalized()
                normals[loop.index] = normals[loop.index].lerp(sph, 0.75).normalized()
        me.normals_split_custom_set(normals)
report["face_verts"] = len(face_v)

# ---------------------------------------------------------------- 9. NLA, orientation, export
for name, act in clips.items():
    tr = rig.animation_data.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(act.frame_range[0]), act)
    if act.slots:
        st.action_slot = act.slots[0]
    tr.mute = True
report["clips"] = {n: [round(x, 1) for x in act.frame_range] for n, act in clips.items()}

for o in list(bpy.data.objects):
    if o not in (rig, body, staff):
        bpy.data.objects.remove(o)
hf, hd = bones.get("headfront"), bones.get("Head")
if ((rig.matrix_world @ hf.head_local) - (rig.matrix_world @ hd.head_local)).y < 0:
    rig.rotation_mode = "XYZ"
    rig.rotation_euler = (0.0, 0.0, math.pi)
    bpy.context.view_layer.update()
    sel = [o for o in (rig, body, staff) if o]
    with bpy.context.temp_override(object=rig, active_object=rig, selected_objects=sel,
                                   selected_editable_objects=sel):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
bpy.context.view_layer.update()
pts = [body.matrix_world @ v.co for v in body.data.vertices]
zmin = min(p.z for p in pts)
rig.location.z -= zmin
bpy.context.view_layer.update()
pts = [body.matrix_world @ v.co for v in body.data.vertices]
report["height_m"] = round(max(p.z for p in pts) - min(p.z for p in pts), 3)
report["feet_z"] = round(min(p.z for p in pts), 4)
d = (rig.matrix_world @ bones["headfront"].head_local) - (rig.matrix_world @ bones["Head"].head_local)
report["face_dir_blender"] = [round(x, 3) for x in d.normalized()]
report["bones"] = len(bones)
report["skirt_bones"] = [c["bones"] for c in chains]
report["hair_bones"] = [c["bones"] for c in hair_chains]

if a.blend:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.blend))

os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=os.path.abspath(a.out), export_format="GLB", use_selection=False,
    export_animation_mode="NLA_TRACKS", export_anim_slide_to_zero=True, export_force_sampling=True,
    export_optimize_animation_size=True, export_skins=True, export_influence_nb=4, export_morph=False,
    export_apply=False, export_yup=True, export_image_format="WEBP", export_image_quality=88,
    export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
    export_cameras=False, export_lights=False, export_def_bones=False)
report["glb_bytes"] = os.path.getsize(a.out)
print("@@REPORT@@" + json.dumps(report))
