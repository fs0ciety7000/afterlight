"""Hand-built stone kit for the Watch Ruins and the Silent Dial Cloister (no fal), painted with the
village props atlas through tools/blender/kit_mesh.py (stone, wood, terracotta, iron quadrants).

  blender -b --factory-startup -P tools/blender/build_cloister_props.py -- assets/environment

Metrics (docs/content/dungeon.md 2.4): walls on a 4 m grid, 0.8 m thick, 4.5 m high; doors 4 m.
Base at y = 0, front = +Z (glTF), one material per piece. Exported to assets/environment/ruins/.
  wall, wall_broken, pillar, arch (4 m opening frame), stairs (4 x 6 m, 3 m rise), brazier,
  torch_post, fountain, campfire, grille, bell,
  tower_ruin (6 x 6 m collapsed watchtower), rubble, lectern.
"""
import math
import os
import random
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit_mesh import IRON, STONE, TILE, WOOD, box, finish, prism  # noqa: E402

SUB = "ruins"


def new():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    return bm, bm.loops.layers.uv.new("UVMap")


def build(out: str) -> None:
    rnd = random.Random(7)
    # Blender axes: X along the wall, -Y = front (glTF +Z), Z up.
    bm, uv = new()
    box(bm, uv, (0, 0, 0), (4.1, 0.9, 0.4), STONE)  # plinth
    box(bm, uv, (0, 0, 0.4), (4.0, 0.8, 3.7), STONE)
    box(bm, uv, (-1.0, 0, 4.1), (1.96, 0.84, 0.4), STONE)  # uneven coping
    box(bm, uv, (1.0, 0, 4.1), (1.96, 0.84, 0.3), STONE)
    finish("wall", bm, out, SUB)

    bm, uv = new()
    box(bm, uv, (0, 0, 0), (4.1, 0.9, 0.4), STONE)
    box(bm, uv, (0, 0, 0.4), (4.0, 0.8, 1.0), STONE)
    box(bm, uv, (-1.2, 0, 1.4), (1.6, 0.8, 2.0), STONE, top_scale=0.94)
    box(bm, uv, (0.2, 0, 1.4), (1.2, 0.78, 0.9), STONE, top_scale=0.9)
    for k in range(4):  # fallen blocks at the foot, front and back
        x = rnd.uniform(-1.6, 1.6)
        y = rnd.choice((-1, 1)) * rnd.uniform(0.7, 1.0)
        box(bm, uv, (x, y, 0), (0.55, 0.45, 0.35), STONE, yaw=rnd.uniform(0, 3), top_scale=0.9)
    finish("wall_broken", bm, out, SUB)

    bm, uv = new()
    box(bm, uv, (0, 0, 0), (1.0, 1.0, 0.4), STONE, top_scale=0.92)
    prism(bm, uv, (0, 0, 0.4), 0.36, 4.3, 8, STONE, top_scale=0.92, phase=math.pi / 8)
    box(bm, uv, (0, 0, 4.7), (0.8, 0.8, 0.2), STONE, top_scale=1.2)
    box(bm, uv, (0, 0, 4.9), (1.0, 1.0, 0.3), STONE)
    finish("pillar", bm, out, SUB)

    bm, uv = new()  # arch: two piers framing a 4 m opening, round head of voussoirs, top course
    for sx in (-2.4, 2.4):
        box(bm, uv, (sx, 0, 0), (1.0, 1.06, 0.4), STONE)  # proud of the wall face: no z-fight
        box(bm, uv, (sx, 0, 0.4), (0.8, 0.96, 3.1), STONE)
    n = 7
    for k in range(n):
        a = math.pi * (k + 0.5) / n
        cx, cz = -math.cos(a) * 2.25, 3.5 + math.sin(a) * 2.25 - 0.3
        box(bm, uv, (cx, 0, cz), (0.95, 0.82 + 0.04 * (k % 2), 0.6), STONE, tilt=-(a - math.pi / 2))
    box(bm, uv, (0, 0, 5.75), (5.6, 0.8, 0.5), STONE)
    for sx in (-2.1, 2.1):  # spandrels
        box(bm, uv, (sx, 0, 3.52), (1.36, 0.74, 2.26), STONE)
    finish("arch", bm, out, SUB)

    bm, uv = new()  # stairs climbing towards -Y (glTF +Z is the low end... front = bottom step)
    steps = 10
    for k in range(steps):
        y = -3.0 + (k + 0.5) * 0.6
        box(bm, uv, (0, -y, 0), (4.0, 0.6, 0.3 * (k + 1)), STONE)
    for sx in (-2.15, 2.15):
        box(bm, uv, (sx, 0, 0), (0.3, 6.0, 0.6), STONE, top_scale=1.0)
    finish("stairs", bm, out, SUB)

    bm, uv = new()
    box(bm, uv, (0, 0, 0), (0.6, 0.6, 0.2), STONE)
    prism(bm, uv, (0, 0, 0.2), 0.16, 0.7, 6, STONE)
    prism(bm, uv, (0, 0, 0.9), 0.3, 0.28, 8, IRON, top_scale=1.6)
    finish("brazier", bm, out, SUB)

    bm, uv = new()  # standing torch: lamp (fire basket) centre at y = 2.05
    box(bm, uv, (0, 0, 0), (0.45, 0.45, 0.15), STONE)
    prism(bm, uv, (0, 0, 0.15), 0.06, 1.7, 6, WOOD)
    prism(bm, uv, (0, 0, 1.85), 0.12, 0.3, 6, IRON, top_scale=1.7)
    finish("torch_post", bm, out, SUB)

    bm, uv = new()  # fountain: octagonal rim (water drawn by the builder), column and upper bowl
    prism(bm, uv, (0, 0, 0), 1.7, 0.15, 8, STONE, phase=math.pi / 8)
    for k in range(8):
        a = math.pi / 8 + k * math.tau / 8 + math.tau / 16
        r = 1.7 * math.cos(math.pi / 8) - 0.15
        box(bm, uv, (math.cos(a) * r, math.sin(a) * r, 0.15), (1.4, 0.3 - 0.02 * (k % 2), 0.5 + 0.03 * (k % 2)),
            STONE, yaw=a + math.pi / 2)  # alternate heights: no coplanar overlap at the corners
    prism(bm, uv, (0, 0, 0.15), 0.22, 1.25, 8, STONE)
    prism(bm, uv, (0, 0, 1.4), 0.3, 0.25, 8, STONE, top_scale=2.0)
    finish("fountain", bm, out, SUB)

    bm, uv = new()
    for k in range(9):
        a = k * math.tau / 9
        box(bm, uv, (math.cos(a) * 0.75, math.sin(a) * 0.75, 0), (0.32, 0.26, 0.22), STONE,
            yaw=a, top_scale=0.75)
    for k in range(4):
        a = k * math.pi / 4 + 0.3
        box(bm, uv, (0, 0, 0.05), (1.1, 0.14, 0.14), WOOD, yaw=a, roll=0.0, tilt=0.18 * (1 if k % 2 else -1))
    box(bm, uv, (0, 0, 0), (0.6, 0.6, 0.06), IRON)  # ash bed
    finish("campfire", bm, out, SUB)

    bm, uv = new()  # portcullis grille, 4 x 4 m
    for z in (0.0, 1.6, 3.7):
        box(bm, uv, (0, 0, z), (4.0, 0.14, 0.18), IRON)
    for k in range(9):
        x = -1.8 + k * 0.45
        box(bm, uv, (x, 0, 0.02), (0.09, 0.09, 3.93), IRON, top_scale=0.6)
    finish("grille", bm, out, SUB)

    bm, uv = new()  # bell, mouth at y = 0, with its yoke
    prism(bm, uv, (0, 0, 0), 0.95, 0.25, 12, IRON, top_scale=0.86)
    prism(bm, uv, (0, 0, 0.25), 0.82, 0.9, 12, IRON, top_scale=0.72)
    prism(bm, uv, (0, 0, 1.15), 0.59, 0.4, 12, IRON, top_scale=0.6)
    box(bm, uv, (0, 0, 1.5), (0.25, 0.25, 0.3), IRON)
    box(bm, uv, (0, 0, 1.8), (2.6, 0.3, 0.3), WOOD)
    finish("bell", bm, out, SUB)

    # floor dial: tools/blender/build_cloister_decor.py (painted dial texture, bronze hands)

    bm, uv = new()  # collapsed watchtower, 6 x 6 m, walls 0.9 m, door on the front (south)
    h = [[11.5, 9.0, 6.0], [10.0, 7.5, 4.5], [8.0, 5.5, 3.0], [11.0, 10.0, 7.0]]  # back, left, front, right
    for side in range(4):
        for seg in range(3):
            x = -2.0 + seg * 2.0
            hh = h[side][seg]
            if side == 2 and seg == 1:  # door
                box(bm, uv, (0, -2.55, 2.6), (2.0, 0.9, hh - 2.6), STONE)
                continue
            if side == 0:
                box(bm, uv, (x, 2.55, 0), (2.0, 0.9, hh), STONE, top_scale=0.98)
            elif side == 2:
                box(bm, uv, (x, -2.55, 0), (2.0, 0.9, hh), STONE, top_scale=0.98)
            elif side == 1:
                box(bm, uv, (-2.55, -x * 0.7, 0), (0.9, 1.4, hh), STONE, top_scale=0.98)
            else:
                box(bm, uv, (2.55, x * 0.7, 0), (0.9, 1.4, hh), STONE, top_scale=0.98)
    for sx, sy in ((-3.1, 3.1), (3.1, 3.1), (3.1, -3.1)):
        box(bm, uv, (sx, sy, 0), (1.0, 1.0, 5.0), STONE, top_scale=0.7)  # buttresses
    box(bm, uv, (1.0, 1.0, 6.5), (4.0, 0.2, 0.2), WOOD, tilt=0.4)  # a fallen beam inside
    for k in range(6):
        box(bm, uv, (rnd.uniform(-3, 3), -rnd.uniform(3.4, 4.6), 0), (0.7, 0.6, 0.45), STONE,
            yaw=rnd.uniform(0, 3), top_scale=0.85)
    finish("tower_ruin", bm, out, SUB)

    bm, uv = new()
    for k in range(8):
        box(bm, uv, (rnd.uniform(-0.8, 0.8), rnd.uniform(-0.6, 0.6), rnd.choice((0, 0, 0.3))),
            (rnd.uniform(0.5, 0.9), rnd.uniform(0.4, 0.7), rnd.uniform(0.3, 0.55) + 0.013 * k), STONE,
            yaw=rnd.uniform(0, 3), top_scale=0.85)
    finish("rubble", bm, out, SUB)

    bm, uv = new()  # lectern with the watch roll (open register)
    box(bm, uv, (0, 0, 0), (0.5, 0.5, 0.1), WOOD)
    box(bm, uv, (0, 0, 0.1), (0.16, 0.16, 0.95), WOOD)
    box(bm, uv, (0, 0, 1.02), (0.7, 0.5, 0.06), WOOD, roll=-0.35)
    box(bm, uv, (0, -0.03, 1.09), (0.6, 0.42, 0.04), TILE, roll=-0.35)
    finish("lectern", bm, out, SUB)


if __name__ == "__main__":
    build(os.path.abspath(sys.argv[sys.argv.index("--") + 1]))
