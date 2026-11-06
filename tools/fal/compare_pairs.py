"""Before / after sheet: one row per pair of images, left = before, right = after, centre crop optional.

  python3 tools/fal/compare_pairs.py out.jpg "Before" "After" a1.jpg b1.jpg [a2.jpg b2.jpg ...] [--crop x0,y0,x1,y1]
"""
import sys

from PIL import Image, ImageDraw

args = sys.argv[1:]
crop = None
if "--crop" in args:
    i = args.index("--crop")
    crop = tuple(int(v) for v in args[i + 1].split(","))
    del args[i:i + 2]
out, left, right, files = args[0], args[1], args[2], args[3:]
pairs = list(zip(files[::2], files[1::2]))
W = 800
ims = [[Image.open(f).convert("RGB") for f in p] for p in pairs]
if crop:
    ims = [[im.crop(crop) for im in p] for p in ims]
H = round(ims[0][0].height * W / ims[0][0].width)
sheet = Image.new("RGB", (W * 2 + 4, (H + 4) * len(ims) + 36), (36, 34, 40))
d = ImageDraw.Draw(sheet)
d.text((12, 10), left, fill=(235, 235, 235))
d.text((W + 16, 10), right, fill=(235, 235, 235))
for r, p in enumerate(ims):
    for c, im in enumerate(p):
        sheet.paste(im.resize((W, H)), (c * (W + 4), 36 + r * (H + 4)))
    d.text((12, 36 + r * (H + 4) + 6), pairs[r][1].rsplit("/", 1)[-1], fill=(255, 255, 255))
sheet.save(out, quality=86)
print(out, sheet.size)
