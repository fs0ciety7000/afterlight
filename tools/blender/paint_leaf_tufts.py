"""Paint stylized leaf-tuft sprites (RGBA) for card canopies, procedurally (no fal call).

Each tuft is a scalloped cluster of small pointed leaves, lit from the top in three or four flat tones
with a thin dark edge, like the painted canopies of our concept sheet (art/source/env/sheet2_nature.png).
Used by tools/blender/build_foliage.py, which packs the tufts next to the trunk albedo in one atlas.

  python3 tools/blender/paint_leaf_tufts.py out.png golden [seed] [fruit]
Palettes: see PALETTES (sampled with k-means from our own concept cut-outs).
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

# dark, mid, light, highlight, edge
PALETTES = {
    "golden": ["#c0824a", "#dfa65c", "#efc078", "#fbd698", "#7a4c33"],
    "sage": ["#8a8a52", "#adaa6a", "#c9c789", "#e0dca4", "#55522f"],
    "russet": ["#8f5a40", "#bb7f50", "#d99c62", "#efc08a", "#5f3626"],
    "amber": ["#b77436", "#d4974a", "#e6b25e", "#f5cf86", "#6e4426"],
    "orchard": ["#4f7a3e", "#6d9a4c", "#8db85e", "#b4d27c", "#2f4a28"],
    "orchard_dark": ["#41683a", "#5b8644", "#78a453", "#9fc16c", "#283f24"],
}
FRUIT = ["#e2863a", "#f0a44a", "#c9552f"]


def _hex(c: str) -> tuple:
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def leaf_poly(cx: float, cy: float, length: float, width: float, ang: float) -> list:
    # ovate birch leaf: round base, pointed tip; 10 points
    pts = []
    for k in range(11):
        t = k / 10.0
        r = math.sin(math.pi * t) * (1.0 - 0.45 * t)
        pts.append((t * length, r * width * 0.5))
    pts += [(x, -y) for x, y in reversed(pts[1:-1])]
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def paint(palette: str, seed: int = 1, fruit: bool = False, size: int = 512, fruit_colors=None,
          fruit_count=(5, 8), fruit_size=(0.026, 0.034)) -> Image.Image:
    rnd = random.Random(seed)
    s = size * 2  # supersample
    dark, mid, light, high, edge = [_hex(c) for c in PALETTES[palette]]
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # cloud of 6 lobes; leaves are scattered inside, pointing outwards
    lobes = [(0.5, 0.42, 0.24)]
    for k in range(6):
        a = k / 6.0 * math.tau + rnd.uniform(-0.3, 0.3)
        lobes.append((0.5 + math.cos(a) * 0.2, 0.47 + math.sin(a) * 0.17, rnd.uniform(0.15, 0.2)))

    def inside(x: float, y: float) -> bool:
        return any((x - lx) ** 2 + (y - ly) ** 2 < lr * lr for lx, ly, lr in lobes)

    # dark body so gaps between leaves read as depth, not holes
    for lx, ly, lr in lobes:
        r = lr * 0.92 * s
        d.ellipse((lx * s - r, ly * s - r, lx * s + r, ly * s + r), fill=dark + (255,))
    leaves = []
    while len(leaves) < 115:
        x, y = rnd.random(), rnd.random()
        if not inside(x, y):
            continue
        leaves.append((x, y))
    leaves.sort(key=lambda p: -p[1])  # paint from the bottom up so upper (lit) leaves overlap
    for x, y in leaves:
        ang = math.atan2(y - 0.5, x - 0.5) + rnd.uniform(-0.7, 0.7)
        length = rnd.uniform(0.1, 0.14) * s
        # light from the top: tone by height plus noise
        lit = (1.0 - y) * 1.25 + rnd.uniform(-0.3, 0.3) - 0.15
        col = dark if lit < 0.15 else mid if lit < 0.5 else light if lit < 0.85 else high
        poly = leaf_poly(x * s, y * s, length, length * rnd.uniform(0.5, 0.62), ang)
        d.polygon(poly, fill=col + (255,))
        if rnd.random() < 0.35:  # painted vein
            ex = x * s + math.cos(ang) * length * 0.7
            ey = y * s + math.sin(ang) * length * 0.7
            vein = tuple(max(0, c - 22) for c in col)
            d.line((x * s, y * s, ex, ey), fill=vein + (255,), width=max(2, s // 400))
    if fruit:
        for k in range(rnd.randint(*fruit_count)):
            while True:
                x, y = rnd.uniform(0.2, 0.8), rnd.uniform(0.3, 0.8)
                if inside(x, y):
                    break
            r = rnd.uniform(*fruit_size) * s
            c = _hex(rnd.choice(fruit_colors or FRUIT))
            d.ellipse((x * s - r, y * s - r, x * s + r, y * s + r), fill=c + (255,))
            hr = r * 0.35
            hx, hy = x * s - r * 0.35, y * s - r * 0.35
            d.ellipse((hx - hr, hy - hr, hx + hr, hy + hr), fill=(255, 226, 170, 255))
    # thin dark edge around the whole silhouette
    alpha = img.getchannel("A")
    grown = alpha.filter(ImageFilter.MaxFilter(7))
    base = Image.new("RGBA", (s, s), edge + (0,))
    base.putalpha(grown)
    base.alpha_composite(img)
    out = base.resize((size, size), Image.LANCZOS)
    # binary-ish alpha for alpha scissor, colour bled under the transparent texels (mip-safe)
    a = out.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rgb = Image.new("RGB", (size, size), dark)
    rgb.paste(out.convert("RGB"), mask=a)
    res = rgb.convert("RGBA")
    res.putalpha(a)
    return res


if __name__ == "__main__":
    out, pal = sys.argv[1], sys.argv[2]
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    paint(pal, seed, len(sys.argv) > 4 and sys.argv[4] == "fruit").save(out)
    print(out)
