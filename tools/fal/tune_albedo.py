"""Readability tweaks on a flattened albedo (after tools/blender/flatten_albedo.py), for the 50 deg camera.

  python3 tools/fal/tune_albedo.py in.png out.png [--gain 1.12] [--glow #a9e4ff] [--darken-grey 0.72]
--gain         multiply every texel (clipped): lifts a texture that Tripo darkened vs the concept;
--glow COLOR   pale cyan-blue texels (runes, visor) snap to COLOR and grow by 2 px, so they still read at 11 m;
--darken-grey  multiply the mid-value, low-saturation texels (a grey robe) so the figure stands out on grass;
               near-black (hair), light (skin) and saturated (ember trim) texels are left as they are.
"""
import argparse

import numpy as np
from PIL import Image
from scipy import ndimage

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("out")
ap.add_argument("--gain", type=float, default=1.0)
ap.add_argument("--glow")
ap.add_argument("--darken-grey", type=float, default=1.0)
a = ap.parse_args()

rgb = np.asarray(Image.open(a.src).convert("RGB")).astype(np.float32) / 255.0
mx, mn = rgb.max(-1), rgb.min(-1)
sat = (mx - mn) / np.maximum(mx, 1e-4)
if a.darken_grey != 1.0:
    grey = (sat < 0.22) & (mx > 0.25) & (mx < 0.6)
    rgb[grey] *= a.darken_grey
if a.gain != 1.0:
    rgb = np.clip(rgb * a.gain, 0, 1)
if a.glow:
    col = np.array([int(a.glow[i:i + 2], 16) / 255 for i in (1, 3, 5)], np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    glow = (b > r + 0.06) & (b > 0.55) & (g > r)
    glow = ndimage.binary_dilation(glow, iterations=2)
    rgb[glow] = col
    print("glow texels", int(glow.sum()))
Image.fromarray((rgb * 255 + 0.5).astype(np.uint8)).save(a.out)
print(a.out)
