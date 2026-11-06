"""Repaint the market-stall awning with clean painted stripes (the generated texture was patchy).

  blender -b --factory-startup -P tools/blender/repaint_awning.py -- assets/environment/props/stall.glb

Awning faces = upper part of the stall whose albedo is maroon / pink / cream. Their UV triangles are
rasterised into the base colour; each texel gets a stripe colour from its 3D position along the awning,
so stripes run straight across UV seams. Underside faces get a darker tone. Writes the new texture to
art/source/env/tex/stall.png (used by build_env_kit.py) and re-exports the GLB in place.
"""
import colorsys
import math
import os
import sys

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
dst = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
STRIPE_M = 0.34
CREAM = np.array([0.94, 0.88, 0.74])
ROSE = np.array([0.74, 0.33, 0.29])
UNDER = 0.72  # underside darkening

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=dst)
obj = next(o for o in bpy.data.objects if o.type == "MESH")
me = obj.data
img = next(i for i in bpy.data.images if i.size[0] > 0)
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
uv = me.uv_layers.active.data
zs = [v.co.z for v in me.vertices]
H = max(zs) - min(zs)
z0 = min(zs)
me.calc_loop_triangles()


def tex_at(u: float, v: float) -> np.ndarray:
    return px[min(h - 1, max(0, int(v * h))), min(w - 1, max(0, int(u * w))), :3]


sel = []
for t in me.loop_triangles:
    c = sum((me.vertices[i].co for i in t.vertices), start=me.vertices[t.vertices[0]].co * 0) / 3
    if c.z - z0 < 0.6 * H:
        continue
    us = [uv[li].uv for li in t.loops]
    # majority vote over the corners and the centroid: wood (orange-brown) is everything else
    votes = 0
    for su, sv in [*((x[0], x[1]) for x in us), (sum(x[0] for x in us) / 3, sum(x[1] for x in us) / 3)]:
        hh, s, vv = colorsys.rgb_to_hsv(*[float(x) for x in tex_at(su % 1, sv % 1)])
        wood = 0.02 <= hh <= 0.16 and s > 0.28
        votes += 0 if wood else 1
    if votes >= 3:
        sel.append(t)
print("awning triangles", len(sel), "of", len(me.loop_triangles))
pos = np.array([[me.vertices[i].co[:] for i in t.vertices] for t in sel])
span = pos.reshape(-1, 3).max(0) - pos.reshape(-1, 3).min(0)
axis = 0 if span[0] > span[1] else 1
for t, P in zip(sel, pos):
    UV = np.array([[uv[li].uv[0] * w, uv[li].uv[1] * h] for li in t.loops])
    under = t.normal.z < -0.2
    x0, y0 = np.floor(UV.min(0) - 1).astype(int)
    x1, y1 = np.ceil(UV.max(0) + 1).astype(int)
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    a, b, c = UV
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-9:
        continue
    l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
    l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
    l3 = 1 - l1 - l2
    tol = -1.5 / max(1.0, math.sqrt(abs(den)))  # grow ~1.5 px to hide seams
    m = (l1 >= tol) & (l2 >= tol) & (l3 >= tol)
    along = l1 * P[0, axis] + l2 * P[1, axis] + l3 * P[2, axis]
    stripe = (np.floor(along / STRIPE_M) % 2).astype(bool)
    col = np.where(stripe[..., None], ROSE, CREAM) * (UNDER if under else 1.0)
    for yy, xx in zip(*np.nonzero(m)):
        X, Y = int(xs[yy, xx]), int(ys[yy, xx])
        if 0 <= X < w and 0 <= Y < h:
            px[Y, X, :3] = col[yy, xx]
img.pixels[:] = px.ravel()
img.update()
tex_path = os.path.join(ROOT, "art", "source", "env", "tex", "stall.png")
img.filepath_raw = tex_path
img.file_format = "PNG"
img.save()
img.unpack(method="REMOVE") if img.packed_file else None
img.filepath = tex_path
img.reload()  # the exporter re-encodes from this file, not from the GLB's original bytes
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=dst, export_format="GLB", use_selection=True, export_apply=True,
    export_image_format="JPEG", export_jpeg_quality=86, export_animations=False,
    export_materials="EXPORT", export_normals=True, export_texcoords=True, export_tangents=False,
    export_yup=True,
)
print("repainted", dst)
