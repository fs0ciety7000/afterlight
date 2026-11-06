"""Turn raw Meshy GLBs into game-ready environment props (Godot / web).

  blender -b --factory-startup -P tools/blender/build_env_kit.py -- art/source/env/raw assets/environment [names...]

Per prop: join, clean, scale to real size, optional yaw fix, decimate to the budget, sharp edges by angle
for hard-surface pieces, pivot at the ground centre, single material with the flattened 1K base colour
(art/source/env/tex/<name>.png, made by tools/fal/process_env_textures.py props), GLB with JPEG.
Writes assets/environment/kit_manifest.json (tris, size, file size).
"""

import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

# name: (category, size_axis, size_m, max_tris, yaw_deg, hard_surface)
# size_axis "h" = height, "l" = longest horizontal side
KIT = {
    "house_a": ("buildings", "h", 7.6, 6000, 0, True),
    "house_b": ("buildings", "h", 6.0, 6000, 0, True),
    "house_c": ("buildings", "h", 8.8, 6000, 0, True),
    "well": ("props", "h", 2.7, 2500, 0, True),
    "fence": ("props", "l", 2.4, 900, 0, True),
    "stall": ("props", "h", 2.8, 3000, 0, True),
    "cart": ("props", "l", 2.4, 2500, 0, True),
    "lantern": ("props", "h", 2.9, 900, 0, True),
    "barrels": ("props", "h", 1.15, 1800, 0, True),
    "bridge": ("props", "l", 7.5, 3000, 0, True),
    "birch_a": ("vegetation", "h", 7.0, 2600, 0, False),
    "birch_b": ("vegetation", "h", 9.0, 3000, 0, False),
    # forest variants: same models at a lower budget for dense MultiMesh scatter
    "birch_a_lo": ("vegetation", "h", 7.0, 1100, 0, False),
    "birch_b_lo": ("vegetation", "h", 9.0, 1200, 0, False),
    "bush": ("vegetation", "h", 1.3, 1200, 0, False),
    "rock_a": ("rocks", "h", 1.7, 1000, 0, False),
    "rock_b": ("rocks", "h", 0.7, 700, 0, False),
}

argv = sys.argv[sys.argv.index("--") + 1:]
raw_dir, out_dir = os.path.abspath(argv[0]), os.path.abspath(argv[1])
only = set(argv[2:])
tex_dir = os.path.join(os.path.dirname(raw_dir), "tex")
manifest_path = os.path.join(out_dir, "kit_manifest.json")
manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tri_count(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def build(name: str) -> None:
    cat, axis, size, max_tris, yaw, hard = KIT[name]
    out_name = name
    name = name.removesuffix("_lo")
    src = os.path.join(raw_dir, name, f"{name}_meshy_0.glb")
    # Tripo retries (for shapes Meshy flattened) win over the Meshy output when present
    tripo = os.path.join(os.path.dirname(raw_dir), "raw_tripo", name, f"{name}_tripo_0.glb")
    if os.path.exists(tripo):
        src = tripo
    if not os.path.exists(src):
        print("missing", src)
        return
    reset()
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    src_tex = os.path.join(tex_dir, f"{name}_src.png")
    if src == tripo and not os.path.exists(src_tex):
        # Tripo embeds its 4K base colour: save a 1K copy for tools/fal/process_env_textures.py props
        emb = next(i for i in bpy.data.images if i.size[0] > 0 and i.name.startswith("Color"))
        emb.scale(1024, 1024)
        emb.filepath_raw = src_tex
        emb.file_format = "PNG"
        emb.save()
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.rotation_mode = "XYZ"
    obj.rotation_euler.z += math.radians(yaw)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # clean: merge doubles, drop tiny floating islands (Meshy leaves specks)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    islands = []
    seen = set()
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            isl.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        islands.append(isl)
    total = len(bm.faces)
    drop = [f for isl in islands if len(isl) < max(8, total * 0.002) for f in isl]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()

    # scale to real size
    lo = Vector([min(v.co[i] for v in obj.data.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in obj.data.vertices) for i in range(3)])
    dims = hi - lo
    ref = dims.z if axis == "h" else max(dims.x, dims.y)
    k = size / ref
    # pivot: centre of the footprint, on the ground
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in obj.data.vertices:
        v.co = (v.co - centre) * k
    obj.data.update()

    # decimate to budget
    tris = tri_count(obj)
    if tris > max_tris:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max_tris / tris
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    tris_after = tri_count(obj)

    # normals: smooth for organic shapes (soft toon bands); hard-surface keeps sharp creases
    for p in obj.data.polygons:
        p.use_smooth = True
    if hard:
        obj.data.set_sharp_from_angle(angle=math.radians(40))

    # material: flattened 1K base colour only, no PBR maps
    mat = bpy.data.materials.new(f"env_{name}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    img_node = nt.nodes.new("ShaderNodeTexImage")
    tex_path = os.path.join(tex_dir, f"{name}.png")
    if not os.path.exists(tex_path):
        tex_path = src_tex
    img = bpy.data.images.load(tex_path)
    img.name = f"{name}_albedo"
    img_node.image = img
    nt.links.new(img_node.outputs["Color"], bsdf.inputs["Base Color"])
    obj.data.materials.clear()
    obj.data.materials.append(mat)

    # remove UV maps beyond the first, colour attributes (not used)
    while len(obj.data.uv_layers) > 1:
        obj.data.uv_layers.remove(obj.data.uv_layers[-1])
    for ca in list(obj.data.color_attributes):
        obj.data.color_attributes.remove(ca)

    dst_dir = os.path.join(out_dir, cat)
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, f"{out_name}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=True, export_apply=True,
        export_image_format="JPEG", export_jpeg_quality=86, export_animations=False,
        export_materials="EXPORT", export_normals=True, export_texcoords=True,
        export_tangents=False, export_yup=True,
    )
    lo = Vector([min(v.co[i] for v in obj.data.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in obj.data.vertices) for i in range(3)])
    name = out_name
    manifest[name] = {
        "file": os.path.relpath(dst, os.path.dirname(out_dir)),
        "tris_raw": tris, "tris": tris_after,
        # Godot axes: x, y (up), z = -blender y
        "size_m": [round(hi.x - lo.x, 2), round(hi.z - lo.z, 2), round(hi.y - lo.y, 2)],
        "kb": round(os.path.getsize(dst) / 1024),
    }
    print("built", name, manifest[name])


for n in KIT:
    if not only or n in only:
        build(n)
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=1, sort_keys=True)
