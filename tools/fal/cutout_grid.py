#!/usr/bin/env python3
"""Cut a lineup sheet (C x R equal cells, one figure per cell, flat grey background) into RGBA figures.

  python3 tools/fal/cutout_grid.py sheet.png out_dir --grid 6x1 odile bastien maelle ... [--keep-top 0.22]

split_sheet.py --grid keys every pixel close to the background grey, which also erases light-grey
hair (Odile's silver bun). Here each cell is cut with cutout_views.cut (flood fill from the border,
stopped by the ink outline), then large enclosed background patches (gaps between arm and body) are
cleared by cutout_sheet.clear_holes, except in the top `keep-top` of the figure (hair and head).
Output: <out_dir>/<name>_cut.png, figure centred on a square transparent canvas.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cutout_sheet import clear_holes  # noqa: E402
from cutout_views import cut  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("names", nargs="+")
    ap.add_argument("--grid", default="6x1")
    ap.add_argument("--keep-top", type=float, default=0.22)
    a = ap.parse_args()
    cols, rows = (int(v) for v in a.grid.split("x"))
    sheet = Image.open(a.src).convert("RGB")
    w, h = sheet.size
    for i, name in enumerate(a.names[: cols * rows]):
        cx, cy = i % cols, i // cols
        box = (round(cx * w / cols), round(cy * h / rows), round((cx + 1) * w / cols), round((cy + 1) * h / rows))
        cell = sheet.crop(box)
        flood = cut(cell)
        holes = np.asarray(clear_holes(cell, flood)).copy()
        alpha = np.asarray(flood)[..., 3]
        ys, xs = np.nonzero(alpha > 0)
        top = ys.min() + int(a.keep_top * (ys.max() - ys.min()))
        holes[:top, :, 3] = alpha[:top]  # head and hair: keep the flood-fill cut only
        ys, xs = np.nonzero(holes[..., 3] > 0)
        pad = 12
        x0, y0 = max(0, xs.min() - pad), max(0, ys.min() - pad)
        x1, y1 = min(cell.width, xs.max() + pad), min(cell.height, ys.max() + pad)
        fig = Image.fromarray(holes[y0:y1, x0:x1])
        side = max(fig.width, fig.height)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(fig, ((side - fig.width) // 2, (side - fig.height) // 2))
        canvas.save(os.path.join(a.out, f"{name}_cut.png"))
        print(name, fig.size)


if __name__ == "__main__":
    main()
