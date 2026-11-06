"""Line up GLBs (Fern first, then the NPCs) under the game camera and render one image (Workbench, textured).

  blender -b --factory-startup -P tools/blender/render_npc_lineup.py -- out.png fern.glb a.glb b.glb ...
      [--distance 11] [--spacing 0.45]

Camera as game/world/explore/camera_rig.gd: pitch 50 deg, vertical FOV 40 deg, distance 11 m (+0.8 m up),
on glTF +Z looking towards -Z, 1600 x 900. Every model is turned to show its front to the camera:
Fern (first file) faces -Z, so she is turned 180 deg; the NPC GLBs face +Z already.
A second render at 6.5 m (the closest zoom) is written next to out.png as <out>_6m.png.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
opts = {}
for k in ("--distance", "--spacing"):
    if k in argv:
        i = argv.index(k)
        opts[k] = float(argv[i + 1])
        del argv[i:i + 2]
out, files = os.path.abspath(argv[0]), argv[1:]
dist = opts.get("--distance", 11.0)
spacing = opts.get("--spacing", 0.45)  # gap between bounding boxes (m)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
groups = []
for k, f in enumerate(files):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(f))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.type == "MESH" and o.name.startswith("Icosphere"):  # importer bone-shape helper
            o.hide_render = True
    roots = [o for o in new if o.parent is None]
    if k == 0:  # Fern faces -Z (glTF) = +Y (Blender): turn her to the camera
        for r in roots:
            r.rotation_mode = "XYZ"
            r.rotation_euler.z += math.pi
    bpy.context.view_layer.update()
    xs = [(o.matrix_world @ Vector(c)).x for o in new if o.type == "MESH" and not o.hide_render for c in o.bound_box]
    groups.append((roots, min(xs), max(xs)))
# side by side: each model's width plus the gap
widths = [max(hi - lo, 0.5) for _, lo, hi in groups]
total = sum(widths) + spacing * (len(groups) - 1)
x = -total / 2
for (roots, lo, hi), w in zip(groups, widths):
    for r in roots:
        r.location.x += x + w / 2 - (lo + hi) / 2
    x += w + spacing
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
ground = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.diffuse_color = (0.42, 0.52, 0.36, 1)
ground.data.materials.append(gm)

cam_data = bpy.data.cameras.new("cam")
cam_data.sensor_fit = "VERTICAL"
cam_data.angle = math.radians(40)
cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.show_shadows = True
sc.display.shading.show_cavity = False
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x, sc.render.resolution_y = 1600, 900
sc.render.film_transparent = False
world = bpy.data.worlds.new("w")
world.color = (0.62, 0.66, 0.78)
sc.world = world


def shoot(d, path):
    p = math.radians(50)
    cam.location = (0, -math.cos(p) * d, math.sin(p) * d + 0.8)
    cam.rotation_euler = (math.radians(90) - p, 0, 0)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("@@SAVED", path)


shoot(dist, out)
shoot(6.5, os.path.splitext(out)[0] + "_6m.png")
