"""Side-by-side v0 / v1 sheet from two shot folders (same preview scene and camera).

Usage: python3 tools/fal/compare_shots.py v0_dir v1_dir out.jpg
Rows: day idle (3/4 gameplay camera), walk from behind, cast, close-up. Crops the centre of each frame.
"""
import os
import sys

from PIL import Image, ImageDraw

v0, v1, out = sys.argv[1:4]
rows = ["shot_day_idle_34", "shot_day_walk_back", "shot_day_cast", "shot_day_closeup"]
crop = {"shot_day_closeup": (360, 200, 1560, 1080)}
W, H = 640, 470
sheet = Image.new("RGB", (W * 2, (H + 4) * len(rows) + 40), (36, 34, 40))
d = ImageDraw.Draw(sheet)
d.text((12, 12), "Fern v0", fill=(235, 235, 235))
d.text((W + 12, 12), "Fern v1", fill=(235, 235, 235))
for r, name in enumerate(rows):
    for c, folder in enumerate((v0, v1)):
        p = os.path.join(folder, name + ".jpg")
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        box = crop.get(name, (560, 200, 1360, 787))
        im = im.crop(box).resize((W, H), Image.LANCZOS)
        sheet.paste(im, (c * W, 40 + r * (H + 4)))
    d.text((8, 40 + r * (H + 4) + 6), name.replace("shot_", ""), fill=(20, 20, 20))
sheet.save(out, quality=88)
print(out)
