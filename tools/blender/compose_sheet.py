"""Compose qa_*.png views into one labelled sheet. Usage: python3 compose_sheet.py out.png a.png b.png ..."""
import sys
from PIL import Image, ImageDraw

out, files = sys.argv[1], sys.argv[2:]
ims = [Image.open(f).convert("RGB") for f in files]
w, h = ims[0].size
sheet = Image.new("RGB", (w * len(ims), h + 40), (40, 40, 44))
d = ImageDraw.Draw(sheet)
for i, (f, im) in enumerate(zip(files, ims)):
    sheet.paste(im.resize((w, h)), (i * w, 40))
    d.text((i * w + 12, 12), f.rsplit("/", 1)[-1].replace("qa_", "").replace(".png", ""), fill=(230, 230, 230))
sheet.save(out)
print(out)
