"""Compose the manifest written by render_pose_strip.py into one labelled sheet (system python, PIL).
Usage: python3 compose_strip.py manifest.json out.png"""
import json
import shutil
import sys

from PIL import Image, ImageDraw

rows = json.load(open(sys.argv[1]))
first = Image.open(rows[0][1][0][0])
w, h = first.size
cols = max(len(r[1]) for r in rows)
sheet = Image.new("RGB", (w * cols, (h + 24) * len(rows)), (40, 40, 44))
d = ImageDraw.Draw(sheet)
for ri, (name, cells) in enumerate(rows):
    y = ri * (h + 24)
    d.text((8, y + 6), name, fill=(230, 230, 230))
    for ci, (p, fr) in enumerate(cells):
        sheet.paste(Image.open(p).convert("RGB"), (ci * w, y + 24))
        d.text((ci * w + 6, y + 28), f"f{fr}", fill=(20, 20, 20))
sheet.save(sys.argv[2])
shutil.rmtree(sys.argv[1].rsplit("/", 1)[0], ignore_errors=True)
print(sys.argv[2])
