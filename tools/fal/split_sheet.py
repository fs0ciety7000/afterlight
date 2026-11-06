#!/usr/bin/env python3
"""Split a concept sheet (objects on a flat grey background) into one RGBA cutout per object.

The background colour is sampled from the border; pixels close to it become transparent, the
largest connected regions become separate objects, sorted left-to-right then top-to-bottom.
Avoids one background-removal call per object.

  python3 tools/fal/split_sheet.py art/source/env/sheet2_props.png art/source/env/cut \
      well fence stall cart lantern barrels bridge
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def main() -> None:
    src, out_dir, names = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3:]
    out_dir.mkdir(parents=True, exist_ok=True)
    im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    h, w, _ = im.shape
    border = np.concatenate([im[:8].reshape(-1, 3), im[-8:].reshape(-1, 3),
                             im[:, :8].reshape(-1, 3), im[:, -8:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    dist = np.linalg.norm(im - bg, axis=2)
    fg = dist > 14.0
    fg = ndimage.binary_opening(fg, iterations=2)
    fg = ndimage.binary_closing(fg, iterations=3)
    # fill only small holes: real gaps (between fence rails, under an awning) stay transparent
    holes, nh = ndimage.label(ndimage.binary_fill_holes(fg) & ~fg)
    if nh:
        hole_sizes = ndimage.sum(np.ones_like(fg), holes, range(1, nh + 1))
        small = np.isin(holes, 1 + np.nonzero(hole_sizes < 0.0004 * h * w)[0])
        fg = fg | small
    # group parts of one object (e.g. a sign hanging off a house) with a generous dilation
    grouped = ndimage.binary_dilation(fg, iterations=int(0.012 * w))
    labels, n = ndimage.label(grouped)
    sizes = ndimage.sum(fg, labels, range(1, n + 1))
    keep = [i + 1 for i in np.argsort(sizes)[::-1][: len(names)]]
    boxes = []
    for lab in keep:
        ys, xs = np.where((labels == lab) & fg)
        boxes.append((xs.min(), ys.min(), xs.max(), ys.max(), lab))
    # reading order: rows (by vertical centre, 1/4 image tolerance) then x
    boxes.sort(key=lambda b: (round(((b[1] + b[3]) / 2) / (h / 4)), b[0]))
    # soft alpha from the colour distance, restricted to the object's own region
    alpha = np.clip((dist - 10.0) / 18.0, 0.0, 1.0)
    rgb = im.astype(np.uint8)
    for name, (x0, y0, x1, y1, lab) in zip(names, boxes):
        region = ndimage.binary_dilation((labels == lab) & fg, iterations=3)
        a = np.where(region, np.where(fg, np.maximum(alpha, 0.0), 0.0), 0.0)
        a = np.where(fg & (dist > 20.0), 1.0, a)
        pad = 24
        x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
        x1, y1 = min(w, x1 + pad), min(h, y1 + pad)
        rgba = np.dstack([rgb[y0:y1, x0:x1], (a[y0:y1, x0:x1] * 255).astype(np.uint8)])
        # square canvas, object centred, so image-to-3D sees the whole silhouette
        side = max(x1 - x0, y1 - y0) + 2 * pad
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(Image.fromarray(rgba, "RGBA"), ((side - (x1 - x0)) // 2, (side - (y1 - y0)) // 2))
        canvas.save(out_dir / f"{name}.png")
        print(name, (x0, y0, x1, y1), canvas.size)


if __name__ == "__main__":
    main()
