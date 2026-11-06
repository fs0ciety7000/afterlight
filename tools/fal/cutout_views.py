"""Cut flat-grey-background concept views into RGBA images (no fal call needed).

Usage:
  python3 tools/fal/cutout_views.py front.png views.png out_dir
front.png: single front view; views.png: side (left half) + back (right half) sheet.
Background = pixels close to the corner grey that are connected to the image border (flood fill),
so grey gaps enclosed by the silhouette stay opaque only if truly enclosed.
Optional: prefix (default fern_v1) and the names of the main view and the two sheet views
(default front,side,back), e.g. `... out_dir mist_wolf side,front,back` for a creature drawn in profile.
Writes out_dir/<prefix>_{front,side,back}_cut.png, each cropped to the figure and padded on a
common canvas so all views share the same figure height (Meshy multi-image wants matching scale).
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


def cut(im: Image.Image, tol: float = 18.0) -> Image.Image:
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    bg = np.median(np.concatenate([a[:8, :8].reshape(-1, 3), a[-8:, -8:].reshape(-1, 3)]), axis=0)
    close = np.linalg.norm(a - bg, axis=2) < tol
    lab, _ = ndimage.label(close)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    mask = ~np.isin(lab, list(border))
    mask = ndimage.binary_opening(mask, iterations=1)
    # keep the largest component only (drops specks)
    lab2, n = ndimage.label(mask)
    if n > 1:
        sizes = ndimage.sum(mask, lab2, range(1, n + 1))
        mask = lab2 == (1 + int(np.argmax(sizes)))
    mask = ndimage.binary_fill_holes(mask) if False else mask
    alpha = (ndimage.gaussian_filter(mask.astype(np.float32), 0.6) * 255).clip(0, 255).astype(np.uint8)
    rgba = np.dstack([a.astype(np.uint8), alpha])
    ys, xs = np.nonzero(mask)
    return Image.fromarray(rgba).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def main() -> None:
    front_p, views_p, out = sys.argv[1:4]
    prefix = sys.argv[4] if len(sys.argv) > 4 else "fern_v1"
    names = sys.argv[5].split(",") if len(sys.argv) > 5 else ["front", "side", "back"]
    front = cut(Image.open(front_p))
    v = Image.open(views_p)
    w, h = v.size
    side = cut(v.crop((0, 0, w // 2, h)))
    back = cut(v.crop((w // 2, 0, w, h)))
    target_h = 1600
    views = [(n, cut_im) for n, cut_im in zip(names, (front, side, back))]
    widths = [round(im.width * target_h / im.height) for _, im in views]
    canvas_w = max(1400, max(widths) + 200)
    for name, im in views:
        s = target_h / im.height
        im = im.resize((max(1, round(im.width * s)), target_h), Image.LANCZOS)
        canvas = Image.new("RGBA", (canvas_w, 1800), (0, 0, 0, 0))
        canvas.paste(im, ((canvas_w - im.width) // 2, 100), im)
        canvas.save(f"{out}/{prefix}_{name}_cut.png")
        print(name, im.size)


if __name__ == "__main__":
    main()
