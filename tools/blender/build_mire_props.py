"""Small hand-built pieces for the Lantern Mire (no fal), painted with the village props atlas.

  blender -b --factory-startup -P tools/blender/build_mire_props.py -- assets/environment

Atlas: art/source/env/tex/village_props_atlas.png (tools/blender/build_village_props.py atlas), quadrants
stone (0, .5) and wood (.5, .5). One material per piece, WebP; front = +Z (glTF).
  boardwalk : 2 x 4 m pontoon section along Z, plank deck with its TOP at y = 0, piles down to y = -1.3,
              two short mooring posts (~250 tris). Placed at deck height by the location builder.
  beacon    : the drowned beacon of the mire, a 6.5 m mast on a stone footing under a wide lantern head
              (iron ring, four warm panes, pointed roof; lamp centre at y = 7.35) (~350 tris).
  ferry_hut : the ferryman's plank cabin on piles, 3.6 x 3.0 m, terracotta roof, porch (~400 tris).
"""
import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit_mesh import IRON, STONE, TILE, WOOD, box, finish  # noqa: E402


def build(out_dir: str) -> None:
    # Blender: -Y = glTF +Z (front), Z up. Boardwalk runs along Y (4 m), 2 m wide.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    for k in range(8):  # eight planks across the walk, slightly uneven
        y = -1.75 + k * 0.5
        box(bm, uvl, (0.03 * ((k * 7) % 3 - 1), y, -0.08), (2.0 + 0.06 * (k % 2), 0.46, 0.08), WOOD,
            tilt=0.012 * ((k * 5) % 3 - 1))
    for sx in (-0.85, 0.85):  # stringers
        box(bm, uvl, (sx, 0, -0.22), (0.14, 4.0, 0.14), WOOD)
    for sx in (-0.85, 0.85):  # piles
        for sy in (-1.6, 1.6):
            box(bm, uvl, (sx, sy, -1.3), (0.18, 0.18, 1.08), WOOD, top_scale=0.9)
    for sx, sy in ((-0.95, 1.7), (0.95, -1.7)):  # mooring posts above the deck
        box(bm, uvl, (sx, sy, -0.2), (0.16, 0.16, 0.85), WOOD, top_scale=0.8)
    finish("boardwalk", bm, out_dir, merge=False)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    box(bm, uvl, (0, 0, -0.6), (1.5, 1.5, 1.1), STONE, top_scale=0.8)  # footing, half sunk
    box(bm, uvl, (0, 0, 0.4), (0.36, 0.36, 6.45), WOOD, top_scale=0.8)  # mast
    for a in (0.0, math.pi * 0.5):  # crossed brackets under the lamp head
        box(bm, uvl, (0, 0, 6.3), (1.3, 0.12, 0.14), WOOD, yaw=a)
    # lamp head: a wide lantern (1.1 m) read from the 50 degree camera: iron floor and ring,
    # four warm panes, corner posts, pointed roof and a finial (lamp centre at y = 7.35)
    box(bm, uvl, (0, 0, 6.45), (1.15, 1.15, 0.12), IRON, top_scale=1.08)
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            box(bm, uvl, (sx, sy, 6.57), (0.1, 0.1, 1.0), IRON)
    for k in range(4):  # panes, set 4 cm inside the posts
        a = k * math.pi * 0.5
        box(bm, uvl, (math.sin(a) * 0.46, -math.cos(a) * 0.46, 6.62), (0.86, 0.04, 0.88), TILE, yaw=a)
    box(bm, uvl, (0, 0, 7.57), (1.25, 1.25, 0.1), IRON)  # top ring
    box(bm, uvl, (0, 0, 7.67), (1.3, 1.3, 0.62), TILE, top_scale=0.12)  # roof
    box(bm, uvl, (0, 0, 8.25), (0.12, 0.12, 0.35), IRON, top_scale=0.4)  # finial
    for a in (0.6, -0.9):  # two leaning stakes around the footing
        box(bm, uvl, (math.cos(a) * 0.9, math.sin(a) * 0.9, -0.5), (0.12, 0.12, 1.6), WOOD, tilt=0.25)
    finish("beacon", bm, out_dir)

    # ferryman's hut: 3.6 x 3.0 m plank cabin on short piles, door on the front (+Z glTF) gable,
    # terracotta roof with the ridge front-to-back, a porch with a mooring post (~400 tris)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    for sx in (-1.6, 0, 1.6):
        for sy in (-1.3, 1.3, -2.6):
            box(bm, uvl, (sx, sy, -0.6), (0.2, 0.2, 0.9), WOOD, top_scale=0.9)  # piles
    box(bm, uvl, (0, -0.65, 0.15), (3.9, 4.3, 0.15), WOOD)  # floor and porch
    wh = 2.1
    box(bm, uvl, (0, 1.42, 0.3), (3.28, 0.16, wh), WOOD)  # back wall
    for sx in (-1.72, 1.72):
        box(bm, uvl, (sx, 0, 0.3), (0.16, 2.84, wh), WOOD)  # side walls
    for sx in (-1.07, 1.07):
        box(bm, uvl, (sx, -1.42, 0.3), (1.14, 0.16, wh), WOOD)  # front wall either side of the door
    box(bm, uvl, (0, -1.42, 0.3 + 1.75), (1.0, 0.16, wh - 1.75), WOOD)  # lintel
    box(bm, uvl, (0, -1.5, 0.3), (1.0, 0.04, 0.04), IRON)  # threshold
    for sy in (-1.42, 1.42):  # gables
        box(bm, uvl, (0, sy, 0.3 + wh), (3.6, 0.16, 1.15), WOOD, top_sx=0.0)
    box(bm, uvl, (1.79, 0.3, 1.2), (0.04, 0.8, 0.6), IRON)  # shuttered window
    a, hx = 0.57, 1.2
    for s in (-1, 1):  # roof planes, ridge along y
        c = (s * hx * math.cos(a) * 0.98, -0.1, 0.3 + wh + 1.15 - hx * math.sin(a) - 0.06)
        box(bm, uvl, c, (2.4, 3.6, 0.12), TILE, tilt=s * a)
    box(bm, uvl, (-1.9, -2.6, -0.2), (0.16, 0.16, 1.2), WOOD, top_scale=0.8)  # mooring post
    box(bm, uvl, (1.2, -2.2, 0.3), (0.5, 0.4, 0.45), WOOD)  # crate on the porch
    finish("ferry_hut", bm, out_dir)


if __name__ == "__main__":
    build(os.path.abspath(sys.argv[sys.argv.index("--") + 1]))
