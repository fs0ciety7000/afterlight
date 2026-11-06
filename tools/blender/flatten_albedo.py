"""Flatten a generated base-colour texture into cel-shading-friendly flat colour regions.

Usage (system python: numpy, scipy, PIL):
  python3 tools/blender/flatten_albedo.py in.png out.png [--k 9] [--keep 0.12] [--size 1024]
                                          [--skin-shift 1.0,0.97,0.94] [--preview preview.png]
- k-means (k clusters, in a perceptual-ish space) over the texels;
- every texel snaps to its cluster colour, keeping `keep` of its own deviation (a hint of detail);
- the label map is mode-filtered (3x3) first, so shading speckles and soft folds disappear;
- texels with sharp local contrast (eyes, mouth, buttons) keep their original colour;
- optional multiply on the skin cluster (the most saturated warm light cluster) to make it less pale.
Baked shadows in AI textures fight the toon shader's bands: this keeps only the material colours.
"""
import argparse

import numpy as np
from PIL import Image
from scipy import ndimage

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("out")
ap.add_argument("--k", type=int, default=9)
ap.add_argument("--keep", type=float, default=0.12)
ap.add_argument("--size", type=int, default=1024)
ap.add_argument("--skin-shift", default="1.0,0.95,0.9")
ap.add_argument("--preview")
ap.add_argument("--seed", type=int, default=7)
ap.add_argument("--dark-target", default="#37323b", help="colour for the darkest big cluster (coat), '' = keep")
ap.add_argument("--white-max", type=float, default=0.93, help="cap on the lightest cluster value")
ap.add_argument("--detail", type=float, default=1.6, help="sobel threshold above which texels are kept")
a = ap.parse_args()

im = Image.open(a.src).convert("RGB").resize((a.size, a.size), Image.LANCZOS)
rgb = np.asarray(im).astype(np.float32) / 255.0
h, w, _ = rgb.shape
x = rgb.reshape(-1, 3)
# perceptual-ish space: sqrt (gamma-like) plus a luma axis, weights more on chroma
lum = x @ np.array([0.299, 0.587, 0.114], np.float32)
feat = np.c_[x - lum[:, None], lum[:, None] * 0.8] if False else np.c_[(x - lum[:, None]) * 1.6, lum]

rng = np.random.default_rng(a.seed)
sample = feat[rng.choice(len(feat), 60000, replace=False)]
# k-means++ init
cent = [sample[rng.integers(len(sample))]]
for _ in range(a.k - 1):
    d = np.min(((sample[:, None, :] - np.array(cent)[None]) ** 2).sum(-1), axis=1)
    cent.append(sample[rng.choice(len(sample), p=d / d.sum())])
cent = np.array(cent)
for _ in range(30):
    lab = np.argmin(((sample[:, None, :] - cent[None]) ** 2).sum(-1), axis=1)
    cent = np.array([sample[lab == i].mean(0) if np.any(lab == i) else cent[i] for i in range(a.k)])

labels = np.empty(len(feat), np.int32)
for s in range(0, len(feat), 200000):
    labels[s:s + 200000] = np.argmin(((feat[s:s + 200000, None, :] - cent[None]) ** 2).sum(-1), axis=1)
labels = labels.reshape(h, w)
# mode filter 3x3: majority label in the neighbourhood
counts = np.stack([ndimage.uniform_filter((labels == i).astype(np.float32), 3) for i in range(a.k)])
labels = np.argmax(counts, axis=0)

# cluster colours = median RGB of their texels (robust to the shading tail)
cols = np.array([np.median(rgb[labels == i], axis=0) if np.any(labels == i) else [0, 0, 0] for i in range(a.k)])
# skin = brightest warm cluster with r > g > b and moderate saturation
warm = [i for i, c in enumerate(cols) if c[0] > c[1] > c[2] and c[0] - c[2] > 0.08 and c.mean() > 0.6]
skin = max(warm, key=lambda i: (labels == i).sum()) if warm else None
if skin is not None:
    cols[skin] = np.clip(cols[skin] * np.array([float(v) for v in a.skin_shift.split(",")]), 0, 1)
sizes = np.array([(labels == i).sum() for i in range(a.k)])
big = [i for i in range(a.k) if sizes[i] > 0.05 * sizes.sum()]
if a.dark_target and big:
    dark = min(big, key=lambda i: cols[i].mean())
    cols[dark] = np.array([int(a.dark_target[j:j + 2], 16) / 255 for j in (1, 3, 5)])
    # small dark-violet clusters on the coat (AI texture spill) join the coat colour
    for i in range(a.k):
        if i not in big and cols[i].mean() < 0.3:
            cols[i] = cols[dark]
if big:
    light = max(big, key=lambda i: cols[i].mean())
    if cols[light].max() > a.white_max:
        cols[light] *= a.white_max / cols[light].max()
flat = cols[labels] + a.keep * (rgb - cols[labels])
# keep painted details (eyes, mouth, buttons, ink lines): sharp local contrast, unlike soft baked shading
g = np.zeros((h, w), np.float32)
for c in range(3):
    g += np.hypot(ndimage.sobel(rgb[..., c], 0), ndimage.sobel(rgb[..., c], 1))
detail = ndimage.maximum_filter(g > a.detail, 3).astype(np.float32)
detail = ndimage.gaussian_filter(detail, 0.8)[..., None]
# details keep their shape but are shifted by their cluster's recolour (eyes stay, coat edges follow)
orig_cols = np.array([np.median(rgb[labels == i], axis=0) if np.any(labels == i) else [0, 0, 0] for i in range(a.k)])
out = flat * (1 - detail) + np.clip(rgb + (cols - orig_cols)[labels], 0, 1) * detail
Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(a.out)
print("clusters", [("#%02x%02x%02x" % tuple((c * 255).astype(int)), int((labels == i).sum())) for i, c in enumerate(cols)],
      "skin", skin)
if a.preview:
    side = Image.new("RGB", (w * 2, h))
    side.paste(im, (0, 0))
    side.paste(Image.open(a.out), (w, 0))
    side.save(a.preview)
