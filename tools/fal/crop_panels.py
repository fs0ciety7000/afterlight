#!/usr/bin/env python3
"""Cut a row of portrait panels (separated by white gaps) into square WebP portraits.

  python3 tools/fal/crop_panels.py art/source/portraits/npc_portraits.png assets/textures/portraits 256 \
      npc_bastien npc_maelle npc_aubelin_merchant
Each square is the panel width, from the panel top (head and shoulders, like fern.png).
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image


def runs(mask: np.ndarray) -> list[tuple[int, int]]:
    out, start = [], None
    for i, v in enumerate(list(mask) + [False]):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append((start, i))
            start = None
    return out


def main() -> None:
    src, dst, size, names = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(np.int16)
    white = (a.min(axis=2) > 235)
    cols = runs(white.mean(axis=0) < 0.6)
    cols = [c for c in cols if c[1] - c[0] > im.width * 0.15][: len(names)]
    for name, (x0, x1) in zip(names, cols):
        rows = runs(white[:, x0:x1].mean(axis=1) < 0.6)
        y0, y1 = max(rows, key=lambda r: r[1] - r[0])
        inset = 6  # stay inside the panel edge
        x0, x1, y0 = x0 + inset, x1 - inset, y0 + inset
        side = min(x1 - x0, y1 - inset - y0)
        sq = im.crop((x0, y0, x0 + side, y0 + side)).resize((size, size), Image.LANCZOS)
        dst.mkdir(parents=True, exist_ok=True)
        sq.save(dst / f"{name}.webp", "WEBP", quality=90, method=6)
        print(name, (x0, y0, side))


if __name__ == "__main__":
    main()
