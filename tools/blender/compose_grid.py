"""Compose the tiles written by qa_props_sheet.py into one labelled grid (system python, PIL).

  python3 tools/blender/compose_grid.py <tiles.txt> out.jpg
"""
import sys

from PIL import Image, ImageDraw

rows = [[c.split("|") for c in line.rstrip("\n").split("\t")] for line in open(sys.argv[1]) if line.strip()]
w, h = Image.open(rows[0][0][2]).size
sheet = Image.new("RGB", (w * len(rows[0]), (h + 24) * len(rows)), (36, 36, 42))
d = ImageDraw.Draw(sheet)
for j, row in enumerate(rows):
    for i, (label, view, path) in enumerate(row):
        sheet.paste(Image.open(path).convert("RGB"), (i * w, j * (h + 24) + 24))
        d.text((i * w + 10, j * (h + 24) + 6), f"{label} - {view}", fill=(230, 230, 230))
sheet.save(sys.argv[2], quality=88)
print(sys.argv[2])
