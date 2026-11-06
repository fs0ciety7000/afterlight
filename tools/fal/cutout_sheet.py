"""Cut a flat-grey-background sheet with N figures side by side into RGBA views (no fal call).

  python3 tools/fal/cutout_sheet.py sheet.png out_dir prefix front,side,back [--height 1600]

The sheet is split into N equal columns (one figure per column); each figure is cut with
cutout_views.cut and pasted on a common canvas at the same figure height, as Meshy multi-image wants.
A single name cuts the whole image (e.g. one 3/4 concept for Tripo image-to-3d).
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cutout_views import cut  # noqa: E402


def clear_holes(src: Image.Image, im: Image.Image, tol: float = 14.0, min_px: int = 2500) -> Image.Image:
    """Make enclosed background-grey regions transparent (gaps between arm and body, hair and robe).

    cut() only removes grey connected to the border; a large enclosed patch of the same grey is
    background seen through a gap, so it goes too. Small patches (eye whites, highlights) stay."""
    a = np.asarray(im).astype(np.float32)
    s = np.asarray(src.convert("RGB")).astype(np.float32)
    bg = np.median(np.concatenate([s[:8, :8].reshape(-1, 3), s[-8:, -8:].reshape(-1, 3)]), axis=0)
    close = (np.linalg.norm(a[..., :3] - bg, axis=2) < tol) & (a[..., 3] > 0)
    lab, n = ndimage.label(close)
    if n:
        sizes = ndimage.sum(close, lab, range(1, n + 1))
        big = np.isin(lab, [i + 1 for i, sz in enumerate(sizes) if sz >= min_px])
        big = ndimage.binary_dilation(big, iterations=2)
        a[..., 3][big] = 0
    return Image.fromarray(a.astype(np.uint8))


def main() -> None:
    src, out, prefix, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(",")
    target_h = int(sys.argv[sys.argv.index("--height") + 1]) if "--height" in sys.argv else 1600
    sheet = Image.open(src)
    w, h = sheet.size
    n = len(names)
    cols = [sheet.crop((i * w // n, 0, (i + 1) * w // n, h)) for i in range(n)]
    cuts = [clear_holes(c, cut(c)) for c in cols]
    widths = [round(c.width * target_h / c.height) for c in cuts]
    canvas_w = max(1400, max(widths) + 200)
    for name, c in zip(names, cuts):
        im = c.resize((max(1, round(c.width * target_h / c.height)), target_h), Image.LANCZOS)
        canvas = Image.new("RGBA", (canvas_w, target_h + 200), (0, 0, 0, 0))
        canvas.paste(im, ((canvas_w - im.width) // 2, 100), im)
        canvas.save(os.path.join(out, f"{prefix}_{name}_cut.png"))
        print(name, im.size)


if __name__ == "__main__":
    main()
