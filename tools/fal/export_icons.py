#!/usr/bin/env python3
"""Export icon cut-outs (RGBA PNG) to square WebP game icons and a contact sheet on dark and light UI.

  python3 tools/fal/export_icons.py art/source/icons/cut assets/textures/icons 128 art/source/icons/icons_contact.jpg
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> None:
    src, dst, size, sheet = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), Path(sys.argv[4])
    dst.mkdir(parents=True, exist_ok=True)
    files = sorted(src.glob("*.png"))
    inner = round(size * 0.9)  # 5 % margin each side: glows stay inside the tile
    tiles = []
    for f in files:
        im = Image.open(f).convert("RGBA")
        im.thumbnail((inner, inner), Image.LANCZOS)
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.paste(im, ((size - im.width) // 2, (size - im.height) // 2))
        out.save(dst / f"{f.stem}.webp", "WEBP", quality=90, method=6)
        tiles.append((f.stem, out))
    # contact sheet: each icon at 48 px on the night surface and at 128 px on the day surface
    cols = 8
    rows = (len(tiles) + cols - 1) // cols
    cw, ch = 200, 210
    board = Image.new("RGB", (cols * cw, rows * ch), "#f3ead6")
    d = ImageDraw.Draw(board)
    for i, (name, im) in enumerate(tiles):
        x, y = (i % cols) * cw, (i // cols) * ch
        board.paste(im, (x + 8, y + 8), im)
        d.rectangle([x + 140, y + 8, x + 192, y + 60], fill="#1c2431")
        small = im.resize((48, 48), Image.LANCZOS)
        board.paste(small, (x + 142, y + 10), small)
        d.text((x + 8, y + 150), name, fill="#2b2620")
    board.save(sheet, quality=88)
    print(len(tiles), "icons ->", dst, ";", sheet)


if __name__ == "__main__":
    main()
