#!/usr/bin/env python3
"""Post-process the fal outputs of the environment kit (no fal call).

  python3 tools/fal/process_env_textures.py props    # Meshy base colours -> flattened 1K (art/source/env/tex/)
  python3 tools/fal/process_env_textures.py ground   # seamless 1K ground tiles (assets/environment/textures/)
  python3 tools/fal/process_env_textures.py cards    # grass / flower clumps -> 4x2 RGBA atlas
  python3 tools/fal/process_env_textures.py backdrop # distant hills + cloister, white keyed out
  python3 tools/fal/process_env_textures.py map      # region map, padded so features clear a 6 % border
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art/source/env"
TEX = ROOT / "assets/environment/textures"


def _arr(im: Image.Image) -> np.ndarray:
    return np.asarray(im).astype(np.float32) / 255.0


def _img(a: np.ndarray, mode: str = "RGB") -> Image.Image:
    return Image.fromarray((np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), mode)


def flatten(a: np.ndarray, lift: float, sat: float) -> np.ndarray:
    """Soften baked shading: lift the darks (the toon shader adds its own shadow band) and add a
    little saturation so lit faces stay painterly instead of grey."""
    lum = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    new_lum = lum ** lift
    out = a * (new_lum / np.maximum(lum, 1e-4))[..., None]
    grey = (out @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
    return grey + (out - grey) * sat


def props() -> None:
    out = SRC / "tex"
    out.mkdir(exist_ok=True)
    for d in sorted((SRC / "raw").iterdir()):
        src = d / f"{d.name}_meshy_7.png"
        if not src.exists():
            continue
        a = _arr(Image.open(src).convert("RGB").resize((1024, 1024), Image.LANCZOS))
        _img(flatten(a, 0.82, 1.08)).save(out / f"{d.name}.png")
        print("prop", d.name)
    for src in sorted(out.glob("*_src.png")):  # embedded textures saved by build_env_kit.py (Tripo)
        name = src.name[: -len("_src.png")]
        a = _arr(Image.open(src).convert("RGB").resize((1024, 1024), Image.LANCZOS))
        _img(flatten(a, 0.82, 1.08)).save(out / f"{name}.png")
        print("prop", name, "(tripo)")


def make_tileable(a: np.ndarray, blend: float = 0.22) -> np.ndarray:
    """Cross-fade the tile with its half-offset copy near the borders: the result wraps seamlessly."""
    h, w, _ = a.shape
    b = np.roll(a, (h // 2, w // 2), axis=(0, 1))
    y = np.minimum(np.arange(h), h - 1 - np.arange(h)) / (h * blend)
    x = np.minimum(np.arange(w), w - 1 - np.arange(w)) / (w * blend)
    m = np.clip(np.minimum(y[:, None], x[None, :]), 0.0, 1.0)
    m = m * m * (3.0 - 2.0 * m)
    return a * m[..., None] + b * (1.0 - m[..., None])


def even_out(a: np.ndarray, amount: float) -> np.ndarray:
    """Remove large-scale brightness blotches that would make the tiling obvious."""
    low = ndimage.gaussian_filter(a, sigma=(a.shape[0] / 6, a.shape[1] / 6, 0), mode="wrap")
    return a - (low - a.reshape(-1, 3).mean(axis=0)) * amount


def ground() -> None:
    TEX.mkdir(parents=True, exist_ok=True)
    # name, blotch removal, saturation, brightness (the raw dirt read as flat orange in game)
    for name, amount, sat, gain in (("grass", 0.8, 1.0, 1.0), ("dirt", 0.7, 0.72, 1.04),
                                    ("cobble", 0.5, 0.85, 1.0), ("forest", 0.7, 0.95, 1.0)):
        a = _arr(Image.open(SRC / f"gen/tex_{name}.png").convert("RGB").resize((1024, 1024), Image.LANCZOS))
        a = make_tileable(even_out(a, amount))
        grey = (a @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
        a = (grey + (a - grey) * sat) * gain
        _img(a).save(TEX / f"ground_{name}.jpg", quality=88)
        print("ground", name)


def _components(path: Path, count: int) -> list[tuple[np.ndarray, tuple[int, int, int, int]]]:
    im = _arr(Image.open(path).convert("RGB"))
    h, w, _ = im.shape
    border = np.concatenate([im[:6].reshape(-1, 3), im[-6:].reshape(-1, 3)])
    dist = np.linalg.norm(im - np.median(border, axis=0), axis=2)
    fg = ndimage.binary_opening(dist > 0.05, iterations=1)
    labels, n = ndimage.label(ndimage.binary_dilation(fg, iterations=int(0.02 * w)))
    sizes = ndimage.sum(fg, labels, range(1, n + 1))
    keep = [i + 1 for i in np.argsort(sizes)[::-1][:count]]
    out = []
    for lab in keep:
        ys, xs = np.where((labels == lab) & fg)
        out.append((lab, (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)))
    out.sort(key=lambda c: (round(((c[1][1] + c[1][3]) / 2) / (h / 3)), c[1][0]))
    alpha = np.clip((dist - 0.035) / 0.08, 0.0, 1.0)
    res = []
    for lab, (x0, y0, x1, y1) in out:
        a = np.where(labels == lab, alpha, 0.0)
        res.append((np.dstack([im, a])[y0:y1, x0:x1], (x0, y0, x1, y1)))
    return res


def cards() -> None:
    cell = 256
    atlas = Image.new("RGBA", (cell * 4, cell * 2), (0, 0, 0, 0))
    for i, (rgba, _box) in enumerate(_components(SRC / "gen/grass_cards.png", 8)):
        # bleed colour into transparent pixels so mipmaps do not darken the edges
        im = _img(rgba, "RGBA")
        k = min((cell - 8) / im.width, (cell - 4) / im.height)
        im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
        cx, cy = (i % 4) * cell, (i // 4) * cell
        atlas.paste(im, (cx + (cell - im.width) // 2, cy + cell - im.height), im)
    a = _arr(atlas)
    solid = a[..., 3] > 0.5
    idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    rgb = a[..., :3][idx[0], idx[1]]
    _img(np.dstack([rgb, a[..., 3]]), "RGBA").save(TEX / "grass_cards.png")
    print("cards atlas", atlas.size)


def backdrop() -> None:
    a = _arr(Image.open(SRC / "gen/backdrop.png").convert("RGB"))
    whiteness = a.min(axis=2)
    alpha = np.clip((0.975 - whiteness) / 0.06, 0.0, 1.0)
    # the sky is everything connected to the top edge that is near-white
    sky = ndimage.label(alpha < 0.5)[0]
    top = set(np.unique(sky[0])) - {0}
    alpha = np.where(np.isin(sky, list(top)), alpha, 1.0)
    alpha = ndimage.gaussian_filter(alpha, 1.2)
    # un-premultiply the white halo on the edges
    rgb = np.where(alpha[..., None] > 0.05, (a - (1.0 - alpha[..., None])) / np.maximum(alpha[..., None], 0.05), a)
    im = _img(np.dstack([rgb, alpha]), "RGBA").resize((2048, 869), Image.LANCZOS)
    im.save(TEX / "backdrop_cloister.png")
    print("backdrop", im.size)


def map_() -> None:
    out = ROOT / "assets/textures/map"
    out.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC / "gen/map_v1.png").convert("RGB")
    w, h = 2560, 1440
    # paper colour from the outer border of the painting
    a = _arr(src)
    paper = np.median(np.concatenate([a[:10].reshape(-1, 3), a[-10:].reshape(-1, 3),
                                      a[:, :10].reshape(-1, 3), a[:, -10:].reshape(-1, 3)]), axis=0)
    scale = 0.93
    inner = src.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
    rng = np.random.default_rng(7)
    noise = ndimage.gaussian_filter(rng.normal(0, 1, (h, w)), 2.0)[..., None] * 0.012
    canvas = _img(np.broadcast_to(paper, (h, w, 3)) + noise)
    # feathered paste: the painting's own paper edge melts into the extended paper
    mask = Image.new("L", inner.size, 0)
    m = np.ones((inner.height, inner.width), np.float32)
    f = int(0.03 * inner.width)
    ramp_x = np.clip(np.minimum(np.arange(inner.width), inner.width - 1 - np.arange(inner.width)) / f, 0, 1)
    ramp_y = np.clip(np.minimum(np.arange(inner.height), inner.height - 1 - np.arange(inner.height)) / f, 0, 1)
    m = np.minimum(ramp_y[:, None], ramp_x[None, :])
    mask = Image.fromarray((m * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(4))
    ox, oy = (w - inner.width) // 2, (h - inner.height) // 2
    canvas.paste(inner, (ox, oy), mask)
    canvas.save(out / "aubelin_vale.jpg", quality=90)
    print("map", canvas.size, "inner offset", ox, oy, "scale", scale)


if __name__ == "__main__":
    {"props": props, "ground": ground, "cards": cards, "backdrop": backdrop, "map": map_}[sys.argv[1]]()
